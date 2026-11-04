import Foundation
import SerafinCore

/// The version last picked for each movie and episode on this device, kept for each account, so Play starts the
/// version picked for it on its page or in the player.
///
/// Only picks are kept, not the versions that played by themselves, so an item no one picked a version of keeps
/// following the quality cap of the network it plays on. The picks stay in the app's own defaults on this device and
/// are never sent anywhere. The newest ``limit`` are kept, and they go when the account signs out or its server is
/// removed.
struct VersionMemory {
    /// How many picks are kept.
    static let limit = 200
    private static let prefix = "versionPicks."

    private let defaults: UserDefaults
    private let key: String?

    /// The picks of `account`, or none kept at all when no one is signed in, as in previews.
    init(account: SessionKey?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = account.map { "\(Self.prefix)\($0.serverID).\($0.userID)" }
    }

    /// The version last picked for `itemID`, or nil when none was.
    func version(of itemID: String) -> String? {
        picks.first { $0.itemID == itemID }?.versionID
    }

    /// Remembers `versionID` as picked for `itemID`, as the newest pick, in place of one picked for it before.
    func remember(_ versionID: String, for itemID: String) {
        guard let key, !itemID.isEmpty, !versionID.isEmpty else { return }
        let others = picks.filter { $0.itemID != itemID }
        let updated = [Pick(itemID: itemID, versionID: versionID)] + others.prefix(Self.limit - 1)
        defaults.set(updated.map { [$0.itemID, $0.versionID] }, forKey: key)
    }

    /// Forgets every pick.
    func clear() {
        guard let key else { return }
        defaults.removeObject(forKey: key)
    }

    /// Forgets the picks of `account`, when it signs out on this device.
    static func forget(_ account: SessionKey, in defaults: UserDefaults = .standard) {
        VersionMemory(account: account, defaults: defaults).clear()
    }

    /// Forgets the picks of every account on the server with `serverID`, when the server is removed.
    static func forget(server serverID: String, in defaults: UserDefaults = .standard) {
        let serverPrefix = "\(prefix)\(serverID)."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(serverPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    /// One pick: the item, and the version picked for it.
    private struct Pick {
        let itemID: String
        let versionID: String
    }

    /// The picks, newest first. Anything else stored under the key is passed over.
    private var picks: [Pick] {
        guard let key, let stored = defaults.array(forKey: key) else { return [] }
        return stored.compactMap { entry in
            guard let pair = entry as? [String], pair.count == 2 else { return nil }
            return Pick(itemID: pair[0], versionID: pair[1])
        }
    }
}
