import Foundation
import Testing

@testable import SerafinCore

@Suite struct ServerStoreTests {
    private let fileURL = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)/servers.json")

    private func server(_ id: String) throws -> Server {
        Server(id: id, name: "Server \(id)", url: try #require(URL(string: "https://\(id).example.com")))
    }

    @Test func startsEmpty() async throws {
        #expect(try await ServerStore(fileURL: fileURL).servers().isEmpty)
    }

    @Test func savedServersSurviveARelaunch() async throws {
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = ServerStore(fileURL: fileURL)
        try await store.save(try server("a"))
        try await store.save(try server("b"))
        try await store.setLastUser("user-1", forServer: "b")

        let reloaded = try await ServerStore(fileURL: fileURL).servers()
        #expect(reloaded.map(\.id) == ["a", "b"])
        #expect(reloaded[1].lastUserID == "user-1")
        #expect(reloaded[1].url.host() == "b.example.com")
    }

    @Test func savingAnExistingServerReplacesItInPlace() async throws {
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = ServerStore(fileURL: fileURL)
        try await store.save(try server("a"))
        try await store.save(try server("b"))
        var renamed = try server("a")
        renamed.name = "Living Room"
        try await store.save(renamed)
        let servers = try await store.servers()
        #expect(servers.map(\.id) == ["a", "b"])
        #expect(servers[0].name == "Living Room")
    }

    @Test func removesServers() async throws {
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = ServerStore(fileURL: fileURL)
        try await store.save(try server("a"))
        try await store.remove(id: "a")
        try await store.remove(id: "missing")
        #expect(try await ServerStore(fileURL: fileURL).servers().isEmpty)
    }

    @Test func theFileIsVersionedJSONWithoutSecrets() async throws {
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try await ServerStore(fileURL: fileURL).save(try server("a"))
        let json = try #require(String(data: try Data(contentsOf: fileURL), encoding: .utf8))
        #expect(json.contains(#""version" : 1"#))
        #expect(!json.lowercased().contains("token"))
    }

    @Test func anUnreadableFileIsAnError() async throws {
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)
        await #expect(throws: SerafinError.serverStoreUnavailable) {
            try await ServerStore(fileURL: fileURL).servers()
        }
    }
}

@Suite struct ServerNameTests {
    private func name(_ reported: String, at address: String) throws -> String {
        Server(id: "s", name: reported, url: try #require(URL(string: address))).displayName
    }

    @Test func aNameSomeoneChoseIsShownAsItIs() throws {
        #expect(try name("Living Room", at: "https://media.example.com") == "Living Room")
        #expect(try name("cafe", at: "http://192.168.1.20:8096") == "cafe")
    }

    @Test(arguments: ["3f9a1c07be52", "3F9A1C07BE52", "", "  ", String(repeating: "ab", count: 16)])
    func aGeneratedNameGivesWayToTheHostName(reported: String) throws {
        #expect(try name(reported, at: "http://nas:8096") == "nas")
        #expect(try name(reported, at: "https://media.example.com/jellyfin") == "media.example.com")
    }

    @Test func anAddressGivesNoBetterNameThanJellyfin() throws {
        #expect(try name("3f9a1c07be52", at: "http://192.168.1.20:8096") == "Jellyfin")
        #expect(try name("3f9a1c07be52", at: "http://[fd7a:115c:a1e0::1]:8096") == "Jellyfin")
    }

    @Test func serversFoundNearbyFollowTheSameRule() throws {
        let url = try #require(URL(string: "http://192.168.1.20:8096"))
        #expect(DiscoveredServer(id: "s", name: "3f9a1c07be52", url: url).displayName == "Jellyfin")
        #expect(DiscoveredServer(id: "s", name: "Den", url: url).displayName == "Den")
    }

    @Test func aRenameIsSavedAndKeepsTheUsers() async throws {
        let fileURL = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)/servers.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }
        let store = ServerStore(fileURL: fileURL)
        let url = try #require(URL(string: "https://a.example.com"))
        try await store.save(
            Server(id: "a", name: "3f9a1c07be52", url: url, users: [ServerUser(id: "u", name: "Alice")]))
        try await store.setName("Living Room", forServer: "a")
        try await store.setName("Ignored", forServer: "missing")

        let saved = try await ServerStore(fileURL: fileURL).servers()
        #expect(saved.map(\.name) == ["Living Room"])
        #expect(saved.first?.users.map(\.id) == ["u"])
    }
}
