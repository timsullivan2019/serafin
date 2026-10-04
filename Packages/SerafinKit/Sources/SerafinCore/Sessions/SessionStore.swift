import Foundation

/// Identifies a signed-in user on a server.
public struct SessionKey: Codable, Hashable, Sendable {
    /// The ``Server/id`` of the server.
    public var serverID: String
    /// The user's ID on that server.
    public var userID: String

    /// Creates a session key.
    public init(serverID: String, userID: String) {
        self.serverID = serverID
        self.userID = userID
    }

    /// The ``SecretStore`` key that holds this session's access token.
    var tokenKey: String { "token.\(serverID).\(userID)" }
}

/// Access tokens for every signed-in user, and which session is current.
///
/// Each token is its own ``SecretStore`` item, so signing out of one server never touches another. The current
/// selection holds only IDs and lives in `UserDefaults`.
public actor SessionStore {
    private static let currentKey = "app.getserafin.serafin.currentSession"

    private let secrets: any SecretStore
    private let defaults: UserDefaults

    /// Creates a store.
    ///
    /// - Parameters:
    ///   - secrets: Where tokens are kept.
    ///   - defaults: Where the current selection is kept. Tests pass a throwaway suite.
    public init(secrets: any SecretStore, defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.defaults = defaults
    }

    /// The access token for a session, or nil when the user is not signed in.
    public func token(for session: SessionKey) throws -> String? {
        try secrets.get(session.tokenKey)
    }

    /// Saves the access token for a session.
    public func setToken(_ token: String, for session: SessionKey) throws {
        try secrets.set(token, for: session.tokenKey)
    }

    /// Deletes the access token for a session, and clears the current selection if it was this session.
    public func removeToken(for session: SessionKey) throws {
        try secrets.delete(session.tokenKey)
        if current == session {
            setCurrent(nil)
        }
    }

    /// The session the app is using, if any.
    public var current: SessionKey? {
        guard let data = defaults.data(forKey: Self.currentKey) else { return nil }
        return try? JSONDecoder().decode(SessionKey.self, from: data)
    }

    /// Makes `session` the one the app uses, or clears the selection when nil.
    public func setCurrent(_ session: SessionKey?) {
        guard let session, let data = try? JSONEncoder().encode(session) else {
            defaults.removeObject(forKey: Self.currentKey)
            return
        }
        defaults.set(data, forKey: Self.currentKey)
    }
}
