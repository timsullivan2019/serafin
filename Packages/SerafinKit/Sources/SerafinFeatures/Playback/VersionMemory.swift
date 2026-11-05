import Foundation
import SerafinCore

/// The version last picked for each movie and episode on this device, and when, kept for each account, so Play starts
/// the version picked for it on its page or in the player.
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

    /// The newest pick of one of `versionIDs` for one of `itemIDs`, or nil when there's none. On Jellyfin 12.0 and later
    /// each version of a movie can have its own page, as when Continue Watching shows the version being watched, so a
    /// pick made on one version's page counts on the others'.
    func latestPick(for itemIDs: Set<String>, among versionIDs: Set<String>) -> Pick? {
        picks.first { itemIDs.contains($0.itemID) && versionIDs.contains($0.versionID) }
    }

    /// Remembers `versionID` as picked for `itemID` at `date`, as the newest pick, in place of one picked for it
    /// before.
    func remember(_ versionID: String, for itemID: String, at date: Date = .now) {
        guard let key, !itemID.isEmpty, !versionID.isEmpty else { return }
        let others = picks.filter { $0.itemID != itemID }
        let updated = [Pick(itemID: itemID, versionID: versionID, date: date)] + others.prefix(Self.limit - 1)
        defaults.set(
            updated.map { [$0.itemID, $0.versionID, String($0.date.timeIntervalSince1970)] }, forKey: key)
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

    /// One pick: the item, the version picked for it, and when.
    struct Pick: Equatable {
        let itemID: String
        let versionID: String
        /// When it was picked, or the distant past for a pick kept without its time.
        let date: Date
    }

    /// The picks, newest first. Anything else stored under the key is passed over.
    private var picks: [Pick] {
        guard let key, let stored = defaults.array(forKey: key) else { return [] }
        return stored.compactMap { entry in
            guard let fields = entry as? [String], fields.count == 2 || fields.count == 3 else { return nil }
            let seconds = fields.count == 3 ? Double(fields[2]).flatMap { $0.isFinite ? $0 : nil } : nil
            return Pick(
                itemID: fields[0], versionID: fields[1],
                date: seconds.map(Date.init(timeIntervalSince1970:)) ?? .distantPast)
        }
    }
}
