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
