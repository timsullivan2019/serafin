import Foundation
import JellyfinAPI
import Testing

@testable import SerafinCore

/// Public system info as Jellyfin 10.10 returns it from `/System/Info/Public`.
private func publicInfoJSON(id: String = "c0ffee", version: String = "10.10.7", product: String = "Jellyfin Server")
    -> String
{
    """
    {"LocalAddress":"http://192.168.1.20:8096","ServerName":"Living Room","Version":"\(version)",\
    "ProductName":"\(product)","OperatingSystem":"","Id":"\(id)","StartupWizardCompleted":true}
    """
}

@Suite struct PublicServerInfoTests {
    private func decode(_ json: String) throws -> PublicSystemInfo {
        try JSONDecoder().decode(PublicSystemInfo.self, from: Data(json.utf8))
    }

    @Test func acceptsASupportedJellyfinServer() throws {
        let info = try PublicServerInfo(validating: decode(publicInfoJSON()))
        #expect(info.id == "c0ffee")
        #expect(info.name == "Living Room")
        #expect(info.version == "10.10.7")
    }

    @Test(arguments: ["10.9.11", "10.8.0", "4.9.0"])
    func refusesOlderReleases(_ version: String) throws {
        #expect(throws: SerafinError.unsupportedServerVersion(version)) {
            try PublicServerInfo(validating: decode(publicInfoJSON(version: version)))
        }
    }

    @Test(arguments: ["10.10.0", "10.11.2", "11.0.0", "10.11.0-rc1"])
    func acceptsNewerReleases(_ version: String) throws {
        #expect(try PublicServerInfo(validating: decode(publicInfoJSON(version: version))).version == version)
    }

    @Test func refusesOtherProducts() throws {
        #expect(throws: SerafinError.notJellyfin) {
            try PublicServerInfo(validating: decode(publicInfoJSON(product: "Emby Server")))
        }
    }

    @Test func refusesAnswersWithoutAnID() throws {
        #expect(throws: SerafinError.notJellyfin) {
            try PublicServerInfo(validating: decode(publicInfoJSON(id: "")))
        }
    }
}

@Suite struct ServerConnectorTests {
    private let connector = ServerConnector(
        pinning: PinningDelegate(pins: PinStore(secrets: InMemorySecretStore())),
        sessionConfiguration: { StubURLProtocol.configuration() }
    )

    @Test func connectsAndNamesTheServer() async throws {
        StubURLProtocol.stub("first.example.com:443", .json(200, publicInfoJSON(id: "server-1")))
        let connected = try await connector.connect(to: ServerAddress.parse("first.example.com"))
        #expect(connected.server.id == "server-1")
        #expect(connected.server.name == "Living Room")
        #expect(connected.server.url.absoluteString == "https://first.example.com")
        #expect(connected.security == .encrypted)
    }

    @Test func triesJellyfinsHTTPSPortWhenTheStandardPortIsDown() async throws {
        StubURLProtocol.stub("second.example.com:443", .failure(.cannotConnectToHost))
        StubURLProtocol.stub("second.example.com:8920", .json(200, publicInfoJSON(id: "server-2")))
        let connected = try await connector.connect(to: ServerAddress.parse("second.example.com"))
        #expect(connected.server.url.absoluteString == "https://second.example.com:8920")
    }

    @Test func reportsAnUnreachableServer() async throws {
        StubURLProtocol.stub("third.example.com:443", .failure(.timedOut))
        StubURLProtocol.stub("third.example.com:8920", .failure(.cannotFindHost))
        await #expect(throws: SerafinError.serverUnreachable) {
            try await connector.connect(to: ServerAddress.parse("third.example.com"))
        }
    }

    @Test func reportsSomethingThatIsNotJellyfin() async throws {
        StubURLProtocol.stub("fourth.example.com:443", .json(404, "{}"))
        await #expect(throws: SerafinError.notJellyfin) {
            try await connector.connect(to: ServerAddress.parse("fourth.example.com"))
        }
    }

    @Test func reportsAnOldServer() async throws {
        StubURLProtocol.stub("fifth.example.com:443", .json(200, publicInfoJSON(version: "10.9.11")))
        await #expect(throws: SerafinError.unsupportedServerVersion("10.9.11")) {
            try await connector.connect(to: ServerAddress.parse("fifth.example.com"))
        }
    }

    @Test func refusesPlainHTTPToAPublicHostWithoutSendingAnything() async throws {
        StubURLProtocol.stub("sixth.example.com:80", .json(200, publicInfoJSON()))
        await #expect(throws: SerafinError.insecureTransport) {
            try await connector.connect(to: ServerAddress.parse("http://sixth.example.com"))
        }
    }

    @Test func allowsPlainHTTPOnAPrivateNetwork() async throws {
        StubURLProtocol.stub("192.168.77.20:8096", .json(200, publicInfoJSON(id: "home")))
        let connected = try await connector.connect(to: ServerAddress.parse("192.168.77.20"))
        #expect(connected.security == .unencryptedOnPrivateNetwork)
    }

    @Test func triesJellyfinsPortWhenSomethingElseAnswersFirst() async throws {
        StubURLProtocol.stub("192.168.77.21:80", .json(200, "<html><body>Router</body></html>"))
        StubURLProtocol.stub("192.168.77.21:8096", .json(200, publicInfoJSON(id: "behind-the-router")))
        let connected = try await connector.connect(to: ServerAddress.parse("http://192.168.77.21"))
        #expect(connected.server.url.absoluteString == "http://192.168.77.21:8096")
    }

    @Test func asksOnlyForThePublicInfoAndSendsNothingAboutTheDevice() async throws {
        StubURLProtocol.stub("seventh.example.com:443", .json(200, publicInfoJSON()))
        _ = try await connector.connect(to: ServerAddress.parse("https://seventh.example.com/jellyfin"))
        let request = try #require(StubURLProtocol.lastRequest(to: "seventh.example.com:443"))
        #expect(request.url?.path() == "/jellyfin/System/Info/Public")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func refusesAnOversizedAnswerWithoutDecodingIt() async throws {
        let padded = String(repeating: " ", count: ServerConnector.maximumInfoSize) + publicInfoJSON()
        StubURLProtocol.stub("eighth.example.com:443", .json(200, padded))
        await #expect(throws: SerafinError.notJellyfin) {
            try await connector.connect(to: ServerAddress.parse("eighth.example.com"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingIsNotReportedAsAnUnreachableServer() async throws {
        StubURLProtocol.stub("ninth.example.com:443", .hang)
        let connector = connector
        let address = try ServerAddress.parse("ninth.example.com")
        let attempt = Task { try await connector.connect(to: address) }
        attempt.cancel()
        await #expect(throws: CancellationError.self) { try await attempt.value }
    }
}

@Suite struct LocalDiscoveryTests {
    @Test func acceptsAServerOnTheLocalNetwork() throws {
        let url = try #require(URL(string: "http://192.168.1.20:8096"))
        #expect(LocalDiscovery.accept(id: "a", name: "Living Room", url: url)?.url == url)
    }

    @Test(arguments: ["http://example.com:8096", "javascript:alert(1)", "file:///etc/passwd"])
    func ignoresUnsafeAddresses(_ address: String) throws {
        #expect(LocalDiscovery.accept(id: "a", name: "Evil", url: try #require(URL(string: address))) == nil)
    }

    @Test func ignoresAnswersWithoutAnID() throws {
        #expect(LocalDiscovery.accept(id: "", name: "x", url: try #require(URL(string: "https://example.com"))) == nil)
    }
}
