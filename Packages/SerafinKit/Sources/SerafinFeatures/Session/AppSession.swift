import Foundation
import Observation
import SerafinCore
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

    /// The account the app is browsing as, if any.
    public var account: Account? {
        if case .signedIn(let account) = state { account } else { nil }
    }

    private static let logger = Logger(serafinCategory: "session")
    private let accounts: Accounts

    /// Creates a session over `accounts`.
    public init(accounts: Accounts) {
        self.accounts = accounts
    }

    /// The session the app runs with: tokens, certificate pins and the device ID in the Keychain, and the server
    /// list in Application Support.
    ///
    /// - Parameter deviceName: The device name servers show, such as "iPhone".
    public static func live(deviceName: String) -> AppSession {
        AppSession(accounts: Accounts(secrets: KeychainSecretStore(), deviceName: deviceName))
    }

    /// Reads the saved servers and the current account. The app calls this once at launch.
    public func load() async {
        await refresh()
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

    /// Signs everyone out of `server` and forgets it.
    public func remove(_ server: Server) async throws {
        try await changing { try await accounts.remove(serverID: server.id) }
    }

    // MARK: - Signing in

    /// Asks `server` for a Quick Connect code to show the user.
    ///
    /// - Throws: ``SerafinError/quickConnectDisabled`` when the server has Quick Connect turned off, so the caller
    ///   offers a password instead.
    public func startQuickConnect(on server: Server) async throws -> QuickConnectRequest {
        try await accounts.startQuickConnect(on: server)
    }

    /// Waits until the user approves the code, then signs in as them. Cancel the calling task to stop waiting.
    public func finishQuickConnect(_ request: QuickConnectRequest) async throws {
        _ = try await changing { try await accounts.finishQuickConnect(request) }
    }

    /// Signs in with a username and password. The password is sent once and kept nowhere.
    public func signIn(to server: Server, username: String, password: String) async throws {
        _ = try await changing { try await accounts.signIn(to: server, username: username, password: password) }
    }

    // MARK: - Switching and signing out

    /// Browses as another signed-in account.
    public func switchTo(_ key: SessionKey) async throws {
        _ = try await changing { try await accounts.switchTo(key) }
    }

    /// Signs a user out on this device and ends their session on the server.
    public func signOut(_ key: SessionKey) async throws {
        try await changing { try await accounts.signOut(key) }
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

    /// Re-reads the servers and the current account, and hands screens a new library and artwork loader when the
    /// account or its server's address has changed.
    private func refresh() async {
        do {
            servers = try await accounts.servers()
            guard let current = try await accounts.current() else {
                signOutScreens()
                return
            }
            if current != account || library == nil || artwork == nil {
                library = try await accounts.library(for: current)
                artwork = try await accounts.artwork(for: current)
            }
            state = .signedIn(current)
        } catch {
            Self.logger.error("Could not read the saved accounts: \(error.localizedDescription, privacy: .private)")
            signOutScreens()
        }
    }

    private func signOutScreens() {
        library = nil
        artwork = nil
        state = .signedOut
    }
}
