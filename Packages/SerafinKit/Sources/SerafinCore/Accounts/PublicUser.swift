import Foundation
import JellyfinAPI

/// A user a server lists on its sign-in screen, as Jellyfin's own web app shows them: a picture and a name to tap.
public struct PublicUser: Hashable, Identifiable, Sendable {
    /// The user's ID.
    public let id: String
    /// The user's name, which signing in asks for.
    public let name: String
    /// The tag of the user's picture, or nil when they haven't set one.
    public let imageTag: String?
    /// Whether the user has a password. Without one, tapping their picture signs in at once.
    public let hasPassword: Bool

    /// Creates a user.
    public init(id: String, name: String, imageTag: String?, hasPassword: Bool) {
        self.id = id
        self.name = name
        self.imageTag = imageTag
        self.hasPassword = hasPassword
    }

    /// The users in the server's answer to `/Users/Public`, at most `limit` of them.
    ///
    /// Read field by field rather than as the SDK's `UserDto`, whose policy has fields some servers leave out. A
    /// user without an ID or a name is skipped, and one whose password state isn't given is taken to have one.
    static func list(from data: Data, limit: Int) -> [PublicUser] {
        guard case .array(let users)? = try? JSONDecoder().decode(AnyJSON.self, from: data) else { return [] }
        return users.lazy.compactMap { user -> PublicUser? in
            guard case .object(let fields) = user,
                case .string(let id)? = fields["Id"], !id.isEmpty,
                case .string(let rawName)? = fields["Name"]
            else { return nil }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            var imageTag: String?
            if case .string(let tag)? = fields["PrimaryImageTag"], !tag.isEmpty { imageTag = tag }
            var hasPassword = true
            if case .bool(let value)? = fields["HasPassword"] { hasPassword = value }
            return PublicUser(id: id, name: String(name.prefix(64)), imageTag: imageTag, hasPassword: hasPassword)
        }
        .prefix(limit)
        .map { $0 }
    }
}
