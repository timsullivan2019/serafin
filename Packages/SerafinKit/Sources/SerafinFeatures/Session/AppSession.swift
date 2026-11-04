import Foundation
import Observation
import SerafinCore
import SerafinPlayback
import os

/// Who is signed in to which server, for the whole app.
///
/// Screens read ``state`` to know whether anyone is signed in and as whom, and ``servers`` to list every server and
/// user on this device. Every change to servers and accounts goes through here, so the app follows the current
/// selection wherever it changes.
@Observable @MainActor public final class AppSession {
    /// Whether anyone is signed in.
    public enum State: Equatable, Sendable {
        /// The saved selection is still being read.
        case loading
        /// No one is signed in.
        case signedOut
        /// The app is browsing as this account.
        case signedIn(Account)
    }

    /// Whether anyone is signed in, and as whom.
    public private(set) var state = State.loading
    /// Every saved server with its signed-in users, in the order the servers were added.
    public private(set) var servers: [Server] = []
    /// The current account's library, or nil when no one is signed in.
    public private(set) var library: LibraryRepository?
    /// Loads the current account's images, or nil when no one is signed in.
    public private(set) var artwork: Artwork?
    /// Plays the current account's movies and episodes, or nil when no one is signed in.
    public private(set) var player: PlayerEngine?
    /// The current account's downloads, or nil when no one is signed in or the session has no downloads, as in
    /// previews.
    private(set) var downloads: DownloadCenter?

    /// The account the app is browsing as, if any.
    public var account: Account? {
        if case .signedIn(let account) = state { account } else { nil }
    }

    /// Keeps the current account's library in Spotlight, or nil in previews and tests.
    let spotlight: SpotlightIndexer?

    private static let logger = Logger(serafinCategory: "session")
    private let accounts: Accounts
    /// The first read of the saved servers and account.
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// Creates a session over `accounts`.
    public convenience init(accounts: Accounts) {
        self.init(accounts: accounts, spotlight: nil)
    }

    init(accounts: Accounts, spotlight: SpotlightIndexer?) {
        self.accounts = accounts
        self.spotlight = spotlight
    }

    /// The session the app runs with: tokens, certificate pins and the device ID in the Keychain, the server list
    /// and downloads in Application Support, and the current account's movies and shows in Spotlight.
    ///
    /// - Parameter deviceName: The device name servers show, such as "iPhone".
    public static func live(deviceName: String) -> AppSession {
        AppSession(
            accounts: Accounts(
                secrets: KeychainSecretStore(),
                deviceName: deviceName,
                downloads: .live(preparer: DownloadedCopyWriter())
            ),
            spotlight: .shared
        )
    }

    /// Reads the saved servers and the current account, once. The app calls this at launch, and Siri or Shortcuts
    /// may call it first when they start the app in the background. Later calls wait for that first read.
    public func load() async {
        if let loading {
            return await loading.value
        }
        let loading = Task { await refresh() }
        self.loading = loading
        await loading.value
    }

    // MARK: - Adding and removing servers

    /// Finds the Jellyfin server at `address`.
    ///
    /// The caller shows whatever the result calls for before ``add(_:)``: the plain-HTTP warning for a server on the
    /// local network, or the certificate check when this throws ``SerafinError/untrustedCertificate(_:)``.
    public func connect(to address: ServerAddress) async throws -> ConnectedServer {
        try await accounts.connect(to: address)
    }

    /// Pins a certificate once the user has checked its fingerprint. Connect again afterwards.
    public func trust(_ certificate: CertificateFingerprint, for address: ServerAddress) async throws {
        try await accounts.trust(certificate, for: address)
    }

    /// Saves a server the user has accepted.
    @discardableResult
    public func add(_ connected: ConnectedServer) async throws -> Server {
        try await changing { try await accounts.add(connected) }
    }

    /// Signs everyone out of `server` and forgets it, with its streaming caps, its users' recent searches and the
    /// name last used to sign in to it.
    public func remove(_ server: Server) async throws {
        try await changing { try await accounts.remove(serverID: server.id) }
        PlaybackQuality.forget(server: server.id, in: .standard)
        RecentSearches.forget(server: server.id)
        LastUsername.forget(server: server.id)
    }

    /// Asks every saved server for its name again, so a server renamed since it was added shows its new name.
    /// Servers that can't be reached keep the name they had.
    ///
    /// Only the names change: the current account's library and player carry on as they are.
    public func refreshServerNames() async {
        var renamed = false
        for server in servers where await accounts.refreshName(ofServer: server.id) {
            renamed = true
        }
        guard renamed, let saved = try? await accounts.servers() else { return }
        servers = saved
        if let account, let server = saved.first(where: { $0.id == account.server.id }) {
            state = .signedIn(Account(server: server, user: account.user))
        }
    }

    // MARK: - Addresses

    /// Moves the current account's server to the address it answers best at on the network the device is on, when
    /// that isn't the one in use, as when the device leaves home Wi-Fi. Screens carry on as they are, with a library,
    /// artwork and player for the new address.
    ///
    /// Nothing moves while the player has something loaded, since a stream can't change address as it plays: the app
    /// checks again once the player stops.
    ///
    /// - Parameter prefersLocal: Whether home addresses come first, as on Wi-Fi or a wired network, rather than
    ///   remote ones, as on cellular.
    public func checkAddress(prefersLocal: Bool) async {
        guard let account, account.server.addresses.count > 1, isPlayerIdle else { return }
        guard
            let best = await accounts.bestAddress(ofServer: account.server.id, prefersLocal: prefersLocal),
            best != account.server.url,
            // Something may have started playing, or another account been chosen, while the addresses answered.
            isPlayerIdle, self.account?.key == account.key
        else { return }
        do {
            _ = try await changing { try await accounts.useAddress(best, forServer: account.server.id) }
        } catch {
            Self.logger.error("Could not move to another address: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Whether the player has nothing loaded, so the current account's server may move to another address.
    public var isPlayerIdle: Bool {
        player.map { $0.state == .idle } ?? true
    }

    /// Which of `server`'s addresses answer as that server now, all asked at once.
    public func answeringAddresses(of server: Server) async -> Set<URL> {
        await accounts.answeringAddresses(ofServer: server.id)
    }

    /// Adds the address `connected` answered at to `server`, which carries on at the address in use until Serafin
    /// finds the new one answers better.
    ///
    /// - Throws: ``SerafinError/differentServer`` when another server answered there, and
    ///   ``SerafinError/tooManyAddresses`` when `server` has ``Server/maximumAddresses`` already.
    public func addAddress(_ connected: ConnectedServer, to server: Server) async throws {
        _ = try await changing { try await accounts.addAddress(connected, toServer: server.id) }
    }

    /// Forgets one of `server`'s addresses, with its certificate pin unless another saved address has the same host.
    /// When it was the address in use, `server` moves to its first address left.
    public func removeAddress(_ address: URL, from server: Server) async throws {
        try await changing { try await accounts.removeAddress(address, fromServer: server.id) }
    }

    /// The address `server` gives for itself on its own network or tailnet, ready to add to it, when it isn't one of
    /// `server`'s addresses yet and the server answers there. Nil otherwise, as when it's an address only a
    /// container can reach.
    ///
    /// - Parameter info: What the server reported when it was just reached, or nil to ask it now.
    public func suggestedAddress(for server: Server, reportedBy info: PublicServerInfo? = nil) async -> ConnectedServer?
    {
        await accounts.suggestedAddress(for: server, reportedBy: info)
    }

    // MARK: - Signing in

    /// The users `server` lists on its sign-in screen, often none.
    public func publicUsers(on server: Server) async throws -> [PublicUser] {
        try await accounts.publicUsers(on: server)
    }

    /// Whether `server` has Quick Connect turned on, or nil when it couldn't be asked.
    public func isQuickConnectEnabled(on server: Server) async -> Bool? {
        await accounts.isQuickConnectEnabled(on: server)
    }

    /// Loads pictures from `server` before anyone has signed in, such as its users' pictures.
    public func signInArtwork(for server: Server) async throws -> Artwork {
        try await accounts.signInArtwork(for: server)
    }

    /// Asks `server` for a Quick Connect code to show the user.
    ///
    /// - Throws: ``SerafinError/quickConnectDisabled`` when the server has Quick Connect turned off, so the caller
    ///   offers a password instead.
    public func startQuickConnect(on server: Server) async throws -> QuickConnectRequest {
        try await accounts.startQuickConnect(on: server)
    }

    /// Waits until the user approves the code, then signs in as them. Cancel the calling task to stop waiting.
    public func finishQuickConnect(_ request: QuickConnectRequest) async throws {
        let account = try await changing { try await accounts.finishQuickConnect(request) }
        LastUsername.save(account.user.name, forServer: account.server.id)
    }

    /// Signs in with a username and password. The password is sent once and kept nowhere; the name is remembered,
    /// so signing in to the server again starts with it.
    public func signIn(to server: Server, username: String, password: String) async throws {
        let account = try await changing {
            try await accounts.signIn(to: server, username: username, password: password)
        }
        LastUsername.save(account.user.name, forServer: server.id)
    }

    // MARK: - Switching and signing out

    /// Browses as another signed-in account.
    public func switchTo(_ key: SessionKey) async throws {
        _ = try await changing { try await accounts.switchTo(key) }
    }

    /// Signs a user out on this device and ends their session on the server, and forgets their recent searches.
    public func signOut(_ key: SessionKey) async throws {
        try await changing { try await accounts.signOut(key) }
        RecentSearches.forget(key)
    }

    // MARK: - Storage

    /// Empties every cache on this device: artwork, each account's saved Home and recent answers from the server.
    public func clearCaches() async {
        await accounts.clearCaches()
    }

    // MARK: - Helpers

    /// Runs a change, then re-reads the servers and the current account whether it worked or not.
    private func changing<Result>(_ change: () async throws -> Result) async throws -> Result {
        do {
            let result = try await change()
            await refresh()
            return result
        } catch {
            await refresh()
            throw error
        }
    }

    /// Re-reads the servers and the current account, and hands screens a new library, artwork loader and player when
    /// the account or its server's address has changed.
    private func refresh() async {
        do {
            servers = try await accounts.servers()
            guard let current = try await accounts.current() else {
                await signOutScreens()
                return
            }
            let isSameAccount = current.key == account?.key && library != nil && artwork != nil && player != nil
            if !isSameAccount || current.server.url != account?.server.url {
                try await signInScreens(as: current, keepingDownloads: isSameAccount)
            }
            state = .signedIn(current)
        } catch {
            Self.logger.error("Could not read the saved accounts: \(error.localizedDescription, privacy: .private)")
            await signOutScreens()
        }
    }

    /// Makes the library, artwork loader and player for `current`, and stops the last player. The same account at
    /// another address keeps its downloads, which take the new library and client, so nothing that shows them blinks.
    private func signInScreens(as current: Account, keepingDownloads: Bool) async throws {
        let library = try await accounts.library(for: current)
        let artwork = try await accounts.artwork(for: current)
        let client = try await accounts.client(for: current)
        let previous = player
        let planner = DownloadPlanner(client: client, userID: current.user.id)
        let trickplay = TrickplayRepository(client: client, userID: current.user.id)
        self.library = library
        self.artwork = artwork
        if keepingDownloads, let downloads, let saved = accounts.downloads {
            downloads.reconnect(
                planner: planner, library: library, artwork: artwork,
                sync: PlaybackSync(client: client, key: current.key, downloads: saved), trickplay: trickplay)
        } else {
            downloads = accounts.downloads.map {
                DownloadCenter(
                    downloads: $0,
                    key: current.key,
                    planner: planner,
                    library: library,
                    artwork: artwork,
                    sync: PlaybackSync(client: client, key: current.key, downloads: $0),
                    trickplay: trickplay
                )
            }
        }
        player = PlayerEngine(
            client: client,
            userID: current.user.id,
            pinning: accounts.pinning,
            playbackPreferences: { try await library.playbackPreferences() }
        )
        await previous?.stop()
    }

    private func signOutScreens() async {
        let previous = player
        library = nil
        artwork = nil
        player = nil
        downloads = nil
        state = .signedOut
        await previous?.stop()
    }
}

#if DEBUG
    extension AppSession {
        /// A session on throwaway, in-memory stores, signed out, for previews.
        ///
        /// - Parameter servers: Servers saved before the session starts, which it lists once ``load()`` has run.
        static func preview(servers: [Server] = []) -> AppSession {
            AppSession(accounts: previewAccounts(servers: servers))
        }

        private nonisolated static func previewAccounts(servers: [Server]) -> Accounts {
            let suite = "app.getserafin.serafin.preview.\(UUID().uuidString)"
            let directory = URL.temporaryDirectory.appending(path: suite)
            let serversFile = directory.appending(path: "servers.json")
            if !servers.isEmpty {
                struct File: Encodable {
                    let version = 1
                    let servers: [Server]
                }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? JSONEncoder().encode(File(servers: servers)).write(to: serversFile)
            }
            return Accounts(
                secrets: InMemorySecretStore(),
                deviceName: "iPhone",
                serverStore: ServerStore(fileURL: serversFile),
                defaults: UserDefaults(suiteName: suite) ?? UserDefaults(),
                imageDiskCache: false,
                homeSnapshots: HomeSnapshotStore(directory: directory.appending(path: "home"))
            )
        }
    }

    extension Server {
        /// A server with an address at home, one on Tailscale and one on the internet, connected at home, for
        /// previews.
        static var previewWithAddresses: Server {
            let addresses = ["http://192.168.1.20:8096", "http://100.101.102.103:8096", "https://media.example.com"]
                .map { URL(string: $0) ?? .temporaryDirectory }
            return Server(id: "preview", name: "Living Room", url: addresses[0], addresses: addresses)
        }
    }
#endif
