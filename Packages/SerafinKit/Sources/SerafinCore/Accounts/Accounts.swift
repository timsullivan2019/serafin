import Foundation
import JellyfinAPI
import Nuke
import os

/// Every server and user on this device, and the account the app is using.
///
/// This is SerafinCore's front door for adding servers, signing in with Quick Connect or a password, switching
/// accounts, signing out and removing servers. It keeps the server list, the tokens and the certificate pins in
/// step, and hands out one `JellyfinClient`, one ``LibraryRepository`` and one ``Artwork`` per account.
public actor Accounts {
    /// How many polls in a row may fail to reach the server before Quick Connect gives up.
    static let pollFailureTolerance = 3
    /// How long sign-out waits for the server before settling for signing out on this device alone.
    static let logoutTimeout: TimeInterval = 10

    private static let logger = Logger(serafinCategory: "accounts")

    private let serverStore: ServerStore
    private let identity: DeviceIdentity
    private let sessions: SessionStore
    private let pins: PinStore
    private let pinning: PinningDelegate
    private let clients: ClientFactory
    private let connector: ServerConnector
    private let images: ImagePipeline

    /// One client per signed-in account, so everything signed in as that user shares its connections.
    private var accountClients: [SessionKey: JellyfinClient] = [:]
    /// One library per signed-in account, so every screen shares its cache.
    private var libraries: [SessionKey: LibraryRepository] = [:]
    /// One anonymous client per server, for signing in.
    private var signInClients: [String: JellyfinClient] = [:]

    /// Creates the accounts, with everything they need built from a few inputs.
    ///
    /// - Parameters:
    ///   - secrets: Where tokens, pins and the device ID are kept. The app passes a ``KeychainSecretStore``.
    ///   - deviceName: The device name servers show, such as "iPhone".
    ///   - version: The app version servers show.
    ///   - serverStore: Where the server list is saved.
    ///   - defaults: Where the current selection is saved. Tests pass a throwaway suite.
    ///   - imageDiskCache: Whether images are cached on disk, up to 200 MB in Caches. Tests turn it off.
    ///   - sessionConfiguration: Makes the `URLSession` configuration for every request. Tests pass one with a stub
    ///     protocol.
    public init(
        secrets: any SecretStore,
        deviceName: String,
        version: String = DeviceIdentity.bundleVersion,
        serverStore: ServerStore = ServerStore(),
        defaults: sending UserDefaults = .standard,
        imageDiskCache: Bool = true,
        sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
    ) {
        let identity = DeviceIdentity(secrets: secrets, deviceName: deviceName, version: version)
        let sessions = SessionStore(secrets: secrets, defaults: defaults)
        let pins = PinStore(secrets: secrets)
        let pinning = PinningDelegate(pins: pins)
        self.serverStore = serverStore
        self.identity = identity
        self.sessions = sessions
        self.pins = pins
        self.pinning = pinning
        self.clients = ClientFactory(
            identity: identity,
            sessions: sessions,
            sessionDelegate: { _ in pinning },
            sessionConfiguration: sessionConfiguration
        )
        self.connector = ServerConnector(pinning: pinning, sessionConfiguration: sessionConfiguration)
        self.images = ImagePipeline.serafin(
            pinning: pinning,
            diskCacheName: imageDiskCache ? ImagePipeline.diskCacheName : nil,
            sessionConfiguration: sessionConfiguration()
        )
    }

    // MARK: - Servers

    /// Every saved server with its signed-in users, in the order the servers were added.
    public func servers() async throws -> [Server] {
        try await serverStore.servers()
    }

    /// Finds the Jellyfin server at `address`, as ``ServerConnector`` does, with this device's certificate pins.
    public func connect(to address: ServerAddress) async throws -> ConnectedServer {
        try await connector.connect(to: address)
    }

    /// Pins a certificate the server at `address` presented, once the user has checked its fingerprint, so the next
    /// attempt to connect succeeds.
    public func trust(_ certificate: CertificateFingerprint, for address: ServerAddress) throws {
        guard let host = address.url.host() else { throw SerafinError.invalidAddress }
        try pins.setPin(certificate, for: host)
        pinning.forgetRejection(for: host)
    }

    /// Saves a server that answered. A server saved before under the same ID keeps its users and takes the new
    /// address and name.
    @discardableResult
    public func add(_ connected: ConnectedServer) async throws -> Server {
        var server = connected.server
        if let saved = try await serverStore.server(id: server.id) {
            server.users = saved.users
            server.lastUserID = saved.lastUserID
            if saved.url != server.url {
                forgetClients(forServer: server.id)
            }
        }
        try await serverStore.save(server)
        return server
    }

    /// Signs every user out of a server and forgets it. Its certificate pin goes too, unless another saved server
    /// uses the same host.
    public func remove(serverID: String) async throws {
        guard let server = try await serverStore.server(id: serverID) else { return }
        var endings: [SessionEnding] = []
        for user in server.users {
            if let ending = try await signOutLocally(SessionKey(serverID: serverID, userID: user.id)) {
                endings.append(ending)
            }
        }
        try await serverStore.remove(id: serverID)
        forgetClients(forServer: serverID)
        if let host = server.url.host(), try await !serverStore.servers().contains(where: { $0.url.host() == host }) {
            try pins.removePin(for: host)
        }
        await Self.endSessions(endings, clients: clients)
    }

    // MARK: - Signing in

    /// Asks `server` for a Quick Connect code to show the user.
    ///
    /// - Throws: ``SerafinError/quickConnectDisabled`` when the server has Quick Connect turned off, so the user
    ///   signs in with a password instead.
    public func startQuickConnect(on server: Server) async throws -> QuickConnectRequest {
        let client = try await signInClient(for: server)
        do {
            let enabled = try JSONDecoder().decode(
                Bool.self, from: await client.send(Paths.getQuickConnectEnabled).value)
            guard enabled else { throw SerafinError.quickConnectDisabled }
            let result = try await client.send(Paths.initiateQuickConnect).value
            guard let code = result.code, !code.isEmpty, let secret = result.secret, !secret.isEmpty else {
                throw SerafinError.unexpectedResponse(status: nil)
            }
            return QuickConnectRequest(code: code, server: server, secret: secret)
        } catch {
            throw translate(error, from: server, statuses: [401: .quickConnectDisabled])
        }
    }

    /// Waits until the user approves a Quick Connect code, then signs in and makes the account current.
    ///
    /// Cancelling the calling task stops the waiting.
    ///
    /// - Parameters:
    ///   - request: The request from ``startQuickConnect(on:)``.
    ///   - interval: How often to ask the server whether the code has been approved.
    ///   - limit: How long to wait. Jellyfin forgets a code after ten minutes.
    /// - Throws: ``SerafinError/quickConnectExpired`` when the code expires or the time runs out first.
    public func finishQuickConnect(
        _ request: QuickConnectRequest,
        pollingEvery interval: Duration = .seconds(5),
        giveUpAfter limit: Duration = .seconds(600)
    ) async throws -> Account {
        let client = try await signInClient(for: request.server)
        let deadline = ContinuousClock.now.advanced(by: limit)
        do {
            var failures = 0
            while true {
                try await Task.sleep(for: interval)
                do {
                    let state = try await client.send(Paths.getQuickConnectState(secret: request.secret)).value
                    failures = 0
                    if state.isAuthenticated == true { break }
                } catch let error as URLError {
                    failures += 1
                    if failures > Self.pollFailureTolerance { throw error }
                }
                guard ContinuousClock.now < deadline else { throw SerafinError.quickConnectExpired }
            }
        } catch {
            throw translate(
                error, from: request.server, statuses: [401: .quickConnectDisabled, 404: .quickConnectExpired])
        }
        do {
            let body = QuickConnectDto(secret: request.secret)
            let result = try await client.send(Paths.authenticateWithQuickConnect(body)).value
            return try await signedIn(result, to: request.server)
        } catch {
            throw translate(
                error, from: request.server, statuses: [401: .quickConnectExpired, 404: .quickConnectExpired])
        }
    }

    /// Signs in with a username and password, saves the token and makes the account current.
    ///
    /// The password goes to the server once and is kept nowhere.
    ///
    /// - Throws: ``SerafinError/invalidCredentials`` when the server refuses them.
    public func signIn(to server: Server, username: String, password: String) async throws -> Account {
        let client = try await signInClient(for: server)
        do {
            let body = AuthenticateUserByName(pw: password, username: username)
            let result = try await client.send(Paths.authenticateUserByName(body)).value
            return try await signedIn(result, to: server)
        } catch {
            throw translate(error, from: server, statuses: [401: .invalidCredentials])
        }
    }

    // MARK: - Accounts

    /// The account the app is using, or nil when no one is signed in. A selection whose user or token has gone is
    /// cleared.
    public func current() async throws -> Account? {
        guard let key = await sessions.current else { return nil }
        if let account = try await account(for: key) {
            return account
        }
        await sessions.setCurrent(nil)
        return nil
    }

    /// Makes another signed-in account the current one.
    ///
    /// - Throws: ``SerafinError/notSignedIn`` when that user has no saved sign-in on that server.
    @discardableResult
    public func switchTo(_ key: SessionKey) async throws -> Account {
        guard let account = try await account(for: key) else { throw SerafinError.notSignedIn }
        await sessions.setCurrent(key)
        try await serverStore.setLastUser(key.userID, forServer: key.serverID)
        return account
    }

    /// Signs a user out: forgets their token and removes them from the server's users on this device, then asks
    /// the server to end the session.
    ///
    /// The device is signed out even when the server cannot be reached. The server gets ``logoutTimeout`` seconds
    /// to answer.
    public func signOut(_ key: SessionKey) async throws {
        guard let ending = try await signOutLocally(key) else { return }
        await Self.endSessions([ending], clients: clients)
    }

    /// The client signed in as `account`, shared by everything that talks to the server as that user.
    ///
    /// - Throws: ``SerafinError/notSignedIn`` when the account has no saved token.
    public func client(for account: Account) async throws -> JellyfinClient {
        if let cached = accountClients[account.key] {
            return cached
        }
        _ = try TransportPolicy.security(of: account.server.url)
        guard let token = try await sessions.token(for: account.key) else { throw SerafinError.notSignedIn }
        let client = try await clients.client(for: account.server, accessToken: token)
        accountClients[account.key] = client
        return client
    }

    /// The library of `account`, shared by every screen that shows it.
    ///
    /// - Throws: ``SerafinError/notSignedIn`` when the account has no saved token.
    public func library(for account: Account) async throws -> LibraryRepository {
        if let cached = libraries[account.key] {
            return cached
        }
        let client = try await client(for: account)
        if let cached = libraries[account.key] {
            return cached
        }
        let library = LibraryRepository(client: client, userID: account.user.id, errors: ServerErrors(pinning: pinning))
        libraries[account.key] = library
        return library
    }

    /// Loads `account`'s images through the app's one image pipeline.
    ///
    /// - Throws: ``SerafinError/notSignedIn`` when the account has no saved token.
    public func artwork(for account: Account) async throws -> Artwork {
        _ = try TransportPolicy.security(of: account.server.url)
        guard let token = try await sessions.token(for: account.key) else { throw SerafinError.notSignedIn }
        let authorization = try await identity.authorizationHeader(accessToken: token)
        return Artwork(urls: ImageURLs(serverURL: account.server.url), pipeline: images, authorization: authorization)
    }

    // MARK: - Helpers

    /// What it takes to end a session on its server after the device has forgotten it.
    private struct SessionEnding: Sendable {
        let server: Server
        let token: String
        let client: JellyfinClient?
    }

    /// The saved account for `key`, when its server, user and token all exist.
    private func account(for key: SessionKey) async throws -> Account? {
        guard
            let server = try await serverStore.server(id: key.serverID),
            let user = server.user(id: key.userID),
            try await sessions.token(for: key) != nil
        else { return nil }
        return Account(server: server, user: user)
    }

    /// Saves what a successful sign-in returned and makes the account current.
    private func signedIn(_ result: AuthenticationResult, to server: Server) async throws -> Account {
        guard
            let token = result.accessToken, !token.isEmpty,
            let userID = result.user?.id, !userID.isEmpty
        else { throw SerafinError.unexpectedResponse(status: nil) }
        let user = ServerUser(id: userID, name: result.user?.name ?? "")
        var saved = try await serverStore.server(id: server.id) ?? server
        if let index = saved.users.firstIndex(where: { $0.id == userID }) {
            saved.users[index] = user
        } else {
            saved.users.append(user)
        }
        saved.lastUserID = userID
        let account = Account(server: saved, user: user)
        try await sessions.setToken(token, for: account.key)
        do {
            try await serverStore.save(saved)
        } catch {
            try? await sessions.removeToken(for: account.key)
            throw error
        }
        accountClients[account.key] = nil
        libraries[account.key] = nil
        await sessions.setCurrent(account.key)
        return account
    }

    /// Forgets a user's token, their place in the server's users and their client, and returns what is needed to
    /// end the session on the server, or nil when the user had no token.
    private func signOutLocally(_ key: SessionKey) async throws -> SessionEnding? {
        let token = try await sessions.token(for: key)
        try await sessions.removeToken(for: key)
        let client = accountClients.removeValue(forKey: key)
        libraries[key] = nil
        guard var server = try await serverStore.server(id: key.serverID) else { return nil }
        server.users.removeAll { $0.id == key.userID }
        if server.lastUserID == key.userID {
            server.lastUserID = server.users.last?.id
        }
        try await serverStore.save(server)
        guard let token else { return nil }
        return SessionEnding(server: server, token: token, client: client)
    }

    /// Asks each server to end a session this device has already forgotten, all at once. Failures are logged, not
    /// thrown: the device is signed out either way.
    private static func endSessions(_ endings: [SessionEnding], clients: ClientFactory) async {
        await withTaskGroup(of: Void.self) { group in
            for ending in endings {
                group.addTask {
                    do {
                        let client: JellyfinClient
                        if let cached = ending.client {
                            client = cached
                        } else {
                            client = try await clients.client(for: ending.server, accessToken: ending.token)
                        }
                        try await client.send(
                            Paths.reportSessionEnded, configure: { $0.timeoutInterval = logoutTimeout })
                    } catch {
                        logger.error(
                            "Could not end a session on \(ending.server.url, privacy: .private): \(error.localizedDescription, privacy: .private)"
                        )
                    }
                }
            }
        }
    }

    /// The anonymous client for signing in to `server`, made once per server and address.
    private func signInClient(for server: Server) async throws -> JellyfinClient {
        _ = try TransportPolicy.security(of: server.url)
        if let cached = signInClients[server.id], cached.configuration.url == server.url {
            return cached
        }
        let client = try await clients.client(for: server, accessToken: nil)
        signInClients[server.id] = client
        return client
    }

    private func forgetClients(forServer serverID: String) {
        signInClients[serverID] = nil
        accountClients = accountClients.filter { $0.key.serverID != serverID }
        libraries = libraries.filter { $0.key.serverID != serverID }
    }

    /// Turns an error from talking to `server` into a ``SerafinError``, or passes a cancellation on.
    private func translate(_ error: any Error, from server: Server, statuses: [Int: SerafinError] = [:]) -> any Error {
        ServerErrors(pinning: pinning).translate(error, from: server.url, statuses: statuses)
    }
}
