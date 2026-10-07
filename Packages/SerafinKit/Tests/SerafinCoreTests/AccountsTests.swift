import Foundation
import Testing

@testable import SerafinCore

/// What `/Users/AuthenticateByName` and `/Users/AuthenticateWithQuickConnect` return, trimmed to what Serafin reads.
private func authenticationJSON(userID: String = "user-1", name: String = "Alice", token: String = "token-1")
    -> String
{
    #"{"User":{"Name":"\#(name)","Id":"\#(userID)","HasPassword":true},"AccessToken":"\#(token)","ServerId":"s"}"#
}

/// What `/QuickConnect/Initiate` and `/QuickConnect/Connect` return.
private func quickConnectJSON(authenticated: Bool) -> String {
    #"{"Authenticated":\#(authenticated),"Secret":"quick-secret","Code":"246810","DeviceId":"d","AppName":"Serafin"}"#
}

/// Accounts on throwaway stores, talking to stubbed servers. Every test uses its own host.
private struct Harness {
    let secrets = InMemorySecretStore()
    let homeSnapshots: HomeSnapshotStore
    let accounts: Accounts

    init() throws {
        let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
        homeSnapshots = HomeSnapshotStore(directory: directory.appending(path: "home"))
        accounts = Accounts(
            secrets: secrets,
            deviceName: "iPhone",
            version: "0.1.0",
            serverStore: ServerStore(fileURL: directory.appending(path: "servers.json")),
            defaults: try #require(UserDefaults(suiteName: "serafin-tests-\(UUID().uuidString)")),
            imageDiskCache: false,
            homeSnapshots: homeSnapshots,
            sessionConfiguration: { StubURLProtocol.configuration() }
        )
    }

    /// Saves a Home for `key` as if it had loaded.
    func saveHome(for key: SessionKey) async {
        await homeSnapshots.save(
            HomeSnapshot(date: .now, libraries: [], resume: [], nextUp: [], latest: [:]), for: key)
    }

    func hasSavedHome(_ key: SessionKey) async -> Bool {
        await homeSnapshots.snapshot(for: key) != nil
    }

    func server(on host: String) throws -> Server {
        Server(id: "server-\(host)", name: "Home", url: try #require(URL(string: "https://\(host)")))
    }

    func token(_ server: Server, _ userID: String) -> String? {
        secrets.get("token.\(server.id).\(userID)")
    }

    /// Signs in with a password against a stubbed server that accepts it.
    func signIn(to server: Server, as userID: String = "user-1", name: String = "Alice") async throws -> Account {
        let host = try #require(server.url.host())
        StubURLProtocol.stub(
            "\(host):443",
            path: "/Users/AuthenticateByName",
            .json(200, authenticationJSON(userID: userID, name: name, token: "token-\(userID)"))
        )
        return try await accounts.signIn(to: server, username: name, password: "password")
    }

    /// Starts Quick Connect against a stubbed server, which answers polls with `polls`.
    func startQuickConnect(on host: String, polls: StubURLProtocol.Reply...) async throws -> QuickConnectRequest {
        let server = try server(on: host)
        StubURLProtocol.stub("\(host):443", path: "/QuickConnect/Enabled", .json(200, "true"))
        StubURLProtocol.stub(
            "\(host):443", path: "/QuickConnect/Initiate", .json(200, quickConnectJSON(authenticated: false)))
        let replies: [StubURLProtocol.Reply] =
            polls.isEmpty ? [.json(200, quickConnectJSON(authenticated: false))] : polls
        StubURLProtocol.stubSequence("\(host):443", path: "/QuickConnect/Connect", replies)
        return try await accounts.startQuickConnect(on: server)
    }
}

@Suite struct PasswordSignInTests {
    @Test func savesTheTokenAndMakesTheAccountCurrent() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "password.example.com")
        let account = try await harness.signIn(to: server)

        #expect(account.user == ServerUser(id: "user-1", name: "Alice"))
        #expect(harness.token(server, "user-1") == "token-user-1")
        #expect(try await harness.accounts.current() == account)
        let saved = try #require(try await harness.accounts.servers().first)
        #expect(saved.users == [account.user])
        #expect(saved.lastUserID == "user-1")
    }

    @Test func sendsTheCredentialsOnceWithTheDeviceIdentityAndNoToken() async throws {
        let harness = try Harness()
        _ = try await harness.signIn(to: try harness.server(on: "credentials.example.com"))
        let requests = StubURLProtocol.requests(to: "credentials.example.com:443", path: "/Users/AuthenticateByName")
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.request.httpMethod == "POST")
        #expect(
            try JSONDecoder().decode([String: String].self, from: request.body) == [
                "Username": "Alice", "Pw": "password",
            ])
        #expect(request.authorization?.contains("Client=Serafin") == true)
        #expect(request.authorization?.contains("Token=") == false)
    }

    @Test func aWrongPasswordIsReportedAndNothingIsSaved() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "wrong-password.example.com")
        StubURLProtocol.stub(
            "wrong-password.example.com:443",
            path: "/Users/AuthenticateByName",
            .json(401, #""Invalid username or password entered.""#)
        )
        await #expect(throws: SerafinError.invalidCredentials) {
            try await harness.accounts.signIn(to: server, username: "Alice", password: "wrong")
        }
        #expect(try await harness.accounts.current() == nil)
        #expect(try await harness.accounts.servers().isEmpty)
    }

    @Test func anUnreachableServerIsReported() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "down.example.com")
        StubURLProtocol.stub("down.example.com:443", .failure(.cannotConnectToHost))
        await #expect(throws: SerafinError.serverUnreachable) {
            try await harness.accounts.signIn(to: server, username: "Alice", password: "password")
        }
    }

    @Test func otherServerErrorsCarryTheirStatus() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "broken.example.com")
        StubURLProtocol.stub("broken.example.com:443", path: "/Users/AuthenticateByName", .json(500, "{}"))
        await #expect(throws: SerafinError.unexpectedResponse(status: 500)) {
            try await harness.accounts.signIn(to: server, username: "Alice", password: "password")
        }
    }

    @Test func passwordsNeverGoOverPlainHTTPToAPublicHost() async throws {
        let harness = try Harness()
        let server = Server(id: "public", name: "Public", url: try #require(URL(string: "http://public.example.com")))
        await #expect(throws: SerafinError.insecureTransport) {
            try await harness.accounts.signIn(to: server, username: "Alice", password: "password")
        }
        #expect(StubURLProtocol.lastRequest(to: "public.example.com:80") == nil)
    }
}

@Suite struct QuickConnectTests {
    @Test func signsInOnceTheCodeIsApproved() async throws {
        let harness = try Harness()
        let host = "quick.example.com"
        StubURLProtocol.stub(
            "\(host):443",
            path: "/Users/AuthenticateWithQuickConnect",
            .json(200, authenticationJSON(userID: "user-2", name: "Bob", token: "token-2"))
        )
        let request = try await harness.startQuickConnect(
            on: host,
            polls: .json(200, quickConnectJSON(authenticated: false)), .json(200, quickConnectJSON(authenticated: true))
        )
        #expect(request.code == "246810")

        let account = try await harness.accounts.finishQuickConnect(request, pollingEvery: .milliseconds(1))
        #expect(account.user == ServerUser(id: "user-2", name: "Bob"))
        #expect(harness.token(request.server, "user-2") == "token-2")
        #expect(try await harness.accounts.current() == account)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/QuickConnect/Connect").count == 2)
        let exchange = try #require(
            StubURLProtocol.requests(to: "\(host):443", path: "/Users/AuthenticateWithQuickConnect").first
        )
        #expect(try JSONDecoder().decode([String: String].self, from: exchange.body) == ["Secret": "quick-secret"])
    }

    @Test func reportsWhenTheServerHasItTurnedOff() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "no-quick.example.com")
        StubURLProtocol.stub("no-quick.example.com:443", path: "/QuickConnect/Enabled", .json(200, "false"))
        await #expect(throws: SerafinError.quickConnectDisabled) {
            try await harness.accounts.startQuickConnect(on: server)
        }
        #expect(StubURLProtocol.requests(to: "no-quick.example.com:443", path: "/QuickConnect/Initiate").isEmpty)
    }

    @Test func reportsAnExpiredCode() async throws {
        let harness = try Harness()
        let request = try await harness.startQuickConnect(
            on: "expired.example.com", polls: .json(404, #""Unknown secret""#))
        await #expect(throws: SerafinError.quickConnectExpired) {
            try await harness.accounts.finishQuickConnect(request, pollingEvery: .milliseconds(1))
        }
    }

    @Test func givesUpWhenTimeRunsOut() async throws {
        let harness = try Harness()
        let request = try await harness.startQuickConnect(on: "slow.example.com")
        await #expect(throws: SerafinError.quickConnectExpired) {
            try await harness.accounts.finishQuickConnect(
                request,
                pollingEvery: .milliseconds(1),
                giveUpAfter: .milliseconds(20)
            )
        }
        #expect(try await harness.accounts.current() == nil)
    }

    @Test func ridesOutABriefDropInTheConnection() async throws {
        let harness = try Harness()
        let host = "flaky.example.com"
        StubURLProtocol.stub(
            "\(host):443",
            path: "/Users/AuthenticateWithQuickConnect",
            .json(200, authenticationJSON())
        )
        let request = try await harness.startQuickConnect(
            on: host,
            polls: .failure(.networkConnectionLost), .failure(.timedOut),
            .json(200, quickConnectJSON(authenticated: true))
        )
        let account = try await harness.accounts.finishQuickConnect(request, pollingEvery: .milliseconds(1))
        #expect(account.user.id == "user-1")
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingStopsTheWaiting() async throws {
        let harness = try Harness()
        let request = try await harness.startQuickConnect(on: "cancelled.example.com")
        let accounts = harness.accounts
        let waiting = Task { try await accounts.finishQuickConnect(request, pollingEvery: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(30))
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
    }
}

@Suite struct AccountManagementTests {
    @Test func signingOutEndsTheSessionAndForgetsTheToken() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "sign-out.example.com")
        let account = try await harness.signIn(to: server)
        StubURLProtocol.stub("sign-out.example.com:443", path: "/Sessions/Logout", .json(204, ""))

        try await harness.accounts.signOut(account.key)

        #expect(harness.token(server, "user-1") == nil)
        #expect(try await harness.accounts.current() == nil)
        #expect(try await harness.accounts.servers().first?.users.isEmpty == true)
        let logout = try #require(
            StubURLProtocol.requests(to: "sign-out.example.com:443", path: "/Sessions/Logout").first)
        #expect(logout.request.httpMethod == "POST")
        #expect(logout.authorization?.contains("Token=token-user-1") == true)
    }

    @Test func signingOutWorksWhileTheServerIsDown() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "sign-out-offline.example.com")
        let account = try await harness.signIn(to: server)
        StubURLProtocol.stub(
            "sign-out-offline.example.com:443", path: "/Sessions/Logout", .failure(.notConnectedToInternet))

        try await harness.accounts.signOut(account.key)

        #expect(harness.token(server, "user-1") == nil)
        #expect(try await harness.accounts.current() == nil)
    }

    @Test func switchingAccountsChangesTheCurrentOne() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "family.example.com")
        let alice = try await harness.signIn(to: server, as: "user-1", name: "Alice")
        let bob = try await harness.signIn(to: server, as: "user-2", name: "Bob")
        #expect(try await harness.accounts.current()?.user == bob.user)

        try await harness.accounts.switchTo(alice.key)

        #expect(try await harness.accounts.current()?.user == alice.user)
        let saved = try #require(try await harness.accounts.servers().first)
        #expect(saved.users.map(\.name) == ["Alice", "Bob"])
        #expect(saved.lastUserID == "user-1")
    }

    @Test func switchingToAnAccountThatIsNotSignedInIsRefused() async throws {
        let harness = try Harness()
        await #expect(throws: SerafinError.notSignedIn) {
            try await harness.accounts.switchTo(SessionKey(serverID: "nowhere", userID: "nobody"))
        }
    }

    @Test func aSelectionWhoseTokenHasGoneIsCleared() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "lost-token.example.com")
        _ = try await harness.signIn(to: server)
        harness.secrets.delete("token.\(server.id).user-1")
        #expect(try await harness.accounts.current() == nil)
    }

    @Test func removingAServerSignsEveryoneOutAndForgetsItsPin() async throws {
        let harness = try Harness()
        let host = "removed.example.com"
        let server = try harness.server(on: host)
        _ = try await harness.signIn(to: server, as: "user-1", name: "Alice")
        _ = try await harness.signIn(to: server, as: "user-2", name: "Bob")
        let certificate = try #require(TestCertificates.a1.flatMap(CertificateFingerprint.init(certificate:)))
        try await harness.accounts.trust(certificate, for: ServerAddress.parse(host))
        StubURLProtocol.stub("\(host):443", path: "/Sessions/Logout", .json(204, ""))

        try await harness.accounts.remove(serverID: server.id)

        #expect(try await harness.accounts.servers().isEmpty)
        #expect(try await harness.accounts.current() == nil)
        #expect(harness.token(server, "user-1") == nil)
        #expect(harness.token(server, "user-2") == nil)
        #expect(try PinStore(secrets: harness.secrets).pin(for: host) == nil)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Sessions/Logout").count == 2)
    }

    @Test func reAddingAServerAtANewAddressKeepsItsUsers() async throws {
        let harness = try Harness()
        let server = try harness.server(on: "old-address.example.com")
        _ = try await harness.signIn(to: server)
        StubURLProtocol.stub(
            "new-address.example.com:443",
            path: "/System/Info/Public",
            .json(
                200, #"{"Id":"\#(server.id)","ServerName":"Moved","Version":"10.10.7","ProductName":"Jellyfin Server"}"#
            )
        )

        let connected = try await harness.accounts.connect(to: ServerAddress.parse("new-address.example.com"))
        let saved = try await harness.accounts.add(connected)

        #expect(saved.url.absoluteString == "https://new-address.example.com")
        #expect(saved.name == "Moved")
        #expect(saved.users.map(\.id) == ["user-1"])
        #expect(try await harness.accounts.current()?.server.url == saved.url)
    }

    @Test func eachAccountHasOneLibraryUntilItSignsOut() async throws {
        let harness = try Harness()
        let account = try await harness.signIn(to: try harness.server(on: "library.example.com"))
        let first = try await harness.accounts.library(for: account)
        #expect(first === (try await harness.accounts.library(for: account)))
        #expect(first.userID == "user-1")

        try await harness.accounts.signOut(account.key)

        await #expect(throws: SerafinError.notSignedIn) { try await harness.accounts.library(for: account) }
    }

    @Test func artworkCarriesTheAccountsTokenInItsHeader() async throws {
        let harness = try Harness()
        let account = try await harness.signIn(to: try harness.server(on: "artwork.example.com"))
        let artwork = try await harness.accounts.artwork(for: account)
        #expect(artwork.authorization.contains(#"Token="token-user-1""#))
        #expect(artwork.urls.serverURL == account.server.url)
    }

    @Test func eachAccountsLibraryKeepsItsHomeOnTheDevice() async throws {
        let harness = try Harness()
        let host = "kept-home.example.com"
        let account = try await harness.signIn(to: try harness.server(on: host))
        for path in ["/UserViews", "/UserItems/Resume", "/Shows/NextUp"] {
            StubURLProtocol.stub("\(host):443", path: path, .json(200, #"{"Items":[]}"#))
        }
        let home = try await harness.accounts.library(for: account).home()
        #expect(await harness.homeSnapshots.snapshot(for: account.key) == home)
    }

    @Test func signingOutForgetsOnlyThatAccountsSavedHome() async throws {
        let harness = try Harness()
        let host = "forget-home.example.com"
        let server = try harness.server(on: host)
        let alice = try await harness.signIn(to: server, as: "user-1", name: "Alice")
        let bob = try await harness.signIn(to: server, as: "user-2", name: "Bob")
        await harness.saveHome(for: alice.key)
        await harness.saveHome(for: bob.key)
        StubURLProtocol.stub("\(host):443", path: "/Sessions/Logout", .json(204, ""))

        try await harness.accounts.signOut(alice.key)

        #expect(await !harness.hasSavedHome(alice.key))
        #expect(await harness.hasSavedHome(bob.key))
    }

    @Test func removingAServerForgetsItsUsersSavedHomes() async throws {
        let harness = try Harness()
        let host = "removed-homes.example.com"
        let server = try harness.server(on: host)
        let alice = try await harness.signIn(to: server, as: "user-1", name: "Alice")
        let bob = try await harness.signIn(to: server, as: "user-2", name: "Bob")
        await harness.saveHome(for: alice.key)
        await harness.saveHome(for: bob.key)
        StubURLProtocol.stub("\(host):443", path: "/Sessions/Logout", .json(204, ""))

        try await harness.accounts.remove(serverID: server.id)

        #expect(await !harness.hasSavedHome(alice.key))
        #expect(await !harness.hasSavedHome(bob.key))
    }

    @Test func clearingCachesForgetsEverySavedHome() async throws {
        let harness = try Harness()
        let first = try await harness.signIn(to: try harness.server(on: "clear-first.example.com"))
        let second = try await harness.signIn(to: try harness.server(on: "clear-second.example.com"))
        await harness.saveHome(for: first.key)
        await harness.saveHome(for: second.key)

        await harness.accounts.clearCaches()

        #expect(await !harness.hasSavedHome(first.key))
        #expect(await !harness.hasSavedHome(second.key))
    }

    @Test func eachAccountHasOneClientCarryingItsToken() async throws {
        let harness = try Harness()
        let account = try await harness.signIn(to: try harness.server(on: "client.example.com"))
        let first = try await harness.accounts.client(for: account)
        let second = try await harness.accounts.client(for: account)
        #expect(first === second)
        #expect(first.accessToken == "token-user-1")
    }
}
