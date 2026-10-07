import Foundation
import SerafinCore
import Testing

// The Keychain answers only processes with an app identity. On the simulator a bare test bundle has none, so these
// tests run inside the Serafin app as their host.
@Suite(.serialized) struct KeychainSecretStoreTests {
    private let store = KeychainSecretStore(service: "app.getserafin.serafin.tests.\(UUID().uuidString)")

    @Test func roundTripsAValue() throws {
        defer { try? store.delete("token") }
        #expect(try store.get("token") == nil)
        try store.set("first", for: "token")
        #expect(try store.get("token") == "first")
        try store.set("second", for: "token")
        #expect(try store.get("token") == "second")
        try store.delete("token")
        #expect(try store.get("token") == nil)
    }

    @Test func keepsKeysApart() throws {
        defer {
            try? store.delete("a")
            try? store.delete("b")
        }
        try store.set("one", for: "a")
        try store.set("two", for: "b")
        #expect(try store.get("a") == "one")
        #expect(try store.get("b") == "two")
    }

    @Test func deletingAMissingKeyIsFine() throws {
        try store.delete("never-saved")
    }

    @Test func theDeviceIDIsKeptInTheKeychain() async throws {
        defer { try? store.delete("device-id") }
        let first = try await DeviceIdentity(secrets: store, deviceName: "iPhone").deviceID()
        let second = try await DeviceIdentity(secrets: store, deviceName: "iPhone").deviceID()
        #expect(first == second)
        #expect(try store.get("device-id") == first)
    }
}
