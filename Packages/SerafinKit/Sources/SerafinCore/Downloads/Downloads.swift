import Foundation
import os

/// SerafinCore's front door for downloads: starts, tracks, retries and deletes them for each account, keeping
/// ``DownloadStore`` and ``DownloadTransfers`` in step, and keeps each one's pictures and where its playback stopped.
///
/// Each change to a download's playback made on this device, where it stopped or a mark as watched, is also kept for
/// the server until it's sent, and stays when the download is deleted; signing out forgets the account's.
///
/// ``Accounts`` owns the one instance. It hands each transfer the account's `Authorization` header, so the token
/// never appears in a URL. Resume data is kept in memory only, because it carries that header: a transfer that stops
/// carries on from where it stopped during this launch, and starts again after a relaunch.
public actor Downloads {
    /// What to download: an item's file as the server offers it.
    public struct Request: Sendable, Equatable {
        /// The item, a movie or an episode.
        public var itemID: String
        /// The server's ID for the version to save.
        public var mediaSourceID: String
        /// The file's address, without the token.
        public var url: URL
        /// The saved file's extension, such as `mp4`.
        public var fileExtension: String
        /// The file's size in bytes, when the server said.
        public var bytes: Int64?
        /// What the Downloads screen shows for it.
        public var metadata: DownloadMetadata
        /// The audio and subtitle tracks inside the file, for the player with no server to ask.
        public var tracks: DownloadTracks
        /// Where the server says playback last stopped, for resuming there with no server to ask, or nil when it
        /// hasn't been started.
        public var playback: DownloadPlayback?
        /// Whether the transfer may use cellular data.
        public var allowsCellularAccess: Bool

        /// Creates a request.
        public init(
            itemID: String,
            mediaSourceID: String,
            url: URL,
            fileExtension: String,
            bytes: Int64?,
            metadata: DownloadMetadata,
            tracks: DownloadTracks = DownloadTracks(),
            playback: DownloadPlayback? = nil,
            allowsCellularAccess: Bool
        ) {
            self.itemID = itemID
            self.mediaSourceID = mediaSourceID
            self.url = url
            self.fileExtension = fileExtension
            self.bytes = bytes
            self.metadata = metadata
            self.tracks = tracks
            self.playback = playback
            self.allowsCellularAccess = allowsCellularAccess
        }
    }

    /// How much of a running download has arrived.
    public struct Progress: Sendable, Equatable {
        /// Bytes so far.
        public var received: Int64
        /// Bytes in all, when known.
        public var expected: Int64?

        /// Creates progress.
        public init(received: Int64, expected: Int64?) {
            self.received = received
            self.expected = expected
        }

        /// The share that has arrived, from 0 to 1, or nil when the size isn't known.
        public var fraction: Double? {
            guard let expected, expected > 0 else { return nil }
            return min(1, Double(received) / Double(expected))
        }
    }

    /// The extensions a saved file may have: the containers Serafin's player opens.
    public static let playableExtensions: Set<String> = ["mp4", "m4v", "mov"]

    private static let logger = Logger(serafinCategory: "downloads")

    private let store: DownloadStore
    private let transfers: DownloadTransfers
    private let identity: DeviceIdentity
    private let sessions: SessionStore
    /// How the transfers that stopped this launch carry on, by file name.
    private var resumeData: [String: Data] = [:]
    /// How far each running download has got, by download ID.
    private var progressByID: [String: Progress] = [:]
    private var watchers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var activation: Task<Void, Never>?
    private var listening: Task<Void, Never>?

    /// Creates the downloads.
    ///
    /// - Parameters:
    ///   - store: Where downloads are kept.
    ///   - transfers: The session that moves the files.
    ///   - identity: Who this install is to the server, for the `Authorization` header.
    ///   - sessions: Where each account's token is kept.
    init(store: DownloadStore, transfers: DownloadTransfers, identity: DeviceIdentity, sessions: SessionStore) {
        self.store = store
        self.transfers = transfers
        self.identity = identity
        self.sessions = sessions
    }

    /// Checks the downloads left from the last launch, then starts reading what the transfers report, once.
    /// Downloads that were running when Serafin last stopped and have no transfer any more, as when it was closed from
    /// the app switcher, are marked interrupted. Starting a download waits for this, so a new download is never taken
    /// for one left over.
    func activate() async {
        if let activation {
            return await activation.value
        }
        let activation = Task { await self.markInterrupted() }
        self.activation = activation
        await activation.value
        let events = transfers.events
        listening = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
    }

    // MARK: - Reading

    /// The account's downloads, newest first.
    public func records(for key: SessionKey) async throws -> [DownloadRecord] {
        try await store.records().filter { $0.key == key }.sorted { $0.created > $1.created }
    }

    /// The account's download of `itemID`, if there is one.
    public func record(forItem itemID: String, key: SessionKey) async throws -> DownloadRecord? {
        try await store.records().first { $0.key == key && $0.itemID == itemID }
    }

    /// How far the running download with `id` has got.
    public func progress(of id: String) -> Progress? {
        progressByID[id]
    }

    /// The saved file of a finished download, or nil when it isn't finished or the file has gone.
    public nonisolated func fileURL(for record: DownloadRecord) -> URL? {
        guard record.state == .finished else { return nil }
        let url = store.fileURL(for: record)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// The picture of `kind` saved with `record`, or nil when none was.
    public nonisolated func artworkURL(_ kind: DownloadArtwork, for record: DownloadRecord) -> URL? {
        let url = store.artworkURL(kind, of: record.id)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    /// The bytes the account's finished downloads take up.
    public func usedBytes(for key: SessionKey) async throws -> Int64 {
        try await records(for: key).filter { $0.state == .finished }.reduce(0) { $0 + ($1.bytes ?? 0) }
    }

    /// A signal each time a download starts, moves on, finishes, fails or is deleted, for screens to read again.
    public func changes() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        watchers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.stopWatching(id) }
        }
        return stream
    }

    private func stopWatching(_ id: UUID) {
        watchers[id] = nil
    }

    private func notify() {
        for watcher in watchers.values {
            watcher.yield()
        }
    }

    // MARK: - Changing

    /// Downloads `request` for the account `key`. An item already downloaded or downloading for the account is left
    /// as it is; one that failed is tried again.
    ///
    /// - Throws: ``DownloadError/notEnoughSpace`` when the file wouldn't fit, ``DownloadError/storeUnavailable`` when
    ///   the list of downloads can't be saved, and ``SerafinError/notSignedIn`` when the account has no token.
    @discardableResult
    public func start(_ request: Request, for key: SessionKey) async throws -> DownloadRecord {
        await activate()
        if let existing = try await record(forItem: request.itemID, key: key) {
            if existing.state == .failed {
                try await retry(existing.id, from: request.url, allowsCellularAccess: request.allowsCellularAccess)
                return try await store.record(id: existing.id) ?? existing
            }
            return existing
        }
        guard Self.playableExtensions.contains(request.fileExtension) else { throw DownloadError.storeUnavailable }
        try checkSpace(for: request.bytes)
        let record = DownloadRecord(
            key: key,
            itemID: request.itemID,
            mediaSourceID: request.mediaSourceID,
            fileExtension: request.fileExtension,
            bytes: request.bytes,
            metadata: request.metadata,
            tracks: request.tracks,
            playback: request.playback
        )
        try await store.save(record)
        do {
            try await transfer(record, from: request.url, allowsCellularAccess: request.allowsCellularAccess)
        } catch {
            try? await store.remove(ids: [record.id])
            throw error
        }
        progressByID[record.id] = Progress(received: 0, expected: request.bytes)
        notify()
        return record
    }

    /// Tries a failed download again, carrying on from where it stopped when it stopped during this launch.
    ///
    /// - Parameters:
    ///   - id: The download.
    ///   - url: The file's address, as the server offers it now, used when the transfer starts again.
    ///   - allowsCellularAccess: Whether the transfer may use cellular data.
    public func retry(_ id: String, from url: URL, allowsCellularAccess: Bool) async throws {
        await activate()
        guard let record = try await store.record(id: id), record.state == .failed else { return }
        if let data = resumeData.removeValue(forKey: record.fileName) {
            transfers.resume(data, fileName: record.fileName)
        } else {
            try await transfer(record, from: url, allowsCellularAccess: allowsCellularAccess)
        }
        try await store.update(id: id) { record in
            record.state = .downloading
            record.failure = nil
        }
        progressByID[id] = Progress(received: 0, expected: record.bytes)
        notify()
    }

    // MARK: - Progress

    /// Keeps where playback of the download `id` stopped, so it resumes there with no server to ask, and keeps it for
    /// the server: where the item resumes and whether the stop counts as watching it, as Jellyfin records a stop with
    /// its standard settings. Does nothing when the download has been deleted.
    public func savePosition(_ position: Duration, of id: String) async throws {
        let saved = try await store.updatePlayback(id: id) { record in
            let stop = DownloadPlayback(position: position)
            let runtime = record.metadata.runtime
            let isPlayed = stop.isPlayed(runtime: runtime)
            record.playback = DownloadPlayback(position: position, changed: stop.changed, isPlayed: isPlayed)
            return PlaybackChange(
                key: record.key,
                itemID: record.itemID,
                position: stop.resumePosition(runtime: runtime),
                isPlayed: isPlayed,
                changed: stop.changed
            )
        }
        if saved != nil {
            notify()
        }
    }

    /// Marks the account `key`'s download of `itemID` watched or not, from the start either way, as when the server
    /// can't be reached, and keeps the mark for the server. Does nothing when the item isn't downloaded.
    public func setPlayed(_ isPlayed: Bool, ofItem itemID: String, key: SessionKey) async throws {
        guard let record = try await self.record(forItem: itemID, key: key) else { return }
        let saved = try await store.updatePlayback(id: record.id) { record in
            let mark = DownloadPlayback(position: .zero, isPlayed: isPlayed)
            record.playback = mark
            return PlaybackChange(
                key: record.key, itemID: record.itemID, position: .zero, isPlayed: isPlayed, changed: mark.changed)
        }
        if saved != nil {
            notify()
        }
    }

    /// The changes to the account `key`'s playback made with its downloads that the server hasn't heard yet, oldest
    /// first, whether or not the downloads are still here.
    public func playbackChanges(for key: SessionKey) async throws -> [PlaybackChange] {
        try await store.changes().filter { $0.key == key }
    }

    /// Forgets `change`, once the server has heard it or has a newer one. A change to the same item made since stays.
    public func removeChange(_ change: PlaybackChange) async throws {
        try await store.removeChange(change)
    }

    /// Keeps `playback`, as the server has it, with the account `key`'s download of `itemID`, so it resumes there with
    /// no server, or clears it for nil, which is an item the server says hasn't been started.
    ///
    /// - Parameter replacingChanges: Whether it replaces a change made on this device that the server hasn't heard
    ///   yet, as when the account has just changed the item on the server. Otherwise such a change, which is newer,
    ///   stays, and so does the download's playback.
    public func keepServerPlayback(
        _ playback: DownloadPlayback?,
        forItem itemID: String,
        key: SessionKey,
        replacingChanges: Bool = false
    ) async throws {
        let changed = try await store.setServerPlayback(
            playback, forItem: itemID, key: key, replacingChanges: replacingChanges)
        if changed {
            notify()
        }
    }

    // MARK: - Pictures and deleting

    /// Saves `data`, as the server sent it, as the picture of `kind` of the download `id`, so its card and detail
    /// screen show it with no server. Does nothing when the download has been deleted, or when `data` isn't a picture.
    public func saveArtwork(_ data: Data, _ kind: DownloadArtwork, of id: String) async throws {
        if try await store.saveArtwork(data, kind, of: id) {
            notify()
        }
    }

    /// Deletes a download, its file and its pictures, stopping its transfer if it's running.
    public func delete(_ id: String) async throws {
        guard let record = try await store.record(id: id) else { return }
        try await store.remove(ids: [id])
        await transfers.cancel(fileName: record.fileName)
        resumeData[record.fileName] = nil
        progressByID[id] = nil
        notify()
    }

    /// Deletes every download of the account `key`, and the changes to its playback the server hasn't heard yet, as
    /// when the user signs out.
    public func deleteAll(for key: SessionKey) async throws {
        try await store.removeChanges { $0.key == key }
        try await delete(try await store.records().filter { $0.key == key })
    }

    /// Deletes every download from the server `serverID`, and the changes to playback on it the server hasn't heard
    /// yet, as when the server is removed.
    public func deleteAll(forServer serverID: String) async throws {
        try await store.removeChanges { $0.serverID == serverID }
        try await delete(try await store.records().filter { $0.serverID == serverID })
    }

    private func delete(_ records: [DownloadRecord]) async throws {
        guard !records.isEmpty else { return }
        try await store.remove(ids: Set(records.map(\.id)))
        for record in records {
            await transfers.cancel(fileName: record.fileName)
            resumeData[record.fileName] = nil
            progressByID[record.id] = nil
        }
        notify()
    }

    // MARK: - Transfers

    private func transfer(_ record: DownloadRecord, from url: URL, allowsCellularAccess: Bool) async throws {
        guard let token = try await sessions.token(for: record.key) else { throw SerafinError.notSignedIn }
        var request = URLRequest(url: url)
        let authorization = try await identity.authorizationHeader(accessToken: token)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.allowsCellularAccess = allowsCellularAccess
        try store.prepareDirectories()
        transfers.start(request, fileName: record.fileName)
    }

    /// Throws when a file of `bytes` wouldn't leave room on the device for anything else.
    private func checkSpace(for bytes: Int64?) throws {
        guard let bytes else { return }
        let values = try? URL.applicationSupportDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey
        ])
        guard let available = values?.volumeAvailableCapacityForImportantUsage else { return }
        if bytes > available {
            throw DownloadError.notEnoughSpace
        }
    }

    private func markInterrupted() async {
        let running = await transfers.runningFileNames()
        do {
            for record in try await store.records() where record.state == .downloading {
                guard !running.contains(record.fileName) else { continue }
                try await store.update(id: record.id) { record in
                    guard record.state == .downloading else { return }
                    record.state = .failed
                    record.failure = .interrupted
                }
            }
            try await store.removeOrphanedFiles()
        } catch {
            Self.logger.error("Could not check the downloads: \(error.localizedDescription, privacy: .private)")
        }
        notify()
    }

    func handle(_ event: DownloadTransfers.Event) async {
        do {
            switch event {
            case .progress(let fileName, let received, let expected):
                guard let record = try await self.record(named: fileName) else { return }
                progressByID[record.id] = Progress(received: received, expected: expected ?? record.bytes)
            case .finished(let fileName, let bytes):
                let finished = try await update(named: fileName) { record in
                    record.state = .finished
                    record.failure = nil
                    record.bytes = bytes
                }
                guard let finished else {
                    // Deleted while it was on its way.
                    try await store.removeOrphanedFiles()
                    return
                }
                progressByID[finished.id] = nil
            case .failed(let fileName, let failure, let data):
                let failed = try await update(named: fileName) { record in
                    guard record.state != .finished else { return }
                    record.state = .failed
                    record.failure = failure
                }
                guard let failed, failed.state == .failed else { return }
                resumeData[fileName] = data
                progressByID[failed.id] = nil
            }
        } catch {
            Self.logger.error("Could not update a download: \(error.localizedDescription, privacy: .private)")
        }
        notify()
    }

    private func record(named fileName: String) async throws -> DownloadRecord? {
        try await store.records().first { $0.fileName == fileName }
    }

    /// Changes the download whose file is `fileName`, or does nothing when there's none, as when it was deleted.
    private func update(
        named fileName: String,
        _ change: @Sendable (inout DownloadRecord) -> Void
    ) async throws -> DownloadRecord? {
        guard let record = try await self.record(named: fileName) else { return nil }
        return try await store.update(id: record.id, change)
    }
}

/// Where ``Accounts`` keeps downloads and how their files travel.
public struct DownloadsSetup: Sendable {
    /// The folder for the index and the files.
    public var directory: URL
    /// Makes the transfers' session configuration.
    public var configuration: @Sendable () -> URLSessionConfiguration

    /// Creates a setup.
    public init(directory: URL, configuration: @escaping @Sendable () -> URLSessionConfiguration) {
        self.directory = directory
        self.configuration = configuration
    }

    /// The app's: `Serafin/Downloads` in Application Support, moved in the background session.
    public static var live: DownloadsSetup {
        DownloadsSetup(directory: DownloadStore.defaultDirectory) { DownloadTransfers.backgroundConfiguration() }
    }
}
