import Foundation

/// The name last used to sign in to each server on this device, so signing in to it again starts with the name
/// filled in. Only the name: the password is never kept.
enum LastUsername {
    private static let prefix = "lastUsername."

    /// The name last used on the server with `serverID`, if any.
    static func name(forServer serverID: String, in defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: prefix + serverID).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Remembers `name` as the last used on the server with `serverID`.
    static func save(_ name: String, forServer serverID: String, in defaults: UserDefaults = .standard) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        defaults.set(name, forKey: prefix + serverID)
    }

    /// Forgets the name for the server with `serverID`, when the server is removed.
    static func forget(server serverID: String, in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: prefix + serverID)
    }
}
