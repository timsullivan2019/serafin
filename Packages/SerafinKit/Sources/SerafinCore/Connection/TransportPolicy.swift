import Foundation

/// How a connection to a server is protected.
public enum TransportSecurity: Equatable, Sendable {
    /// HTTPS.
    case encrypted
    /// Plain HTTP to a private address. Allowed only after the user has seen a warning.
    case unencryptedOnPrivateNetwork
}

/// Serafin's rule for plain HTTP: allowed on the user's own network after a warning, never to a public host.
public enum TransportPolicy {
    /// How a connection to `url` would be protected.
    ///
    /// - Throws: ``SerafinError/insecureTransport`` for plain HTTP to a public host, and
    ///   ``SerafinError/invalidAddress`` for anything that is not http or https.
    public static func security(of url: URL) throws -> TransportSecurity {
        switch url.scheme?.lowercased() {
        case "https":
            return .encrypted
        case "http":
            guard let host = url.host(), PrivateNetwork.isPrivate(host: host) else {
                throw SerafinError.insecureTransport
            }
            return .unencryptedOnPrivateNetwork
        default:
            throw SerafinError.invalidAddress
        }
    }
}
