import Foundation
import JellyfinAPI

/// Builds a `JellyfinClient` for a server, carrying this install's identity and, for a signed-in user, their
/// access token.
public struct ClientFactory: Sendable {
    /// Makes the `URLSession` delegate for a server's connections, such as the certificate-pinning delegate.
    public typealias SessionDelegateProvider = @Sendable (Server) -> (any URLSessionDelegate)?

    private let identity: DeviceIdentity
    private let sessions: SessionStore
    private let sessionDelegate: SessionDelegateProvider
    private let sessionConfiguration: @Sendable () -> URLSessionConfiguration

    /// Creates a factory.
    ///
    /// - Parameters:
    ///   - identity: Who this install is to servers.
    ///   - sessions: Where access tokens are kept.
    ///   - sessionDelegate: The `URLSession` delegate for each server's connections. Certificate pinning plugs in
    ///     here; the default uses the system's own trust evaluation.
    ///   - sessionConfiguration: Makes each client's `URLSession` configuration. The default is ephemeral, so
    ///     responses are never cached on disk and no cookies are kept. Tests pass one with a stub protocol.
    public init(
        identity: DeviceIdentity,
        sessions: SessionStore,
        sessionDelegate: @escaping SessionDelegateProvider = { _ in nil },
        sessionConfiguration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }
    ) {
        self.identity = identity
        self.sessions = sessions
        self.sessionDelegate = sessionDelegate
        self.sessionConfiguration = sessionConfiguration
    }

    /// A client for `server`, signed in as `userID` when that user has a saved token.
    ///
    /// - Parameters:
    ///   - server: The server to talk to.
    ///   - userID: The user to sign in as, or nil for an anonymous client, such as for public info and sign-in.
    public func client(for server: Server, userID: String? = nil) async throws -> JellyfinClient {
        var token: String?
        if let userID {
            token = try await sessions.token(for: SessionKey(serverID: server.id, userID: userID))
        }
        return try await client(for: server, accessToken: token)
    }

    /// A client for `server` that sends `accessToken`, or none when it is nil.
    func client(for server: Server, accessToken: String?) async throws -> JellyfinClient {
        let configuration = try await identity.configuration(serverURL: server.url, accessToken: accessToken)
        return JellyfinClient(
            configuration: configuration,
            sessionConfiguration: sessionConfiguration(),
            sessionDelegate: sessionDelegate(server)
        )
    }
}
