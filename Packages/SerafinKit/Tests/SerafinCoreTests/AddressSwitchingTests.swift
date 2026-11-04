import Foundation
import JellyfinAPI
import Testing

@testable import SerafinCore

/// The addresses tests use: one at home, one on a tailnet and one on the internet.
private struct Addresses {
    let home: URL
    let tailscale: URL
    let remote: URL

    init() throws {
        home = try #require(URL(string: "http://192.168.1.20:8096"))
        tailscale = try #require(URL(string: "http://100.101.102.103:8096"))
        remote = try #require(URL(string: "https://media.example.com"))
    }
}

@Suite struct ServerAddressListTests {
    private let addresses: Addresses
    private let fileURL = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)/servers.json")

    init() throws {
        addresses = try Addresses()
    }

    @Test func aServerSavedBeforeServersHadSeveralAddressesHasItsOneAddress() async throws {
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // What Serafin 1.0 wrote.
        let json = #"""
            {"version":1,"servers":[{"id":"s","name":"Living Room","url":"https:\/\/media.example.com",
            "lastUserID":"u","users":[{"id":"u","name":"Alice"}]}]}
            """#
        try Data(json.utf8).write(to: fileURL)

        let server = try #require(try await ServerStore(fileURL: fileURL).servers().first)
        #expect(server.url == addresses.remote)
        #expect(server.addresses == [addresses.remote])
        #expect(server.users.map(\.id) == ["u"])
        #expect(server.lastUserID == "u")
    }

    @Test func theAddressInUseIsSavedWhereAnEarlierReleaseLooksForIt() async throws {
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        var server = Server(id: "s", name: "Living Room", url: addresses.remote)
        try server.add(addresses.home)
        server.use(addresses.home)
        try await ServerStore(fileURL: fileURL).save(server)

        let reloaded = try #require(try await ServerStore(fileURL: fileURL).servers().first)
        #expect(reloaded.url == addresses.home)
        #expect(reloaded.addresses == [addresses.remote, addresses.home])
        let file = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
        let saved = try #require((file?["servers"] as? [[String: Any]])?.first)
        let url = try #require(saved["url"] as? String)
        #expect(url == "http://192.168.1.20:8096")
        let all = try #require(saved["addresses"] as? [String])
        #expect(all == ["https://media.example.com", "http://192.168.1.20:8096"])
    }

    @Test func anAddressWrittenAnotherWayIsTheSameAddress() throws {
        var server = Server(id: "s", name: "Living Room", url: addresses.remote)
        for same in ["https://MEDIA.example.com", "https://media.example.com:443", "https://media.example.com/"] {
            try server.add(try #require(URL(string: same)))
        }
        #expect(server.addresses == [addresses.remote])

        let underAPath = try #require(URL(string: "https://media.example.com/jellyfin"))
        let onAnotherPort = try #require(URL(string: "https://media.example.com:8920"))
        try server.add(underAPath)
        try server.add(onAnotherPort)
        #expect(server.addresses == [addresses.remote, underAPath, onAnotherPort])
        let withASlash = try #require(URL(string: "https://media.example.com/jellyfin/"))
        #expect(server.address(matching: withASlash) == underAPath)
    }

    @Test func aServerKeepsAtMostFourAddresses() throws {
        var server = Server(id: "s", name: "Living Room", url: addresses.remote)
        try server.add(addresses.home)
        try server.add(addresses.tailscale)
        try server.add(try #require(URL(string: "http://nas.local:8096")))
        do {
            try server.add(try #require(URL(string: "https://other.example.com")))
            Issue.record("A fifth address was added.")
        } catch {
            #expect(error as? SerafinError == SerafinError.tooManyAddresses)
        }
        #expect(server.addresses.count == Server.maximumAddresses)
        // One it has already is no trouble.
        try server.add(addresses.home)
    }

    @Test func theAddressInUseIsKeptWhenThereAreTooMany() throws {
        let six = try (1...6).map { try #require(URL(string: "https://\($0).example.com")) }
        let server = Server(id: "s", name: "Living Room", url: six[5], addresses: six)
        #expect(server.url == six[5])
        #expect(server.addresses == [six[0], six[1], six[2], six[5]])

        let elsewhere = Server(id: "s", name: "Living Room", url: addresses.home, addresses: [addresses.remote])
        #expect(elsewhere.addresses == [addresses.home, addresses.remote])
    }

    @Test func movingToAnAddressTheServerDoesntHaveChangesNothing() throws {
        var server = Server(id: "s", name: "Living Room", url: addresses.remote, addresses: [addresses.home])
        let movedElsewhere = server.use(addresses.tailscale)
        #expect(!movedElsewhere)
        #expect(server.url == addresses.remote)
        let withASlash = try #require(URL(string: "http://192.168.1.20:8096/"))
        let movedHome = server.use(withASlash)
        #expect(movedHome)
        // The address as it was saved.
        #expect(server.url == addresses.home)
    }

    @Test func removingTheAddressInUseMovesToTheFirstOneLeft() {
        var server = Server(
            id: "s", name: "Living Room", url: addresses.home,
            addresses: [addresses.remote, addresses.home, addresses.tailscale])
        let removedHome = server.remove(addresses.home)
        #expect(removedHome)
        #expect(server.url == addresses.remote)
        #expect(server.addresses == [addresses.remote, addresses.tailscale])
        let removedRemote = server.remove(addresses.remote)
        #expect(removedRemote)
        // A server can't have no address.
        let removedTheLast = server.remove(addresses.tailscale)
        #expect(!removedTheLast)
        #expect(server.addresses == [addresses.tailscale])
        #expect(server.url == addresses.tailscale)
    }

    @Test func aLinkToShareUsesTheRemoteAddress() {
        let atHome = Server(
            id: "s", name: "Living Room", url: addresses.home,
            addresses: [addresses.home, addresses.tailscale, addresses.remote])
        #expect(atHome.sharingAddress == addresses.remote)
        let homeOnly = Server(
            id: "s", name: "Living Room", url: addresses.home, addresses: [addresses.home, addresses.tailscale])
        #expect(homeOnly.sharingAddress == addresses.home)
    }

    @Test func theNameIsTheSameWhicheverAddressIsInUse() {
        var server = Server(
            id: "s", name: "3f9a1c07be52", url: addresses.home, addresses: [addresses.home, addresses.remote])
        #expect(server.displayName == "media.example.com")
        server.use(addresses.remote)
        #expect(server.displayName == "media.example.com")
    }
}

@Suite struct ServerAddressKindTests {
    @Test(arguments: [
        ("http://192.168.1.20:8096", ServerAddressKind.local),
        ("http://10.0.0.5:8096", ServerAddressKind.local),
        ("http://nas.local:8096", ServerAddressKind.local),
        ("http://nas:8096", ServerAddressKind.local),
        ("http://[fd12:3456:789a::20]:8096", ServerAddressKind.local),
        ("http://100.64.0.1:8096", ServerAddressKind.tailscale),
        ("http://100.101.102.103:8096", ServerAddressKind.tailscale),
        ("http://100.127.255.254:8096", ServerAddressKind.tailscale),
        ("https://nas.tailnet-1234.ts.net", ServerAddressKind.tailscale),
        ("http://[fd7a:115c:a1e0::1]:8096", ServerAddressKind.tailscale),
        ("https://media.example.com", ServerAddressKind.remote),
        ("https://203.0.113.10", ServerAddressKind.remote),
        ("http://100.63.255.255:8096", ServerAddressKind.remote),
        ("http://100.128.0.1:8096", ServerAddressKind.remote),
    ])
    func eachAddressHasAKind(address: String, kind: ServerAddressKind) throws {
        let url = try #require(URL(string: address))
        #expect(ServerAddressKind(url) == kind)
    }
}

/// How each of a server's addresses answers a probe in a test.
private enum Answer: Sendable {
    /// The server answers, after `delay`.
    case server(after: Duration = .zero)
    /// Another server answers, after `delay`.
    case another(after: Duration = .zero)
    /// Nothing answers, and that's known after `delay`.
    case nothing(after: Duration = .zero)
    /// Nothing answers, and the probe waits until it's cancelled.
    case silence
}

@Suite struct AddressResolverTests {
    private let addresses: Addresses

    init() throws {
        addresses = try Addresses()
    }

    private func server(at url: URL, _ all: [URL]) -> Server {
        Server(id: "s", name: "Living Room", url: url, addresses: all)
    }

    private func resolver(_ answers: [URL: Answer], headStart: Duration = .seconds(5)) -> AddressResolver {
        AddressResolver(headStart: headStart) { url in
            switch answers[url] ?? .silence {
            case .server(let delay):
                try await Task.sleep(for: delay)
                return "s"
            case .another(let delay):
                try await Task.sleep(for: delay)
                return "another-server"
            case .nothing(let delay):
                try await Task.sleep(for: delay)
                throw SerafinError.serverUnreachable
            case .silence:
                try await Task.sleep(for: .seconds(600))
                throw SerafinError.serverUnreachable
            }
        }
    }

    @Test func homeAddressesComeFirstOnWiFiAndRemoteOnesOnCellular() {
        let server = server(at: addresses.remote, [addresses.remote, addresses.home, addresses.tailscale])
        #expect(
            AddressResolver.ranking(of: server, prefersLocal: true) == [
                addresses.home, addresses.tailscale, addresses.remote,
            ])
        #expect(
            AddressResolver.ranking(of: server, prefersLocal: false) == [
                addresses.remote, addresses.tailscale, addresses.home,
            ])
    }

    @Test func withinAKindTheAddressInUseComesFirst() throws {
        let nas = try #require(URL(string: "http://nas.local:8096"))
        let server = server(at: nas, [addresses.home, nas, addresses.remote])
        #expect(AddressResolver.ranking(of: server, prefersLocal: true) == [nas, addresses.home, addresses.remote])
    }

    @Test func atHomeTheHomeAddressWins() async {
        let server = server(at: addresses.remote, [addresses.remote, addresses.home])
        let resolver = resolver([addresses.home: .server(), addresses.remote: .server()])
        #expect(await resolver.bestAddress(of: server, prefersLocal: true) == addresses.home)
    }

    @Test func onCellularTheRemoteAddressWins() async {
        let server = server(at: addresses.home, [addresses.home, addresses.remote])
        let resolver = resolver([addresses.home: .server(), addresses.remote: .server()])
        #expect(await resolver.bestAddress(of: server, prefersLocal: false) == addresses.remote)
    }

    @Test func aHomeAddressThatAnswersWithinTheHeadStartBeatsAQuickerRemoteOne() async {
        let server = server(at: addresses.remote, [addresses.remote, addresses.home])
        let resolver = resolver([
            addresses.home: .server(after: .milliseconds(100)), addresses.remote: .server(),
        ])
        #expect(await resolver.bestAddress(of: server, prefersLocal: true) == addresses.home)
    }

    @Test func awayFromHomeTheRemoteAddressWinsOnceTheHeadStartIsOver() async {
        let server = server(at: addresses.home, [addresses.home, addresses.remote])
        let resolver = resolver(
            [addresses.home: .silence, addresses.remote: .server()], headStart: .milliseconds(50))
        let started = ContinuousClock.now
        #expect(await resolver.bestAddress(of: server, prefersLocal: true) == addresses.remote)
        // It never waited for the home address to give up.
        #expect(ContinuousClock.now - started < .seconds(60))
    }

    @Test func aHomeAddressKnownNotToAnswerHoldsNothingUp() async {
        let server = server(at: addresses.home, [addresses.home, addresses.remote])
        let resolver = resolver(
            [addresses.home: .nothing(), addresses.remote: .server(after: .milliseconds(50))],
            headStart: .seconds(600))
        let started = ContinuousClock.now
        #expect(await resolver.bestAddress(of: server, prefersLocal: true) == addresses.remote)
        #expect(ContinuousClock.now - started < .seconds(60))
    }

    @Test func anotherServerAtAHomeAddressNeverWins() async {
        // On someone else's network, another Jellyfin server can have the same home address.
        let server = server(at: addresses.remote, [addresses.remote, addresses.home])
        let resolver = resolver([addresses.home: .another(), addresses.remote: .server()])
        #expect(await resolver.bestAddress(of: server, prefersLocal: true) == addresses.remote)
    }

    @Test func whenNoAddressAnswersThereIsNoBestAddress() async {
        let server = server(at: addresses.remote, [addresses.remote, addresses.home])
        let resolver = resolver([addresses.home: .nothing(), addresses.remote: .another()])
        #expect(await resolver.bestAddress(of: server, prefersLocal: true) == nil)
    }

    @Test func theTestFindsEveryAddressWhereTheServerAnswers() async {
        let server = server(at: addresses.remote, [addresses.remote, addresses.home, addresses.tailscale])
        let resolver = resolver([
            addresses.home: .server(), addresses.tailscale: .another(), addresses.remote: .server(),
        ])
        let expected: Set<URL> = [addresses.home, addresses.remote]
        #expect(await resolver.answeringAddresses(of: server) == expected)
    }

    @Test func aWinnerWaitsOnlyForBetterAddressesStillInTheRunning() {
        #expect(AddressResolver.winner(of: [.server, .waiting], isHeadStartOver: false) == 0)
        #expect(AddressResolver.winner(of: [.waiting, .server], isHeadStartOver: false) == nil)
        #expect(AddressResolver.winner(of: [.waiting, .server], isHeadStartOver: true) == 1)
        #expect(AddressResolver.winner(of: [.none, .server], isHeadStartOver: false) == 1)
        #expect(AddressResolver.winner(of: [.none, .waiting, .server], isHeadStartOver: false) == nil)
        #expect(AddressResolver.winner(of: [.none, .none], isHeadStartOver: true) == nil)
        #expect(AddressResolver.winner(of: [.waiting, .waiting], isHeadStartOver: true) == nil)
    }
}

/// An address longer than any a server really gives, which Serafin doesn't read.
private let oversizedAddress = "http://" + String(repeating: "a", count: 600) + ".local"

@Suite struct LocalAddressTests {
    private func info(localAddress: String?) throws -> PublicServerInfo {
        try PublicServerInfo(
            validating: PublicSystemInfo(
                id: "s", localAddress: localAddress, productName: "Jellyfin Server", serverName: "Home",
                version: "10.10.7"))
    }

    @Test func theAddressAServerGivesForItselfIsRead() throws {
        let home = try info(localAddress: "http://192.168.1.20:8096/").localAddress
        #expect(home?.absoluteString == "http://192.168.1.20:8096")
        let tailnet = try info(localAddress: "https://nas.tailnet-1234.ts.net").localAddress
        #expect(tailnet?.absoluteString == "https://nas.tailnet-1234.ts.net")
    }

    @Test(arguments: [
        nil, "", "192.168.1.20:8096", "javascript:alert(1)", "file:///etc/passwd", "ftp://192.168.1.20", "http://",
        "http://user:secret@192.168.1.20:8096", oversizedAddress,
    ])
    func anAddressSerafinCantUseIsLeftOut(_ text: String?) throws {
        #expect(try info(localAddress: text).localAddress == nil)
    }
}
