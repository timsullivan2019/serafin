import Foundation
import Testing

@testable import SerafinCore

@Suite struct ClientFactoryTests {
    private let server = Server(
        id: "server-1",
        name: "Home",
        url: URL(string: "https://media.example.com") ?? URL.temporaryDirectory
    )

    private func factory(_ secrets: InMemorySecretStore) throws -> (ClientFactory, SessionStore) {
        let sessions = SessionStore(
            secrets: secrets,
            defaults: try #require(UserDefaults(suiteName: "serafin-tests-\(UUID().uuidString)"))
        )
        let identity = DeviceIdentity(secrets: secrets, deviceName: "iPhone", version: "0.1.0")
        return (ClientFactory(identity: identity, sessions: sessions), sessions)
    }

    @Test func anonymousClientsCarryNoToken() async throws {
        let (factory, _) = try factory(InMemorySecretStore())
        let client = try await factory.client(for: server)
        #expect(client.accessToken == nil)
        #expect(client.configuration.url == server.url)
        #expect(client.configuration.client == "Serafin")
    }

    @Test func signedInClientsCarryTheUsersToken() async throws {
        let secrets = InMemorySecretStore()
        let (factory, sessions) = try factory(secrets)
        try await sessions.setToken("token-1", for: SessionKey(serverID: "server-1", userID: "alice"))
        #expect(try await factory.client(for: server, userID: "alice").accessToken == "token-1")
        #expect(try await factory.client(for: server, userID: "bob").accessToken == nil)
    }
}
