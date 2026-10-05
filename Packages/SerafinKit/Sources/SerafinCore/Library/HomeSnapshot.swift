import CryptoKit
import Foundation
import JellyfinAPI
import os

/// Home as the server sent it to one account: the libraries, Continue Watching, Next Up and the newest items in each
/// library.
public struct HomeSnapshot: Codable, Equatable, Sendable {
    /// When the server sent it.
    public var date: Date
    /// The user's movie and TV libraries, as ``LibraryRepository/userViews()`` returns them.
    public var libraries: [BaseItemDto]
    /// Started movies and episodes, as ``LibraryRepository/resume(limit:)`` returns them.
    public var resume: [BaseItemDto]
    /// The next episode of each show in progress, as ``LibraryRepository/nextUp(limit:series:)`` returns them.
    public var nextUp: [BaseItemDto]
    /// The newest items in each library, by the library's ID. A library whose newest items didn't load has none.
    public var latest: [String: [BaseItemDto]]

    /// Creates a snapshot.
    public init(
        date: Date,
        libraries: [BaseItemDto],
        resume: [BaseItemDto],
        nextUp: [BaseItemDto],
        latest: [String: [BaseItemDto]]
    ) {
        self.date = date
        self.libraries = libraries
        self.resume = resume
        self.nextUp = nextUp
        self.latest = latest
    }
}

/// Keeps the last Home each account was sent on this device, so Home can show it when the server can't be reached.
///
/// Each account's snapshot is one JSON file, named by a SHA-256 hash of the account, so the name says nothing about
/// the server or user and a server can't steer where the file goes. Files are written with complete file protection,
/// so they can't be read while the device is locked. They live in Caches, so they're never backed up and iOS may
/// delete them when space runs low, and Clear Cache in Settings deletes them.
///
/// The files are a cache, so their format can change from one release to the next: a file in another version, larger
/// than ``maximumFileSize`` or unreadable is deleted and ignored, and the next visit to Home saves a new one.
///
/// ```json
/// { "version": 1, "home": { "date": 781000000, "libraries": [ … ], "resume": [ … ], "nextUp": [ … ], "latest": { … } } }
/// ```
public actor HomeSnapshotStore {
    private struct File: Codable {
        var version: Int
        var home: HomeSnapshot
    }

    /// The version of the file format.
    static let currentVersion = 1
    /// The largest file read back. Home's rows hold a few hundred items at most, well under a megabyte.
    static let maximumFileSize = 8 * 1024 * 1024
    private static let logger = Logger(serafinCategory: "home-snapshots")

    private let directory: URL

    /// Creates a store.
    ///
    /// - Parameter directory: The folder the files go in. Defaults to ``defaultDirectory``.
    public init(directory: URL = HomeSnapshotStore.defaultDirectory) {
        self.directory = directory
    }

    /// The default folder, a folder of its own in Caches.
    public static var defaultDirectory: URL {
        URL.cachesDirectory.appending(path: "app.getserafin.serafin.home", directoryHint: .isDirectory)
    }

    /// The snapshot saved for `account`, or nil when there's none that can be used.
    func snapshot(for account: SessionKey) -> HomeSnapshot? {
        let url = fileURL(for: account)
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        if size <= Self.maximumFileSize {
            // A file that can't be read right now, as while the device is locked, stays for next time.
            guard let data = try? Data(contentsOf: url) else { return nil }
            if let file = try? JSONDecoder().decode(File.self, from: data), file.version == Self.currentVersion {
                return file.home
            }
        }
        Self.logger.error("Deleted a saved Home that couldn't be used")
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    /// Saves `snapshot` as `account`'s, in place of the one before. A failure is logged, not thrown, since Home works
    /// without it.
    func save(_ snapshot: HomeSnapshot, for account: SessionKey) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(File(version: Self.currentVersion, home: snapshot))
            try data.write(to: fileURL(for: account), options: [.atomic, .completeFileProtection])
        } catch {
            Self.logger.error("Could not save Home: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Deletes `account`'s snapshot, as when they sign out.
    func remove(for account: SessionKey) {
        try? FileManager.default.removeItem(at: fileURL(for: account))
    }

    /// Deletes every account's snapshot, for Clear Cache in Settings.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Where `account`'s snapshot goes: a file named by a hash of the account. The server ID's length leads, so no two
    /// accounts hash the same text.
    func fileURL(for account: SessionKey) -> URL {
        let identity = "\(account.serverID.utf8.count):\(account.serverID)\(account.userID)"
        let name = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appending(path: "\(name).json", directoryHint: .notDirectory)
    }
}

extension HomeSnapshotStore {
    /// One account's place in the store, handed to that account's ``LibraryRepository``.
    struct Slot: Sendable {
        let store: HomeSnapshotStore
        let account: SessionKey

        func load() async -> HomeSnapshot? {
            await store.snapshot(for: account)
        }

        func save(_ snapshot: HomeSnapshot) async {
            await store.save(snapshot, for: account)
        }
    }
}
