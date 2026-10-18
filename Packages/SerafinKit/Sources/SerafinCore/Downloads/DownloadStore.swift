import Foundation
import ImageIO
import os

/// The downloads on this device: an index saved as JSON and the files beside it, under Application Support.
///
/// Everything is excluded from backup, since a restored phone can download again, and protected until the device is
/// first unlocked after a restart, so a transfer that finishes while the phone is locked can still be saved. The
/// index holds no address, token or pin, and files are named by each download's ID: the video in `Media`, and its
/// poster and backdrop in `Artwork`. A download whose copy Serafin writes keeps the file that arrived and its
/// subtitles in `Media` too until the copy is saved. The index also keeps the changes to playback made with downloads
/// that the server hasn't heard yet, which stay when their download is deleted. Its format is versioned so later
/// releases can migrate it:
///
/// ```json
/// {
///   "version": 1,
///   "downloads": [
///     { "id": "…", "serverID": "…", "userID": "…", "itemID": "…", "mediaSourceID": "…",
///       "fileExtension": "mp4", "state": "finished", "bytes": 1234, "created": …,
///       "metadata": { "title": "…", "kind": "movie", "year": 2010, "overview": "…" },
///       "tracks": { "audio": [{ "index": 1, "codec": "aac", "language": "eng", "isDefault": true, … }],
///                   "subtitles": [], "defaultAudio": 1 },
///       "playback": { "position": […], "changed": …, "isPlayed": false },
///       "preparation": { "arrivingExtension": "mp4", "subtitles": [3] } }
///   ],
///   "changes": [
///     { "serverID": "…", "userID": "…", "itemID": "…", "position": […], "isPlayed": false, "changed": … }
///   ]
/// }
/// ```
public actor DownloadStore {
    private struct File: Codable {
        var version: Int
        var downloads: [DownloadRecord]
        /// The changes to playback the server hasn't heard yet, oldest first. Left out when there are none, and of an
        /// index saved before they were kept.
        var changes: [PlaybackChange]?
    }

    /// What the index holds, as it's read and saved.
    private struct Contents {
        var downloads: [DownloadRecord] = []
        var changes: [PlaybackChange] = []
    }

    private static let currentVersion = 1
    private static let logger = Logger(serafinCategory: "downloads")
    /// Protection for the index and the files: readable once the device has been unlocked after a restart.
    static let protection = FileProtectionType.completeUntilFirstUserAuthentication

    /// The folder that holds the index and the files.
    public nonisolated let directory: URL
    private var cached: Contents?

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

    /// The folder the downloads' posters and backdrops are saved in.
    public nonisolated var artworkDirectory: URL {
        directory.appending(path: "Artwork", directoryHint: .isDirectory)
    }

    /// The largest picture saved with a download: the most the image pipeline takes from the server for any picture.
    static let maximumArtworkSize = 20 * 1024 * 1024

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

    /// Where the file `record`'s transfer brings is put: its saved file's place, or until a copy is written from it,
    /// a place of its own.
    nonisolated func arrivedURL(for record: DownloadRecord) -> URL {
        fileURL(named: record.transferName)
    }

    /// Where the WebVTT file of `record`'s subtitles with the server's stream `index` is kept until they're in the
    /// copy.
    nonisolated func subtitlesURL(_ index: Int, of record: DownloadRecord) -> URL {
        fileURL(named: record.subtitlesName(index))
    }

    /// Where `record`'s copy is written, until it's whole.
    nonisolated func savingURL(for record: DownloadRecord) -> URL {
        fileURL(named: record.savingName)
    }

    /// Where the download `id`'s picture of `kind` is saved, whether or not it's there yet. Like the file, it's named
    /// by the download's ID alone.
    public nonisolated func artworkURL(_ kind: DownloadArtwork, of id: String) -> URL {
        artworkDirectory.appending(path: "\(id)-\(kind.rawValue)", directoryHint: .notDirectory)
    }

    /// Every download, oldest first.
    public func records() throws -> [DownloadRecord] {
        try currentContents().downloads
    }

    /// The changes to playback made with downloads that the server hasn't heard yet, oldest first.
    public func changes() throws -> [PlaybackChange] {
        try currentContents().changes
    }

    /// The download with `id`, if there is one.
    public func record(id: String) throws -> DownloadRecord? {
        try records().first { $0.id == id }
    }

    /// Saves `record`, replacing a download with the same ID or adding it at the end.
    public func save(_ record: DownloadRecord) throws {
        var contents = try currentContents()
        if let index = contents.downloads.firstIndex(where: { $0.id == record.id }) {
            contents.downloads[index] = record
        } else {
            contents.downloads.append(record)
        }
        try write(contents)
    }

    /// Changes the download with `id` and saves it, or does nothing when there's no such download, as when it was
    /// deleted meanwhile, so a change never brings a deleted download back. Returns the download as it now is.
    @discardableResult
    public func update(id: String, _ change: @Sendable (inout DownloadRecord) -> Void) throws -> DownloadRecord? {
        var contents = try currentContents()
        guard let index = contents.downloads.firstIndex(where: { $0.id == id }) else { return nil }
        let unchanged = contents.downloads[index]
        change(&contents.downloads[index])
        if contents.downloads[index] != unchanged {
            try write(contents)
        }
        return contents.downloads[index]
    }

    /// Changes the download with `id`'s playback with `change`, and keeps the change to playback it returns for the
    /// server, in place of an earlier one to the same item that hasn't been sent, all in one save. Does nothing when
    /// there's no such download. Returns the download as it now is.
    @discardableResult
    public func updatePlayback(
        id: String,
        _ change: @Sendable (inout DownloadRecord) -> PlaybackChange
    ) throws -> DownloadRecord? {
        var contents = try currentContents()
        guard let index = contents.downloads.firstIndex(where: { $0.id == id }) else { return nil }
        let queued = change(&contents.downloads[index])
        contents.changes.removeAll { $0.isFor(queued.itemID, key: queued.key) }
        contents.changes.append(queued)
        try write(contents)
        return contents.downloads[index]
    }

    /// Forgets `change`, once the server has heard it or has a newer one. A change to the same item made since stays.
    public func removeChange(_ change: PlaybackChange) throws {
        var contents = try currentContents()
        guard let index = contents.changes.firstIndex(of: change) else { return }
        contents.changes.remove(at: index)
        try write(contents)
    }

    /// Forgets the changes `isRemoved` picks, as an account's when it signs out.
    public func removeChanges(where isRemoved: @Sendable (PlaybackChange) -> Bool) throws {
        var contents = try currentContents()
        let count = contents.changes.count
        contents.changes.removeAll(where: isRemoved)
        guard contents.changes.count != count else { return }
        try write(contents)
    }

    /// Keeps `playback`, as the server has it, with the account `key`'s download of `itemID`, or clears it for nil.
    /// While a change to the item waits for the server, which is newer, nothing changes, unless `replacingChanges`,
    /// for what the server has after a change made there, which is newer still: then the waiting change is forgotten.
    /// Returns whether the download changed.
    @discardableResult
    public func setServerPlayback(
        _ playback: DownloadPlayback?,
        forItem itemID: String,
        key: SessionKey,
        replacingChanges: Bool
    ) throws -> Bool {
        var contents = try currentContents()
        let waiting = contents.changes.contains { $0.isFor(itemID, key: key) }
        if waiting {
            guard replacingChanges else { return false }
            contents.changes.removeAll { $0.isFor(itemID, key: key) }
        }
        let index = contents.downloads.firstIndex { $0.key == key && $0.itemID == itemID }
        let changesDownload = index.map { contents.downloads[$0].playback != playback } ?? false
        if let index, changesDownload {
            contents.downloads[index].playback = playback
        }
        if waiting || changesDownload {
            try write(contents)
        }
        return changesDownload
    }

    /// Saves `data` as the download `id`'s picture of `kind`, in place of one saved before, and returns whether it did.
    /// Nothing is saved when there's no such download, as when it was deleted meanwhile, or when `data` isn't an image
    /// or is larger than ``maximumArtworkSize``.
    @discardableResult
    public func saveArtwork(_ data: Data, _ kind: DownloadArtwork, of id: String) throws -> Bool {
        guard try records().contains(where: { $0.id == id }) else { return false }
        guard data.count <= Self.maximumArtworkSize, Self.isImage(data) else {
            Self.logger.error("Did not save a download's picture the server sent, since it isn't one")
            return false
        }
        try prepareDirectories()
        do {
            try data.write(
                to: artworkURL(kind, of: id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.logger.error("Could not save a download's picture: \(error.localizedDescription, privacy: .private)")
            throw DownloadError.storeUnavailable
        }
        return true
    }

    /// Removes the downloads with `ids` and deletes their files and pictures. IDs that aren't saved are ignored. The
    /// changes to their playback that the server hasn't heard yet stay.
    public func remove(ids: Set<String>) throws {
        var contents = try currentContents()
        let removed = contents.downloads.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        contents.downloads.removeAll { ids.contains($0.id) }
        try write(contents)
        for record in removed {
            for name in record.fileNames {
                deleteFile(at: fileURL(named: name))
            }
            for kind in DownloadArtwork.allCases {
                deleteFile(at: artworkURL(kind, of: record.id))
            }
        }
    }

    /// Deletes files and pictures that no download names, such as a file that finished after its download was removed.
    public func removeOrphanedFiles() throws {
        let list = try records()
        let names = list.reduce(into: Set<String>()) { $0.formUnion($1.fileNames) }
        let pictures = Set(
            list.flatMap { record in DownloadArtwork.allCases.map { artworkURL($0, of: record.id).lastPathComponent } })
        for (folder, kept) in [(mediaDirectory, names), (artworkDirectory, pictures)] {
            let files =
                (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for file in files where !kept.contains(file.lastPathComponent) {
                deleteFile(at: file)
            }
        }
    }

    /// Makes the folders, excluded from backup and protected, if they aren't there yet.
    public nonisolated func prepareDirectories() throws {
        do {
            for folder in [directory, mediaDirectory, artworkDirectory] {
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

    /// What the index holds, read once and then kept.
    private func currentContents() throws -> Contents {
        if let cached { return cached }
        let loaded = try load()
        cached = loaded
        return loaded
    }

    private func load() throws -> Contents {
        guard FileManager.default.fileExists(atPath: indexURL.path(percentEncoded: false)) else { return Contents() }
        do {
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: indexURL))
            return Contents(downloads: file.downloads, changes: file.changes ?? [])
        } catch {
            Self.logger.error("Could not read the downloads: \(error.localizedDescription, privacy: .private)")
            throw DownloadError.storeUnavailable
        }
    }

    private func write(_ contents: Contents) throws {
        try prepareDirectories()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let file = File(
                version: Self.currentVersion,
                downloads: contents.downloads,
                changes: contents.changes.isEmpty ? nil : contents.changes
            )
            let data = try encoder.encode(file)
            try data.write(to: indexURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            cached = contents
        } catch {
            Self.logger.error("Could not save the downloads: \(error.localizedDescription, privacy: .private)")
            throw DownloadError.storeUnavailable
        }
    }

    /// Whether `data` is a picture ImageIO can read, rather than something else a server sent, such as an error page.
    static func isImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetType(source) != nil && CGImageSourceGetCount(source) > 0
    }

    /// Deletes what `record` kept while its copy was written: the file that arrived, its subtitles, and the copy as
    /// far as it got.
    nonisolated func removePreparationFiles(of record: DownloadRecord) {
        for name in record.fileNames where name != record.fileName {
            deleteFile(at: fileURL(named: name))
        }
    }

    /// Deletes the file at `url`, if there is one.
    nonisolated func deleteFile(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("Could not delete a download: \(error.localizedDescription, privacy: .private)")
        }
    }
}
