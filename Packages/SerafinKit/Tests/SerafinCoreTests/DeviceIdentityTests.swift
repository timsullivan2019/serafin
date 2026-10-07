import Foundation
import Testing

@testable import SerafinCore

@Suite struct DeviceIdentityTests {
    @Test func theDeviceIDIsCreatedOnceAndKept() async throws {
        let secrets = InMemorySecretStore()
        let first = try await DeviceIdentity(secrets: secrets, deviceName: "iPhone", version: "1.0").deviceID()
        let second = try await DeviceIdentity(secrets: secrets, deviceName: "iPhone", version: "1.0").deviceID()
        #expect(first == second)
        #expect(UUID(uuidString: first) != nil)
        #expect(secrets.get(DeviceIdentity.deviceIDKey) == first)
    }

    @Test func anotherInstallGetsAnotherID() async throws {
        let one = try await DeviceIdentity(secrets: InMemorySecretStore(), deviceName: "iPhone").deviceID()
        let two = try await DeviceIdentity(secrets: InMemorySecretStore(), deviceName: "iPhone").deviceID()
        #expect(one != two)
    }

    @Test func theConfigurationNamesSerafin() async throws {
        let secrets = InMemorySecretStore([DeviceIdentity.deviceIDKey: "device-1"])
        let identity = DeviceIdentity(secrets: secrets, deviceName: "iPad", version: "0.1.0")
        let url = try #require(URL(string: "https://media.example.com"))
        let configuration = try await identity.configuration(serverURL: url, accessToken: "token-1")
        #expect(configuration.client == "Serafin")
        #expect(configuration.deviceName == "iPad")
        #expect(configuration.deviceID == "device-1")
        #expect(configuration.version == "0.1.0")
        #expect(configuration.accessToken == "token-1")
        #expect(configuration.url == url)
    }

    @Test func theAuthorizationHeaderQuotesEveryValue() async throws {
        let secrets = InMemorySecretStore([DeviceIdentity.deviceIDKey: "device-1"])
        let identity = DeviceIdentity(secrets: secrets, deviceName: "Tim's \"iPad\", 2", version: "0.1.0")
        #expect(
            try await identity.authorizationHeader(accessToken: nil)
                == #"MediaBrowser Client="Serafin", Device="Tim's \"iPad\", 2", DeviceId="device-1", Version="0.1.0""#
        )
        #expect(try await identity.authorizationHeader(accessToken: "abc").hasSuffix(#", Token="abc""#))
    }
}
