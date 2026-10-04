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
    /// The users signed in to this server on this device, in the order they signed in.
    public var users: [ServerUser]

    /// Creates a server.
    ///
    /// - Parameters:
    ///   - id: The server's own ID.
    ///   - name: The name the server reports.
    ///   - url: The address Serafin connects to.
    ///   - lastUserID: The user signed in most recently, if any.
    ///   - users: The users signed in to this server.
    public init(id: String, name: String, url: URL, lastUserID: String? = nil, users: [ServerUser] = []) {
        self.id = id
        self.name = name
        self.url = url
        self.lastUserID = lastUserID
        self.users = users
    }

    /// The signed-in user with `id`, if there is one.
    public func user(id: String) -> ServerUser? {
        users.first { $0.id == id }
    }
}

/// A user signed in to a server. Only the ID and the name are kept, to list accounts without a network request;
/// the user's token lives in the ``SecretStore``.
public struct ServerUser: Codable, Hashable, Identifiable, Sendable {
    /// The user's ID on the server.
    public var id: String
    /// The user's name, as the server reports it.
    public var name: String

    /// Creates a user.
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
