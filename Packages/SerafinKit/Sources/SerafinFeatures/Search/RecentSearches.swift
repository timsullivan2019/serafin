import Foundation
import SerafinCore

/// The last ten searches on this device, kept for each account so each user sees their own, for the search tab to
/// offer again.
///
/// They stay in the app's own defaults on this device and are never sent anywhere. They go when the account signs
/// out or its server is removed, and the search tab's Clear button empties them.
struct RecentSearches {
    /// How many searches are kept.
    static let limit = 10
    private static let prefix = "recentSearches."

    private let defaults: UserDefaults
    private let key: String?

    /// The searches of `account`, or none kept at all when no one is signed in, as in previews.
    init(account: SessionKey?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = account.map { "\(Self.prefix)\($0.serverID).\($0.userID)" }
    }

    /// The searches, newest first.
    var terms: [String] {
        key.flatMap { defaults.stringArray(forKey: $0) } ?? []
    }

    /// Puts `term` first, dropping an earlier search that differs only in case or spacing, and keeps the newest ten.
    ///
    /// - Returns: The searches, newest first.
    @discardableResult func record(_ term: String) -> [String] {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !term.isEmpty else { return terms }
        let others = terms.filter {
            $0.compare(term, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
        }
        let updated = Array(([term] + others).prefix(Self.limit))
        defaults.set(updated, forKey: key)
        return updated
    }

    /// Forgets every search.
    func clear() {
        guard let key else { return }
        defaults.removeObject(forKey: key)
    }

    /// Forgets the searches of `account`, when it signs out on this device.
    static func forget(_ account: SessionKey, in defaults: UserDefaults = .standard) {
        RecentSearches(account: account, defaults: defaults).clear()
    }

    /// Forgets the searches of every account on the server with `serverID`, when the server is removed.
    static func forget(server serverID: String, in defaults: UserDefaults = .standard) {
        let serverPrefix = "\(prefix)\(serverID)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(serverPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
