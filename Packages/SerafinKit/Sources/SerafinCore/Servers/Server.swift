import Foundation

/// A Jellyfin server the user has added. It holds no secrets: tokens and certificate pins live in the
/// ``SecretStore``.
public struct Server: Codable, Hashable, Identifiable, Sendable {
    /// The server's own ID, from its public system info. It stays the same if the server moves address.
    public var id: String
    /// The name the server reports, shown in Serafin's server list.
    public var name: String
    /// The address Serafin connects to.
    public var url: URL
    /// The user who was signed in most recently, so switching servers lands on the right account.
    public var lastUserID: String?

    /// Creates a server.
    ///
    /// - Parameters:
    ///   - id: The server's own ID.
    ///   - name: The name the server reports.
    ///   - url: The address Serafin connects to.
    ///   - lastUserID: The user signed in most recently, if any.
    public init(id: String, name: String, url: URL, lastUserID: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.lastUserID = lastUserID
    }
}
