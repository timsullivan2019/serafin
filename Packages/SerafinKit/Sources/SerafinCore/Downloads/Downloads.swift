import Foundation
import os

/// SerafinCore's front door for downloads: starts, tracks, retries and deletes them for each account, keeping
/// ``DownloadStore`` and ``DownloadTransfers`` in step, and keeps each one's pictures and where its playback stopped.
///
/// Each change to a download's playback made on this device, where it stopped or a mark as watched, is also kept for
/// the server until it's sent, and stays when the download is deleted; signing out forgets the account's.
///
/// A download that isn't saved as it arrives, as when the server converts the video for the player while it's sent,
/// is prepared once its file arrives: a ``DownloadPreparing`` writes the copy the player opens, with the subtitles
/// saved beside it, one download at a time, for as long as iOS lets Serafin run in the background, and carries on
/// when Serafin is next active.
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
        /// The extension of the file the server sends, such as `mp4`.
        public var fileExtension: String
        /// The file's size in bytes, when the server said, or an estimate of it for a file the server converts.
        public var bytes: Int64?
        /// What the Downloads screen shows for it.
        public var metadata: DownloadMetadata
        /// The audio and subtitle tracks inside the file, for the player with no server to ask.
        public var tracks: DownloadTracks
        /// Where the server says playback last stopped, for resuming there with no server to ask, or nil when it
        /// hasn't been started.
        public var playback: DownloadPlayback?
        /// How the saved copy is written once the file arrives, or nil to save the file as it arrives.
        public var preparation: Preparation?
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
            preparation: Preparation? = nil,
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
            self.preparation = preparation
            self.allowsCellularAccess = allowsCellularAccess
        }
    }

    /// How a download's saved copy is written once its file arrives: the file is copied into a QuickTime movie, with
    /// subtitles added after those inside it.
    public struct Preparation: Sendable, Equatable {
        /// The subtitles to add, in order.
        public var subtitles: [Subtitles]
        /// The Dolby Vision the copy signals, for Dolby Vision video the server copies into a file that doesn't say
        /// so, or nil.
        public var dolbyVision: DolbyVisionConfiguration?

        /// Creates a preparation.
        public init(subtitles: [Subtitles] = [], dolbyVision: DolbyVisionConfiguration? = nil) {
            self.subtitles = subtitles
            self.dolbyVision = dolbyVision
        }
    }

    /// Subtitles to add to a download's copy.
    public struct Subtitles: Sendable, Equatable {
        /// The server's index for the stream, which is among the request's ``Request/tracks``.
        public var index: Int
        /// The subtitles as a WebVTT file, as the server sent it.
        public var webVTT: Data

        /// Creates subtitles.
        public init(index: Int, webVTT: Data) {
            self.index = index
            self.webVTT = webVTT
        }
    }

    /// How much of a running download has arrived.
    public struct Progress: Sendable, Equatable {
        /// Bytes so far.
        public var received: Int64
        /// Bytes in all, when known.
        public var expected: Int64?
        /// Whether ``expected`` is an estimate made before the transfer, since the server didn't say, as when it
        /// converts the file while it sends it.
        public var isEstimate: Bool

        /// Creates progress.
        public init(received: Int64, expected: Int64?, isEstimate: Bool = false) {
            self.received = received
            self.expected = expected
            self.isEstimate = isEstimate
        }

        /// The share that has arrived, from 0 to 1, or nil when the size isn't known. Short of 1 while it's measured
        /// against an estimate, which the file can outgrow.
        public var fraction: Double? {
            guard let expected, expected > 0 else { return nil }
            return min(isEstimate ? 0.99 : 1, Double(received) / Double(expected))
        }
    }

    /// The extensions a saved file may have: the containers Serafin's player opens.
    public static let playableExtensions: Set<String> = ["mp4", "m4v", "mov"]

    private static let logger = Logger(serafinCategory: "downloads")

    private let store: DownloadStore
    private let transfers: DownloadTransfers
    private let identity: DeviceIdentity
    private let sessions: SessionStore
    private let preparer: (any DownloadPreparing)?
    /// How the transfers that stopped this launch carry on, by file name.
    private var resumeData: [String: Data] = [:]
    /// How far each running download has got, by download ID.
    private var progressByID: [String: Progress] = [:]
    private var watchers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var activation: Task<Void, Never>?
    private var listening: Task<Void, Never>?
    /// The task writing the copies of downloads whose files have arrived, while it runs.
    private var preparing: Task<Void, Never>?
    /// Whether a download's file has arrived since the copies being written were looked for.
    private var needsPreparing = false
    /// The download whose copy is being written, and the task writing it, so deleting the download stops it.
    private var writing: (id: String, task: Task<Void, any Error>)?

    /// Creates the downloads.
    ///
    /// - Parameters:
    ///   - store: Where downloads are kept.
    ///   - transfers: The session that moves the files.
    ///   - identity: Who this install is to the server, for the `Authorization` header.
    ///   - sessions: Where each account's token is kept.
    ///   - preparer: Writes the copies of downloads that aren't saved as they arrive, or nil to take none.
    init(
        store: DownloadStore,
        transfers: DownloadTransfers,
        identity: DeviceIdentity,
        sessions: SessionStore,
        preparer: (any DownloadPreparing)? = nil
    ) {
        self.store = store
        self.transfers = transfers
        self.identity = identity
        self.sessions = sessions
        self.preparer = preparer
    }

    /// Checks the downloads left from the last launch, then starts reading what the transfers report, once.
    /// Downloads that were running when Serafin last stopped and have no transfer any more, as when it was closed from
    /// the app switcher, are marked interrupted, and the copies left to write are written. Starting a download waits
    /// for this, so a new download is never taken for one left over.
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
        startPreparing()
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
    /// as it is; one that failed is tried again, afresh when its copy is written on the device, since the server
    /// converts its file anew.
    ///
    /// - Throws: ``DownloadError/notEnoughSpace`` when the file wouldn't fit, ``DownloadError/storeUnavailable`` when
    ///   the list of downloads can't be saved, and ``SerafinError/notSignedIn`` when the account has no token.
    @discardableResult
    public func start(_ request: Request, for key: SessionKey) async throws -> DownloadRecord {
        await activate()
        if let existing = try await record(forItem: request.itemID, key: key) {
            guard existing.state == .failed else { return existing }
            guard existing.preparation != nil || request.preparation != nil else {
                try await retry(existing.id, from: request.url, allowsCellularAccess: request.allowsCellularAccess)
                return try await store.record(id: existing.id) ?? existing
            }
            try await delete(existing.id)
        }
        guard Self.playableExtensions.contains(request.fileExtension),
            request.preparation == nil || preparer != nil
        else { throw DownloadError.storeUnavailable }
        // A copy needs room for the file that arrives and the copy written from it, until the first is deleted.
        try checkSpace(for: request.bytes.map { request.preparation == nil ? $0 : Self.twice($0) })
        let preparation = request.preparation.map { preparation in
            DownloadPreparation(
                arrivingExtension: request.fileExtension,
                subtitles: preparation.subtitles.map(\.index),
                dolbyVision: preparation.dolbyVision
            )
        }
        let record = DownloadRecord(
            key: key,
            itemID: request.itemID,
            mediaSourceID: request.mediaSourceID,
            fileExtension: preparation == nil ? request.fileExtension : "mov",
            bytes: request.bytes,
            metadata: request.metadata,
            tracks: request.tracks,
            playback: request.playback,
            preparation: preparation
        )
        try await store.save(record)
        do {
            try saveSubtitles(request.preparation?.subtitles ?? [], of: record)
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
    private func retry(_ id: String, from url: URL, allowsCellularAccess: Bool) async throws {
        guard let record = try await store.record(id: id), record.state == .failed else { return }
        if let data = resumeData.removeValue(forKey: record.transferName) {
            transfers.resume(data, fileName: record.transferName)
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

    /// Deletes a download, its file and its pictures, stopping its transfer, or the writing of its copy, if it's
    /// running.
    public func delete(_ id: String) async throws {
        guard let record = try await store.record(id: id) else { return }
        stopWriting([id])
        try await store.remove(ids: [id])
        await transfers.cancel(fileName: record.transferName)
        resumeData[record.transferName] = nil
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
        let ids = Set(records.map(\.id))
        stopWriting(ids)
        try await store.remove(ids: ids)
        for record in records {
            await transfers.cancel(fileName: record.transferName)
            resumeData[record.transferName] = nil
            progressByID[record.id] = nil
        }
        notify()
    }

    /// Stops writing the copy of the download it's being written for, when that's one of `ids`.
    private func stopWriting(_ ids: Set<String>) {
        guard let writing, ids.contains(writing.id) else { return }
        writing.task.cancel()
    }

    // MARK: - Preparing

    /// Writes the copies of the downloads whose files have arrived and still wait for one, as when Serafin ran out of
    /// time in the background before it could, unless that's under way.
    public func prepareArrived() async {
        await activate()
        startPreparing()
    }

    /// Starts writing the copies waiting to be written, one at a time, unless that's under way, in which case it
    /// looks for them again once it's done.
    private func startPreparing() {
        guard let preparer else { return }
        needsPreparing = true
        guard preparing == nil else { return }
        preparing = Task {
            await Self.keepingAwake {
                await self.prepareWhileNeeded(with: preparer)
            }
        }
    }

    private func prepareWhileNeeded(with preparer: any DownloadPreparing) async {
        while needsPreparing, !Task.isCancelled {
            needsPreparing = false
            await prepareEach(with: preparer)
        }
        preparing = nil
    }

    /// Writes the copy of each download waiting for one, oldest first, until none is left or the task is cancelled.
    private func prepareEach(with preparer: any DownloadPreparing) async {
        var tried: Set<String> = []
        while !Task.isCancelled {
            guard let records = try? await store.records(),
                let record = records.first(where: { $0.state == .preparing && !tried.contains($0.id) })
            else { return }
            tried.insert(record.id)
            await prepare(record, with: preparer)
        }
    }

    /// Writes `record`'s copy and saves it, which finishes the download, or fails it when the copy can't be written.
    /// When the task is cancelled, as when iOS won't let Serafin run any longer, it stays waiting, to be written again.
    private func prepare(_ record: DownloadRecord, with preparer: any DownloadPreparing) async {
        guard let preparation = record.preparation else { return }
        let subtitles = preparation.subtitles.compactMap { index -> AddedSubtitles? in
            guard let track = record.tracks?.subtitles.first(where: { $0.index == index }) else { return nil }
            return AddedSubtitles(track: track, file: store.subtitlesURL(index, of: record))
        }
        let saving = store.savingURL(for: record)
        let job = DownloadPreparationJob(
            arrived: store.arrivedURL(for: record),
            subtitles: subtitles,
            output: saving,
            dolbyVision: preparation.dolbyVision
        )
        let task = Task { try await preparer.prepare(job) }
        writing = (record.id, task)
        defer { writing = nil }
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
        } catch is CancellationError {
            store.deleteFile(at: saving)
            return
        } catch {
            let failure: DownloadFailure =
                error as? DownloadPreparationError == .storageFull ? .storageFull : .preparationFailed
            await failPreparing(record, failure)
            return
        }
        await finishPreparing(record)
    }

    /// Saves `record`'s copy, once it's written, as its file, and finishes the download.
    private func finishPreparing(_ record: DownloadRecord) async {
        do {
            let saved = store.fileURL(for: record)
            store.deleteFile(at: saved)
            try FileManager.default.moveItem(at: store.savingURL(for: record), to: saved)
            let size = try? saved.resourceValues(forKeys: [.fileSizeKey]).fileSize
            let finished = try await store.update(id: record.id) { record in
                guard record.state == .preparing else { return }
                record.state = .finished
                record.failure = nil
                record.preparation = nil
                record.bytes = size.map(Int64.init) ?? record.bytes
            }
            if finished?.state == .finished {
                // The file that arrived and the subtitles are in the copy now.
                store.removePreparationFiles(of: record)
            } else {
                // Deleted while its copy was written.
                try await store.removeOrphanedFiles()
            }
        } catch {
            Self.logger.error("Could not save a download's copy: \(error.localizedDescription, privacy: .private)")
            await failPreparing(record, .preparationFailed)
            return
        }
        notify()
    }

    /// Fails `record`, whose copy couldn't be written, and deletes what was kept for it, which trying again brings
    /// afresh.
    private func failPreparing(_ record: DownloadRecord, _ failure: DownloadFailure) async {
        do {
            try await store.update(id: record.id) { record in
                guard record.state == .preparing else { return }
                record.state = .failed
                record.failure = failure
            }
        } catch {
            Self.logger.error("Could not update a download: \(error.localizedDescription, privacy: .private)")
        }
        store.removePreparationFiles(of: record)
        notify()
    }

    /// Runs `operation`, asking iOS to keep Serafin running until it ends, as when it's in the background, and
    /// cancelling it once iOS won't any longer.
    private static func keepingAwake(_ operation: @escaping @Sendable () async -> Void) async {
        let task = Task { await operation() }
        #if canImport(UIKit)
            let ended = DispatchSemaphore(value: 0)
            ProcessInfo.processInfo.performExpiringActivity(withReason: "Saving downloads") { expired in
                if expired {
                    task.cancel()
                } else {
                    // Serafin keeps running while this waits.
                    Task {
                        await task.value
                        ended.signal()
                    }
                    ended.wait()
                }
            }
        #endif
        await task.value
    }

    // MARK: - Transfers

    private func transfer(_ record: DownloadRecord, from url: URL, allowsCellularAccess: Bool) async throws {
        guard let token = try await sessions.token(for: record.key) else { throw SerafinError.notSignedIn }
        var request = URLRequest(url: url)
        let authorization = try await identity.authorizationHeader(accessToken: token)
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.allowsCellularAccess = allowsCellularAccess
        try store.prepareDirectories()
        transfers.start(request, fileName: record.transferName)
    }

    /// Saves the WebVTT files of `subtitles` beside `record`'s file, until they're in its copy.
    private func saveSubtitles(_ subtitles: [Subtitles], of record: DownloadRecord) throws {
        guard !subtitles.isEmpty else { return }
        try store.prepareDirectories()
        for file in subtitles {
            do {
                try file.webVTT.write(
                    to: store.subtitlesURL(file.index, of: record),
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            } catch {
                Self.logger.error(
                    "Could not save a download's subtitles: \(error.localizedDescription, privacy: .private)")
                throw DownloadError.storeUnavailable
            }
        }
    }

    /// Twice `bytes`, or the most there can be when that's more.
    private static func twice(_ bytes: Int64) -> Int64 {
        let (doubled, overflow) = bytes.multipliedReportingOverflow(by: 2)
        return overflow ? .max : doubled
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
                guard !running.contains(record.transferName) else { continue }
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
                progressByID[record.id] = Progress(
                    received: received, expected: expected ?? record.bytes, isEstimate: expected == nil)
            case .finished(let fileName, let bytes):
                let finished = try await update(named: fileName) { record in
                    // A copy is written from the file before the download is finished.
                    record.state = record.preparation == nil ? .finished : .preparing
                    record.failure = nil
                    record.bytes = bytes
                }
                guard let finished else {
                    // Deleted while it was on its way.
                    try await store.removeOrphanedFiles()
                    return
                }
                progressByID[finished.id] = nil
                if finished.state == .preparing {
                    startPreparing()
                }
            case .failed(let fileName, let failure, let data):
                let failed = try await update(named: fileName) { record in
                    guard record.state == .downloading || record.state == .failed else { return }
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

    /// The download whose transfer brings the file `fileName`.
    private func record(named fileName: String) async throws -> DownloadRecord? {
        try await store.records().first { $0.transferName == fileName }
    }

    /// Changes the download whose transfer brings the file `fileName`, or does nothing when there's none, as when it
    /// was deleted.
    private func update(
        named fileName: String,
        _ change: @Sendable (inout DownloadRecord) -> Void
    ) async throws -> DownloadRecord? {
        guard let record = try await self.record(named: fileName) else { return nil }
        return try await store.update(id: record.id, change)
    }
}

/// Where ``Accounts`` keeps downloads, how their files travel, and what writes the copies of those that aren't saved
/// as they arrive.
public struct DownloadsSetup: Sendable {
    /// The folder for the index and the files.
    public var directory: URL
    /// Makes the transfers' session configuration.
    public var configuration: @Sendable () -> URLSessionConfiguration
    /// Writes the copies of downloads that aren't saved as they arrive, or nil to take none.
    public var preparer: (any DownloadPreparing)?

    /// Creates a setup.
    public init(
        directory: URL,
        preparer: (any DownloadPreparing)? = nil,
        configuration: @escaping @Sendable () -> URLSessionConfiguration
    ) {
        self.directory = directory
        self.preparer = preparer
        self.configuration = configuration
    }

    /// The app's: `Serafin/Downloads` in Application Support, moved in the background session, with `preparer`
    /// writing the copies of downloads that aren't saved as they arrive.
    public static func live(preparer: any DownloadPreparing) -> DownloadsSetup {
        DownloadsSetup(directory: DownloadStore.defaultDirectory, preparer: preparer) {
            DownloadTransfers.backgroundConfiguration()
        }
    }
}
