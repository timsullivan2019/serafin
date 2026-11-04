import Foundation
import JellyfinAPI
import SerafinCore
import SerafinPlayback
import Synchronization
import Testing

@testable import SerafinFeatures

/// A Jellyfin server at each of the addresses a test gives it, which answers its public info and signs Alice in, and
/// fails everything else, such as a request to play something.
final class ServerAtAddresses: URLProtocol, @unchecked Sendable {
    /// The ID of the server at each host and port.
    private static let servers = Mutex<[String: String]>([:])

    /// Puts the server with `id` at `hostAndPort`.
    static func serve(_ id: String, at hostAndPort: String) {
        servers.withLock { $0[hostAndPort] = id }
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServerAtAddresses.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url, let host = url.host() else { return fail() }
        let hostAndPort = "\(host):\(url.port ?? (url.scheme == "https" ? 443 : 80))"
        guard let id = Self.servers.withLock({ $0[hostAndPort] }) else { return fail() }
        switch url.path() {
        case "/System/Info/Public":
            respond(#"{"Id":"\#(id)","ServerName":"Home","Version":"10.10.7","ProductName":"Jellyfin Server"}"#)
        case "/Users/AuthenticateByName":
            respond(
                #"{"User":{"Name":"Alice","Id":"user-1","HasPassword":true},"AccessToken":"token-1","ServerId":"\#(id)"}"#
            )
        default:
            fail()
        }
    }

    private func respond(_ json: String) {
        guard
            let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        else { return fail() }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    private func fail() {
        client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
    }
}

@MainActor
@Suite struct AddressSwitchingTests {
    /// A session on throwaway stores, whose requests reach only the servers ``ServerAtAddresses`` puts at addresses.
    private func session() throws -> AppSession {
        AppSession(accounts: try Self.accounts())
    }

    /// The session's accounts, made off the main actor so the defaults they're handed belong to nothing else.
    private nonisolated static func accounts() throws -> Accounts {
        let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
        return Accounts(
            secrets: InMemorySecretStore(),
            deviceName: "iPhone",
            serverStore: ServerStore(fileURL: directory.appending(path: "servers.json")),
            defaults: try #require(UserDefaults(suiteName: "serafin-tests-\(UUID().uuidString)")),
            imageDiskCache: false,
            homeSnapshots: HomeSnapshotStore(directory: directory.appending(path: "home")),
            sessionConfiguration: { ServerAtAddresses.configuration() }
        )
    }

    @Test func theServerMovesOnlyOnceThePlayerHasNothingLoaded() async throws {
        ServerAtAddresses.serve("switching-server", at: "switching.example.com:443")
        ServerAtAddresses.serve("switching-server", at: "192.168.78.10:8096")
        let session = try session()
        let connected = try await session.connect(to: ServerAddress.parse("switching.example.com"))
        let server = try await session.add(connected)
        try await session.signIn(to: server, username: "Alice", password: "password")
        let home = try await session.connect(to: ServerAddress.parse("http://192.168.78.10:8096"))
        try await session.addAddress(home, to: server)
        let player = try #require(session.player)

        // Something is loaded: here it fails, since this server can't stream, and stays on screen until it's closed.
        await player.load(BaseItemDto(id: "movie-1", type: .movie), options: PlaybackOptions())
        #expect(player.state != PlaybackState.idle)
        await session.checkAddress(prefersLocal: true)
        #expect(session.account?.server.url == server.url)

        await player.stop()
        await session.checkAddress(prefersLocal: true)
        #expect(session.account?.server.url == home.server.url)
        #expect(session.account?.user.id == "user-1")
        // The screens carry on with a library and player made for the new address.
        #expect(session.player !== player)
    }

    @Test func addingASignedInServerFromSettingsAddsTheAddressWithoutSigningInAgain() async throws {
        ServerAtAddresses.serve("settings-server", at: "settings.example.com:443")
        ServerAtAddresses.serve("settings-server", at: "192.168.78.30:8096")
        let session = try session()
        let connected = try await session.connect(to: ServerAddress.parse("settings.example.com"))
        let server = try await session.add(connected)
        try await session.signIn(to: server, username: "Alice", password: "password")
        let library = try #require(session.library)
        let model = AddServerModel(addsToSignedInServers: true)
        model.address = "http://192.168.78.30:8096"

        // Plain HTTP at home: nothing is saved until the warning has been accepted and has closed.
        #expect(await model.connect(with: session) == nil)
        #expect(model.unencrypted != nil)
        model.acceptUnencrypted()
        #expect(model.unencrypted == nil)
        #expect(model.isConnecting)
        #expect(session.account?.server.addresses.count == 1)

        #expect(await model.proceed(with: session) == .addresses(serverID: "settings-server"))
        #expect(!model.isConnecting)
        let saved = try #require(session.account?.server)
        #expect(saved.addresses.count == 2)
        // The address in use stays until Serafin finds the new one answers better, and so does the sign-in.
        #expect(saved.url == server.url)
        #expect(session.library === library)
    }

    @Test func addingAServerAgainGoesOnToSignInWhenNobodyIsSignedInOrOnTheWelcomeScreen() async throws {
        ServerAtAddresses.serve("again-server", at: "again.example.com:443")
        ServerAtAddresses.serve("again-server", at: "192.168.78.40:8096")
        let session = try session()
        let connected = try await session.connect(to: ServerAddress.parse("again.example.com"))
        let server = try await session.add(connected)
        try await session.signIn(to: server, username: "Alice", password: "password")

        // The welcome screen is there to sign in, so a saved server goes on to sign-in at the address that answered.
        let welcome = AddServerModel()
        welcome.address = "http://192.168.78.40:8096"
        _ = await welcome.connect(with: session)
        welcome.acceptUnencrypted()
        let fromWelcome = await welcome.proceed(with: session)
        let atHome = try #require(session.servers.first)
        #expect(fromWelcome == .signIn(atHome))
        #expect(atHome.url.host() == "192.168.78.40")

        // From Settings, a saved server nobody is signed in to goes on to sign-in too.
        try await session.signOut(SessionKey(serverID: server.id, userID: "user-1"))
        let settings = AddServerModel(addsToSignedInServers: true)
        settings.address = "again.example.com"
        let fromSettings = await settings.connect(with: session)
        let signedOut = try #require(session.servers.first)
        #expect(signedOut.users.isEmpty)
        #expect(fromSettings == .signIn(signedOut))
    }

    @Test func cancellingTheWarningSavesNothing() async throws {
        ServerAtAddresses.serve("cancelled-server", at: "192.168.78.50:8096")
        let session = try session()
        let model = AddServerModel(addsToSignedInServers: true)
        model.address = "http://192.168.78.50:8096"

        _ = await model.connect(with: session)
        model.unencrypted = nil

        #expect(await model.proceed(with: session) == nil)
        #expect(session.servers.isEmpty)
        #expect(!model.isConnecting)
    }

    @Test func signingInAgainAsTheAccountInUseHandsTheScreensTheNewSignIn() async throws {
        ServerAtAddresses.serve("resigned-server", at: "resigned.example.com:443")
        let session = try session()
        let connected = try await session.connect(to: ServerAddress.parse("resigned.example.com"))
        let server = try await session.add(connected)
        try await session.signIn(to: server, username: "Alice", password: "password")
        let account = try #require(session.account)
        let library = try #require(session.library)
        let player = try #require(session.player)

        // Jellyfin ends the session the screens were using when the same user signs in again from this device.
        try await session.signIn(to: server, username: "Alice", password: "password")

        #expect(session.account == account)
        #expect(session.library !== library)
        #expect(session.player !== player)
    }

    @Test func aServerWithOneAddressStaysWhereItIs() async throws {
        ServerAtAddresses.serve("single-server", at: "single.example.com:443")
        let session = try session()
        let connected = try await session.connect(to: ServerAddress.parse("single.example.com"))
        let server = try await session.add(connected)
        try await session.signIn(to: server, username: "Alice", password: "password")
        let player = session.player

        await session.checkAddress(prefersLocal: false)
        #expect(session.account?.server.url == server.url)
        #expect(session.player === player)
    }
}
