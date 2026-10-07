import Foundation
import JellyfinAPI

/// Who this install is to a Jellyfin server.
///
/// Every request names the client, the device, a device ID and the app version, so users can see and revoke
/// each install in the Jellyfin dashboard. The device ID is a UUID generated on first use and kept in the
/// ``SecretStore``, so it survives launches but not a reinstall on another device.
public actor DeviceIdentity {
    /// The client name every server sees.
    public static let clientName = "Serafin"

    /// The Keychain key of the device ID.
    static let deviceIDKey = "device-id"

    /// The device name servers show, such as "iPhone".
    public nonisolated let deviceName: String

    /// The app version servers show, such as "0.1.0".
    public nonisolated let version: String

    private let secrets: any SecretStore
    private var cachedDeviceID: String?

    /// Creates the identity.
    ///
    /// - Parameters:
    ///   - secrets: Where the device ID is kept.
    ///   - deviceName: The device name servers show. The app passes the device model, such as "iPhone".
    ///   - version: The app version servers show.
    public init(secrets: any SecretStore, deviceName: String, version: String = DeviceIdentity.bundleVersion) {
        self.secrets = secrets
        self.deviceName = deviceName
        self.version = version
    }

    /// The app's marketing version from the main bundle, or "0" when the bundle has none, as in tests.
    public static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// This install's stable ID, created on first use.
    public func deviceID() throws -> String {
        if let cachedDeviceID { return cachedDeviceID }
        let id: String
        if let saved = try secrets.get(Self.deviceIDKey) {
            id = saved
        } else {
            id = UUID().uuidString
            try secrets.set(id, for: Self.deviceIDKey)
        }
        cachedDeviceID = id
        return id
    }

    /// The SDK configuration for talking to `serverURL`, signed in with `accessToken` when one is given.
    public func configuration(serverURL: URL, accessToken: String?) throws -> JellyfinClient.Configuration {
        JellyfinClient.Configuration(
            url: serverURL,
            accessToken: accessToken,
            client: Self.clientName,
            deviceName: deviceName,
            deviceID: try deviceID(),
            version: version
        )
    }

    /// The `Authorization` header value for requests made outside the SDK, such as image loads.
    ///
    /// Values are quoted, so a device name with a comma or space cannot break the header.
    public func authorizationHeader(accessToken: String?) throws -> String {
        var fields = [
            ("Client", Self.clientName),
            ("Device", deviceName),
            ("DeviceId", try deviceID()),
            ("Version", version),
        ]
        if let accessToken {
            fields.append(("Token", accessToken))
        }
        let quoted = fields.map { name, value in
            let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
                of: "\"", with: "\\\"")
            return "\(name)=\"\(escaped)\""
        }
        return "MediaBrowser " + quoted.joined(separator: ", ")
    }
}
