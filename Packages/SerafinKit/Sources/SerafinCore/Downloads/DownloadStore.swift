import Foundation
import os

/// The downloads on this device: an index saved as JSON and the files beside it, under Application Support.
///
/// Everything is excluded from backup, since a restored phone can download again, and protected until the device is
/// first unlocked after a restart, so a transfer that finishes while the phone is locked can still be saved. The
/// index holds no address, token or pin, and files are named by each download's ID. Its format is versioned so later
/// releases can migrate it:
///
/// ```json
/// {
///   "version": 1,
///   "downloads": [
///     { "id": "…", "serverID": "…", "userID": "…", "itemID": "…", "mediaSourceID": "…",
///       "fileExtension": "mp4", "state": "finished", "bytes": 1234, "created": …,
///       "metadata": { "title": "…", "kind": "movie" },
///       "tracks": { "audio": [{ "index": 1, "codec": "aac", "language": "eng", "isDefault": true, … }],
///                   "subtitles": [], "defaultAudio": 1 },
///       "playback": { "position": […], "changed": … } }
///   ]
/// }
/// ```
public actor DownloadStore {
    private struct File: Codable {
        var version: Int
        var downloads: [DownloadRecord]
    }

    private static let currentVersion = 1
    private static let logger = Logger(serafinCategory: "downloads")
    /// Protection for the index and the files: readable once the device has been unlocked after a restart.
    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    /// The folder that holds the index and the files.
    public nonisolated let directory: URL
    private var cached: [DownloadRecord]?

    /// Creates a store.
    ///
    /// - Parameter directory: Where downloads are kept. Defaults to `Serafin/Downloads` in Application Support.
    public init(directory: URL = DownloadStore.defaultDirectory) {
        self.directory = directory
    }

    /// The default folder for downloads.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Serafin/Downloads", directoryHint: .isDirectory)
    }

    /// The folder the files are saved in.
    public nonisolated var mediaDirectory: URL {
        directory.appending(path: "Media", directoryHint: .isDirectory)
    }

    private var indexURL: URL {
        directory.appending(path: "downloads.json", directoryHint: .notDirectory)
    }

    /// Where the file of the download named `fileName` is saved.
    public nonisolated func fileURL(named fileName: String) -> URL {
        mediaDirectory.appending(path: fileName, directoryHint: .notDirectory)
    }

    /// Where `record`'s file is saved, whether or not it's there yet.
    public nonisolated func fileURL(for record: DownloadRecord) -> URL {
        fileURL(named: record.fileName)
    }

    /// Every download, oldest first.
    public func records() throws -> [DownloadRecord] {
        if let cached { return cached }
        let loaded = try load()
        cached = loaded
        return loaded
    }

    /// The download with `id`, if there is one.
    public func record(id: String) throws -> DownloadRecord? {
        try records().first { $0.id == id }
    }

    /// Saves `record`, replacing a download with the same ID or adding it at the end.
    public func save(_ record: DownloadRecord) throws {
        var list = try records()
        if let index = list.firstIndex(where: { $0.id == record.id }) {
            list[index] = record
        } else {
            list.append(record)
        }
        try write(list)
    }

    /// Changes the download with `id` and saves it, or does nothing when there's no such download, as when it was
    /// deleted meanwhile, so a change never brings a deleted download back. Returns the download as it now is.
    @discardableResult
    public func update(id: String, _ change: @Sendable (inout DownloadRecord) -> Void) throws -> DownloadRecord? {
        var list = try records()
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        let unchanged = list[index]
        change(&list[index])
        if list[index] != unchanged {
            try write(list)
        }
        return list[index]
    }

    /// Removes the downloads with `ids` and deletes their files. IDs that aren't saved are ignored.
    public func remove(ids: Set<String>) throws {
        let list = try records()
        let removed = list.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        try write(list.filter { !ids.contains($0.id) })
        for record in removed {
            deleteFile(at: fileURL(for: record))
        }
    }

    /// Deletes files in the media folder that no download names, such as one that finished after its download was
    /// removed.
    public func removeOrphanedFiles() throws {
        let names = Set(try records().map(\.fileName))
        let files =
            (try? FileManager.default.contentsOfDirectory(at: mediaDirectory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !names.contains(file.lastPathComponent) {
            deleteFile(at: file)
        }
    }

    /// Makes the folders, excluded from backup and protected, if they aren't there yet.
    public nonisolated func prepareDirectories() throws {
        do {
            for folder in [directory, mediaDirectory] {
                try FileManager.default.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: Self.protection]
                )
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var folder = directory
            try folder.setResourceValues(values)
        } catch {
            Self.logger.error("Could not make the downloads folder: \(error.localizedDescription, privacy: .private)")
            throw DownloadError.storeUnavailable
        }
    }

    private func load() throws -> [DownloadRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path(percentEncoded: false)) else { return [] }
        do {
            return try JSONDecoder().decode(File.self, from: Data(contentsOf: indexURL)).downloads
        } catch {
            Self.logger.error("Could not read the downloads: \(error.localizedDescription, privacy: .private)")
            throw DownloadError.storeUnavailable
        }
    }

    private func write(_ list: [DownloadRecord]) throws {
        try prepareDirectories()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(File(version: Self.currentVersion, downloads: list))
            try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            cached = list
        } catch {
            Self.logger.error("Could not save the downloads: \(error.localizedDescription, privacy: .private)")
            throw DownloadError.storeUnavailable
        }
    }

    private func deleteFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("Could not delete a download: \(error.localizedDescription, privacy: .private)")
        }
    }
}
