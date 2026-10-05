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
    /// in Application Support, and the current account's movies and shows in Spotlight.
    ///
    /// - Parameter deviceName: The device name servers show, such as "iPhone".
    public static func live(deviceName: String) -> AppSession {
        AppSession(
            accounts: Accounts(secrets: KeychainSecretStore(), deviceName: deviceName),
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

    /// Signs everyone out of `server` and forgets it, with its streaming caps.
    public func remove(_ server: Server) async throws {
        try await changing { try await accounts.remove(serverID: server.id) }
        PlaybackQuality.forget(server: server.id, in: .standard)
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
                await signOutScreens()
                return
            }
            if current != account || library == nil || artwork == nil || player == nil {
                library = try await accounts.library(for: current)
                artwork = try await accounts.artwork(for: current)
                let previous = player
                player = PlayerEngine(
                    client: try await accounts.client(for: current),
                    userID: current.user.id,
                    pinning: accounts.pinning
                )
                await previous?.stop()
            }
            state = .signedIn(current)
        } catch {
            Self.logger.error("Could not read the saved accounts: \(error.localizedDescription, privacy: .private)")
            await signOutScreens()
        }
    }

    private func signOutScreens() async {
        let previous = player
        library = nil
        artwork = nil
        player = nil
        state = .signedOut
        await previous?.stop()
    }
}

#if DEBUG
    extension AppSession {
        /// A session on throwaway, in-memory stores, signed out, for previews.
        static func preview() -> AppSession {
            AppSession(accounts: previewAccounts())
        }

        private nonisolated static func previewAccounts() -> Accounts {
            let suite = "app.getserafin.serafin.preview.\(UUID().uuidString)"
            let directory = URL.temporaryDirectory.appending(path: suite)
            return Accounts(
                secrets: InMemorySecretStore(),
                deviceName: "iPhone",
                serverStore: ServerStore(fileURL: directory.appending(path: "servers.json")),
                defaults: UserDefaults(suiteName: suite) ?? UserDefaults(),
                imageDiskCache: false
            )
        }
    }
#endif
