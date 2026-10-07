import Foundation
import Testing

@testable import SerafinCore

@Suite struct SessionStoreTests {
    private let suiteName = "serafin-tests-\(UUID().uuidString)"

    private func makeStore(_ secrets: InMemorySecretStore = InMemorySecretStore()) throws -> SessionStore {
        SessionStore(secrets: secrets, defaults: try #require(UserDefaults(suiteName: suiteName)))
    }

    @Test func tokensForDifferentServersAndUsersStayApart() async throws {
        let store = try makeStore()
        let alice = SessionKey(serverID: "server-1", userID: "alice")
        let aliceElsewhere = SessionKey(serverID: "server-2", userID: "alice")
        let bob = SessionKey(serverID: "server-1", userID: "bob")
        try await store.setToken("t1", for: alice)
        try await store.setToken("t2", for: aliceElsewhere)
        try await store.setToken("t3", for: bob)

        try await store.removeToken(for: alice)
        #expect(try await store.token(for: alice) == nil)
        #expect(try await store.token(for: aliceElsewhere) == "t2")
        #expect(try await store.token(for: bob) == "t3")
    }

    @Test func tokensLiveInTheSecretStoreOnly() async throws {
        let secrets = InMemorySecretStore()
        let store = try makeStore(secrets)
        let session = SessionKey(serverID: "server-1", userID: "alice")
        try await store.setToken("secret-token", for: session)
        await store.setCurrent(session)
        #expect(secrets.get("token.server-1.alice") == "secret-token")
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let saved = defaults.dictionaryRepresentation().values.compactMap { $0 as? Data }
        #expect(saved.allSatisfy { !String(decoding: $0, as: UTF8.self).contains("secret-token") })
    }

    @Test func theCurrentSessionSurvivesARelaunch() async throws {
        let session = SessionKey(serverID: "server-1", userID: "alice")
        try await makeStore().setCurrent(session)
        #expect(try await makeStore().current == session)
    }

    @Test func removingTheCurrentSessionsTokenClearsTheSelection() async throws {
        let store = try makeStore()
        let session = SessionKey(serverID: "server-1", userID: "alice")
        try await store.setToken("t1", for: session)
        await store.setCurrent(session)
        try await store.removeToken(for: session)
        #expect(await store.current == nil)
    }
}
