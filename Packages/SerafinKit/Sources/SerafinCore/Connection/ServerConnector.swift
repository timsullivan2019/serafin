import Foundation
import JellyfinAPI

/// A server that answered and checked out, ready to be saved and signed in to.
public struct ConnectedServer: Equatable, Identifiable, Sendable {
    /// The server to save, at the address that answered.
    public let server: Server
    /// What the server reported about itself.
    public let info: PublicServerInfo
    /// Whether the connection is HTTPS or plain HTTP on a private network.
    public let security: TransportSecurity

    /// The server's own ID.
    public var id: String { server.id }
}

/// Finds a Jellyfin server at an address the user typed or discovered.
///
/// Only the public info endpoint is called, and nothing about the device or user is sent with it: the device ID
/// first goes to a server at sign-in, once it has shown it is Jellyfin.
public struct ServerConnector: Sendable {
    /// The most Serafin reads of a server's public info. A real answer is well under a kilobyte.
    static let maximumInfoSize = 64 * 1024
    /// How long a request may sit idle before the address counts as unreachable.
    static let timeout: TimeInterval = 15

    private let pinning: PinningDelegate
    private let sessionConfiguration: @Sendable () -> URLSessionConfiguration

    /// Creates a connector.
    ///
    /// - Parameters:
    ///   - pinning: The delegate that accepts pinned certificates and records refused ones.
    ///   - sessionConfiguration: Makes the `URLSession` configuration. Tests pass one with a stub protocol.
    public init(
        pinning: PinningDelegate,
        sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
    ) {
        self.pinning = pinning
        self.sessionConfiguration = sessionConfiguration
    }

    /// Connects to `address`, trying its fallback port once if nothing answers at the first address or what answers
    /// is not Jellyfin, such as a router or NAS page on port 80.
    ///
    /// - Throws: ``SerafinError/insecureTransport`` before any request for plain HTTP to a public host;
    ///   ``SerafinError/untrustedCertificate(_:)`` when the server's certificate needs the user's pin;
    ///   ``SerafinError/notJellyfin``, ``SerafinError/unsupportedServerVersion(_:)`` or
    ///   ``SerafinError/serverUnreachable`` otherwise. When both addresses fail, the first address's error wins
    ///   unless the fallback got further.
    public func connect(to address: ServerAddress) async throws -> ConnectedServer {
        do {
            return try await connect(to: address.url)
        } catch let error as SerafinError where error == .serverUnreachable || error == .notJellyfin {
            guard let fallback = address.fallback else { throw error }
            do {
                return try await connect(to: fallback)
            } catch SerafinError.serverUnreachable {
                throw error
            }
        }
    }

    /// Connects to exactly `url`, with no fallback.
    public func connect(to url: URL) async throws -> ConnectedServer {
        let security = try TransportPolicy.security(of: url)
        let host = url.host() ?? ""
        pinning.forgetRejection(for: host)
        let info: PublicServerInfo
        do {
            info = try PublicServerInfo(validating: try await publicSystemInfo(at: url))
        } catch let error as SerafinError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch let error as URLError {
            try Task.checkCancellation()
            if error.isCertificateFailure, let presented = pinning.rejectedCertificate(for: host) {
                throw SerafinError.untrustedCertificate(presented)
            }
            if error.code == .appTransportSecurityRequiresSecureConnection {
                throw SerafinError.plainHTTPBlocked
            }
            throw SerafinError.serverUnreachable
        } catch {
            // Something answered, but not with Jellyfin's public info: an HTML page, malformed JSON, another product.
            throw SerafinError.notJellyfin
        }
        let server = Server(id: info.id, name: info.name, url: url)
        return ConnectedServer(server: server, info: info, security: security)
    }

    /// Fetches and decodes the public system info at `url`, reading at most ``maximumInfoSize`` bytes.
    ///
    /// The session is made for this one request and torn down after it, so no connection or delegate outlives it.
    private func publicSystemInfo(at url: URL) async throws -> PublicSystemInfo {
        guard let path = Paths.getPublicSystemInfo.url?.path() else { throw SerafinError.notJellyfin }
        let session = URLSession(configuration: sessionConfiguration(), delegate: pinning, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var request = URLRequest(url: url.appending(path: path), timeoutInterval: Self.timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SerafinError.notJellyfin }

        var body = Data()
        for try await byte in bytes {
            body.append(byte)
            guard body.count <= Self.maximumInfoSize else { throw SerafinError.notJellyfin }
        }
        return try JSONDecoder().decode(PublicSystemInfo.self, from: body)
    }
}
