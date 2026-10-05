import Foundation
import SerafinCore
import Testing

// Signing out against the real Keychain, hosted in the app for the same reason as KeychainSecretStoreTests.
@Suite struct SignOutKeychainTests {
    @Test func signingOutDeletesTheTokenFromTheKeychainEvenWhenTheServerIsDown() async throws {
        let secrets = KeychainSecretStore(service: "app.getserafin.serafin.tests.\(UUID().uuidString)")
        let suite = "app.getserafin.serafin.tests.\(UUID().uuidString)"
        defer {
            try? secrets.delete("token.server.user")
            try? secrets.delete("device-id")
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        // Nothing listens on the discard port, so the server's sign-out fails at once and the device signs out alone.
        let server = Server(
            id: "server",
            name: "Home",
            url: try #require(URL(string: "http://127.0.0.1:9")),
            users: [ServerUser(id: "user", name: "Alice")]
        )
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let store = ServerStore(fileURL: directory.appending(path: "servers.json"))
        try await store.save(server)
        try secrets.set("token-value", for: "token.server.user")
        let accounts = Accounts(
            secrets: secrets,
            deviceName: "iPhone",
            version: "0.1.0",
            serverStore: store,
            defaults: try #require(UserDefaults(suiteName: suite)),
            imageDiskCache: false,
            homeSnapshots: HomeSnapshotStore(directory: directory.appending(path: "home"))
        )

        try await accounts.signOut(SessionKey(serverID: "server", userID: "user"))

        #expect(try secrets.get("token.server.user") == nil)
        #expect(try await store.server(id: "server")?.users.isEmpty == true)
    }
}
