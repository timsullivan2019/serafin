import Foundation
import Testing

@testable import SerafinCore

/// A one-pixel PNG, as a server sends a picture.
private let png = Data(base64Encoded: onePixel) ?? Data()
private let onePixel =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="

/// Whether a file is saved at `url`.
private func isSaved(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
}

@Suite struct DownloadStoreTests {
    private let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
    private let key = SessionKey(serverID: "server-1", userID: "user-1")

    private func record(_ itemID: String, state: DownloadRecord.State = .finished) -> DownloadRecord {
        DownloadRecord(
            key: key,
            itemID: itemID,
            mediaSourceID: itemID,
            fileExtension: "mp4",
            state: state,
            metadata: DownloadMetadata(title: "Sintel", kind: .movie, runtime: .seconds(888), year: 2010)
        )
    }

    /// A change to `record`'s playback, stopped at `position`, for the server.
    private func change(of record: DownloadRecord, at position: Duration) -> PlaybackChange {
        PlaybackChange(key: key, itemID: record.itemID, position: position, isPlayed: false, changed: .now)
    }

    @Test func savedDownloadsSurviveARelaunch() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)
        let reloaded = try await DownloadStore(directory: directory).records()
        #expect(reloaded == [saved])
        #expect(reloaded.first?.metadata.runtime == .seconds(888))
    }

    @Test func theIndexIsVersionedAndNamesNoServerOrToken() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)
        let json = try String(contentsOf: directory.appending(path: "downloads.json"), encoding: .utf8)
        #expect(json.contains(#""version" : 1"#))
        #expect(!json.lowercased().contains("token"))
        #expect(!json.contains("http"))
        #expect(!json.contains(#""changes""#))
        #expect(saved.fileName == "\(saved.id).mp4")
    }

    @Test func aChangeForTheServerNamesOnlyTheAccountAndTheItem() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)
        let waiting = change(of: saved, at: .seconds(400))

        try await store.updatePlayback(id: saved.id) { _ in waiting }

        let data = try Data(contentsOf: directory.appending(path: "downloads.json"))
        let index = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let changes = try #require(index["changes"] as? [[String: Any]])
        let keys = Set(try #require(changes.first).keys)
        #expect(changes.count == 1)
        #expect(keys == ["serverID", "userID", "itemID", "position", "isPlayed", "changed"])
    }

    @Test func changesForTheServerOutliveARelaunchAndTheirDownload() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)
        let waiting = change(of: saved, at: .seconds(400))

        try await store.updatePlayback(id: saved.id) { _ in waiting }
        try await store.remove(ids: [saved.id])

        let reloaded = DownloadStore(directory: directory)
        #expect(try await reloaded.changes() == [waiting])
        #expect(try await reloaded.records().isEmpty)
    }

    @Test func aLaterChangeToAnItemTakesTheEarliersPlace() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let first = record("item-1")
        let second = record("item-2")
        try await store.save(first)
        try await store.save(second)
        let earlier = change(of: first, at: .seconds(400))
        let other = change(of: second, at: .seconds(100))
        let later = change(of: first, at: .seconds(700))

        try await store.updatePlayback(id: first.id) { _ in earlier }
        try await store.updatePlayback(id: second.id) { _ in other }
        try await store.updatePlayback(id: first.id) { _ in later }

        #expect(try await store.changes() == [other, later])
    }

    @Test func aChangeSentIsForgottenButNotOneMadeSince() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)
        let sent = change(of: saved, at: .seconds(400))
        let since = change(of: saved, at: .seconds(700))
        try await store.updatePlayback(id: saved.id) { _ in sent }
        try await store.updatePlayback(id: saved.id) { _ in since }

        try await store.removeChange(sent)
        #expect(try await store.changes() == [since])

        try await store.removeChange(since)
        #expect(try await store.changes().isEmpty)
    }

    @Test func theServersPlaybackWaitsForAChangeMadeOnTheDevice() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        var saved = record("item-1")
        saved.playback = DownloadPlayback(position: .seconds(400))
        try await store.save(saved)
        let waiting = change(of: saved, at: .seconds(400))
        try await store.updatePlayback(id: saved.id) { _ in waiting }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let server = DownloadPlayback(position: .zero, changed: date, isPlayed: true)

        // The change made on the device, waiting for the server, is newer.
        let kept = try await store.setServerPlayback(server, forItem: "item-1", key: key, replacingChanges: false)
        #expect(!kept)
        #expect(try await store.record(id: saved.id)?.playback == saved.playback)
        #expect(try await store.changes() == [waiting])

        // A change made on the server since, as a mark made there, is newer still.
        let replaced = try await store.setServerPlayback(server, forItem: "item-1", key: key, replacingChanges: true)
        #expect(replaced)
        #expect(try await store.record(id: saved.id)?.playback == server)
        #expect(try await store.changes().isEmpty)

        // With nothing waiting, the same again changes nothing, and nil clears it.
        let again = try await store.setServerPlayback(server, forItem: "item-1", key: key, replacingChanges: false)
        #expect(!again)
        let cleared = try await store.setServerPlayback(nil, forItem: "item-1", key: key, replacingChanges: false)
        #expect(cleared)
        #expect(try await store.record(id: saved.id)?.playback == nil)
    }

    @Test func theFolderIsExcludedFromBackup() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        try await store.save(record("item-1"))
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func removingADownloadDeletesItsFile() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)
        try Data("movie".utf8).write(to: store.fileURL(for: saved))
        try await store.remove(ids: [saved.id, "missing"])
        #expect(try await store.records().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL(for: saved).path(percentEncoded: false)))
    }

    @Test func filesAndPicturesNoDownloadNamesAreDeleted() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let kept = record("item-1")
        try await store.save(kept)
        try Data("movie".utf8).write(to: store.fileURL(for: kept))
        try await store.saveArtwork(png, .backdrop, of: kept.id)
        let orphans = [store.fileURL(named: "orphan.mp4"), store.artworkURL(.poster, of: "orphan")]
        for orphan in orphans {
            try Data("left over".utf8).write(to: orphan)
        }
        try await store.removeOrphanedFiles()
        #expect(isSaved(store.fileURL(for: kept)))
        #expect(isSaved(store.artworkURL(.backdrop, of: kept.id)))
        #expect(!orphans.contains(where: isSaved))
    }

    @Test func aPictureIsSavedBesideItsDownloadAndDeletedWithIt() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)

        #expect(try await store.saveArtwork(png, .poster, of: saved.id))

        let poster = store.artworkURL(.poster, of: saved.id)
        #expect(poster.lastPathComponent == "\(saved.id)-poster")
        #expect(try Data(contentsOf: poster) == png)
        try await store.remove(ids: [saved.id])
        #expect(!isSaved(poster))
    }

    @Test func onlyAPictureOfASensibleSizeForASavedDownloadIsSaved() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)

        let errorPage = Data(#"{"Message":"Not found"}"#.utf8)
        #expect(try await store.saveArtwork(errorPage, .poster, of: saved.id) == false)
        let huge = png + Data(count: DownloadStore.maximumArtworkSize)
        #expect(try await store.saveArtwork(huge, .backdrop, of: saved.id) == false)
        #expect(try await store.saveArtwork(png, .poster, of: "deleted") == false)

        #expect(!isSaved(store.artworkURL(.poster, of: saved.id)))
        #expect(!isSaved(store.artworkURL(.backdrop, of: saved.id)))
        #expect(!isSaved(store.artworkURL(.poster, of: "deleted")))
    }

    @Test func tracksAndPositionsAreSavedWithTheDownload() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var saved = record("item-1")
        saved.tracks = DownloadTracks(
            audio: [DownloadTrack(index: 1, codec: "aac", language: "eng", channelLayout: "stereo", isDefault: true)],
            subtitles: [DownloadTrack(index: 3, codec: "mov_text", language: "eng", isForced: true, isText: true)],
            defaultAudio: 1,
            defaultSubtitles: 3
        )
        saved.playback = DownloadPlayback(position: .seconds(95), changed: Date(timeIntervalSince1970: 1_790_000_000))
        try await DownloadStore(directory: directory).save(saved)
        #expect(try await DownloadStore(directory: directory).records() == [saved])
    }

    @Test func anUpdateChangesTheSavedDownload() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1")
        try await store.save(saved)
        let changed = try await store.update(id: saved.id) { $0.playback = DownloadPlayback(position: .seconds(60)) }
        #expect(changed?.playback?.position == .seconds(60))
        let reloaded = try await DownloadStore(directory: directory).records()
        #expect(reloaded.first?.playback?.position == .seconds(60))
    }

    @Test func anUpdateNeverBringsBackADeletedDownload() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let saved = record("item-1", state: .downloading)
        try await store.save(saved)
        try await store.remove(ids: [saved.id])
        let changed = try await store.update(id: saved.id) { $0.state = .finished }
        #expect(changed == nil)
        #expect(try await store.records().isEmpty)
    }

    @Test func anIndexSavedBeforeOverviewsAndPicturesStillReads() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let index = """
            {"version": 1, "downloads": [{"id": "A", "serverID": "server-1", "userID": "user-1", "itemID": "item-1",
            "mediaSourceID": "item-1", "fileExtension": "mp4", "created": 0, "state": "finished",
            "metadata": {"title": "Sintel", "kind": "movie", "year": 2010}}]}
            """
        try Data(index.utf8).write(to: directory.appending(path: "downloads.json"))

        let store = DownloadStore(directory: directory)
        let saved = try #require(try await store.records().first)

        #expect(saved.metadata == DownloadMetadata(title: "Sintel", kind: .movie, year: 2010))
        #expect(saved.playback == nil)
        #expect(try await store.changes().isEmpty)
    }

    @Test func anUnreadableIndexIsAnError() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appending(path: "downloads.json"))
        await #expect(throws: DownloadError.storeUnavailable) {
            try await DownloadStore(directory: directory).records()
        }
    }
}

@Suite struct DownloadPlaybackTests {
    /// An hour and a half.
    private let movie = Duration.seconds(5400)

    private func resume(at position: Duration, runtime: Duration?) -> Duration {
        DownloadPlayback(position: position).resumePosition(runtime: runtime)
    }

    @Test func aDownloadResumesWhereItStopped() {
        #expect(resume(at: .seconds(2700), runtime: movie) == .seconds(2700))
    }

    @Test func aStopInTheFirstMomentsStartsOver() {
        // 5% of an hour and a half is four and a half minutes.
        #expect(resume(at: .seconds(200), runtime: movie) == .zero)
        #expect(resume(at: .seconds(280), runtime: movie) == .seconds(280))
    }

    @Test func aStopNearTheEndCountsAsWatched() {
        #expect(resume(at: .seconds(4900), runtime: movie) == .zero)
        #expect(resume(at: movie, runtime: movie) == .zero)
    }

    @Test func aShortVideoNeverResumes() {
        #expect(resume(at: .seconds(120), runtime: .seconds(240)) == .zero)
    }

    @Test func withNoRuntimeItResumesWhereItStopped() {
        #expect(resume(at: .seconds(300), runtime: nil) == .seconds(300))
        #expect(resume(at: .seconds(-1), runtime: nil) == .zero)
    }

    @Test func aStopNearTheEndOrPastTheStartOfAShortVideoIsWatched() {
        #expect(DownloadPlayback(position: .seconds(4900)).isPlayed(runtime: movie))
        #expect(DownloadPlayback(position: .seconds(120)).isPlayed(runtime: .seconds(240)))
        #expect(!DownloadPlayback(position: .seconds(2700)).isPlayed(runtime: movie))
        #expect(!DownloadPlayback(position: .seconds(5)).isPlayed(runtime: .seconds(240)))
    }

    @Test func withNoRuntimeOrNoPositionNothingIsWatched() {
        #expect(!DownloadPlayback(position: .seconds(4900)).isPlayed(runtime: nil))
        #expect(!DownloadPlayback(position: .zero).isPlayed(runtime: movie))
    }

    @Test func aMarkOrTheServerSaysWhetherItsWatched() {
        #expect(DownloadPlayback(position: .zero, isPlayed: true).isPlayed(runtime: movie))
        #expect(!DownloadPlayback(position: .seconds(4900), isPlayed: false).isPlayed(runtime: movie))
    }
}

@Suite struct DownloadTransfersTests {
    @Test func onlyPlainFileNamesAreSavedTo() {
        #expect(DownloadTransfers.isPlainFileName("6F9619FF-8B86-D011-B42D-00C04FC964FF.mp4"))
        #expect(!DownloadTransfers.isPlainFileName("../downloads.json"))
        #expect(!DownloadTransfers.isPlainFileName(".hidden"))
        #expect(!DownloadTransfers.isPlainFileName("a/b.mp4"))
        #expect(!DownloadTransfers.isPlainFileName(""))
    }

    @Test func statusesBecomeFailures() {
        #expect(DownloadTransfers.failure(forStatus: 403) == .notAllowed)
        #expect(DownloadTransfers.failure(forStatus: 401) == .notAllowed)
        #expect(DownloadTransfers.failure(forStatus: 404) == .notFound)
        #expect(DownloadTransfers.failure(forStatus: 500) == .serverError)
        #expect(DownloadTransfers.failure(forStatus: nil) == .serverError)
    }

    @Test func errorsBecomeFailures() {
        let full = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        #expect(DownloadTransfers.failure(for: full) == .storageFull)
        #expect(DownloadTransfers.failure(for: URLError(.networkConnectionLost)) == .network)
    }
}

/// English subtitles inside a file, and Spanish ones the server sends as WebVTT to add to its copy.
private let english = DownloadTrack(index: 2, codec: "mov_text", language: "eng", isText: true)
private let spanish = DownloadTrack(index: 3, codec: "subrip", language: "spa", isText: true)
private let webVTT = "WEBVTT\n\n00:00.000 --> 00:01.000\nHola\n"

/// Writes each download's copy as the file that arrived followed by the subtitles added to it, after failing as it's
/// told to first.
private actor FakePreparer: DownloadPreparing {
    private var failures: [DownloadPreparationError]
    /// The copies asked for, in order.
    private(set) var jobs: [DownloadPreparationJob] = []

    init(failing failures: [DownloadPreparationError] = []) {
        self.failures = failures
    }

    func prepare(_ job: DownloadPreparationJob) async throws {
        jobs.append(job)
        if !failures.isEmpty {
            throw failures.removeFirst()
        }
        var copy = try Data(contentsOf: job.arrived)
        for subtitles in job.subtitles {
            copy.append(try Data(contentsOf: subtitles.file))
        }
        try copy.write(to: job.output)
    }
}

/// Writes nothing, as a long copy does, until it's cancelled.
private actor StalledPreparer: DownloadPreparing {
    private(set) var isStarted = false
    private(set) var isCancelled = false

    func prepare(_ job: DownloadPreparationJob) async throws {
        isStarted = true
        do {
            try await Task.sleep(for: .seconds(60))
        } catch {
            isCancelled = true
            throw error
        }
    }
}

/// Waits until `condition` holds.
private func eventually(_ condition: () async throws -> Bool) async throws {
    for _ in 0..<1000 {
        if try await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    throw CancellationError()
}

/// Downloads on a throwaway folder, moving files from a stubbed server. Every test uses its own host.
private struct DownloadsHarness {
    let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
    let key = SessionKey(serverID: "server-1", userID: "user-1")
    let store: DownloadStore
    let downloads: Downloads

    /// Creates downloads whose copies `preparer` writes, while the test runs.
    init(preparer: (any DownloadPreparing)? = nil) async throws {
        let secrets = InMemorySecretStore()
        let sessions = SessionStore(
            secrets: secrets,
            defaults: try #require(UserDefaults(suiteName: "serafin-tests-\(UUID().uuidString)"))
        )
        try await sessions.setToken("token-1", for: key)
        store = DownloadStore(directory: directory)
        let transfers = DownloadTransfers(
            configuration: StubURLProtocol.configuration(),
            pinning: nil,
            mediaDirectory: store.mediaDirectory
        )
        downloads = Downloads(
            store: store,
            transfers: transfers,
            identity: DeviceIdentity(secrets: secrets, deviceName: "iPhone", version: "1.1.0"),
            sessions: sessions,
            preparer: preparer,
            asksForBackgroundTime: false
        )
        await downloads.activate()
    }

    func request(host: String, itemID: String = "item-1") throws -> Downloads.Request {
        Downloads.Request(
            itemID: itemID,
            mediaSourceID: itemID,
            url: try #require(URL(string: "https://\(host)/Items/\(itemID)/Download")),
            fileExtension: "mp4",
            bytes: 5,
            metadata: DownloadMetadata(title: "Sintel", kind: .movie),
            allowsCellularAccess: true
        )
    }

    /// A request for a file whose copy is written once it arrives, with Spanish subtitles added to its English ones:
    /// one the server converts, or an original, which plays as it arrives.
    func withSubtitles(host: String, playsAsItArrives: Bool = false) throws -> Downloads.Request {
        var made = try request(host: host)
        made.tracks = DownloadTracks(subtitles: [english, spanish], defaultSubtitles: spanish.index)
        made.preparation = Downloads.Preparation(
            subtitles: [Downloads.Subtitles(index: spanish.index, webVTT: Data(webVTT.utf8))],
            playsAsItArrives: playsAsItArrives
        )
        return made
    }

    /// Waits until the download of `itemID` is no longer on its way.
    func settled(_ itemID: String = "item-1") async throws -> DownloadRecord {
        for _ in 0..<1000 {
            if let record = try await downloads.record(forItem: itemID, key: key), record.state != .downloading {
                return record
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CancellationError()
    }

    /// Waits until the download of `itemID` is neither on its way nor waiting for its copy.
    func prepared(_ itemID: String = "item-1") async throws -> DownloadRecord {
        for _ in 0..<1000 {
            let record = try await settled(itemID)
            if record.state != .preparing {
                return record
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw CancellationError()
    }

    /// The names of the files kept for downloads, in order.
    func savedFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: store.mediaDirectory.path(percentEncoded: false)).sorted()
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@Suite struct DownloadsTests {
    @Test func aFinishedDownloadIsSavedWithTheTokenInTheHeaderOnly() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-finish.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))

        try await harness.downloads.start(try harness.request(host: host), for: harness.key)
        let record = try await harness.settled()

        #expect(record.state == .finished)
        #expect(record.bytes == 5)
        let file = try #require(harness.downloads.fileURL(for: record))
        #expect(try Data(contentsOf: file) == Data("movie".utf8))
        let sent = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items/item-1/Download").first)
        #expect(sent.authorization?.contains(#"Token="token-1""#) == true)
        #expect(sent.request.url?.query == nil)
    }

    @Test func aRefusedDownloadFailsAsNotAllowedAndSavesNothing() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-refused.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(403, "{}"))

        try await harness.downloads.start(try harness.request(host: host), for: harness.key)
        let record = try await harness.settled()

        #expect(record.state == .failed)
        #expect(record.failure == .notAllowed)
        #expect(harness.downloads.fileURL(for: record) == nil)
    }

    @Test func aFailedDownloadCanBeTriedAgain() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-retry.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/item-1/Download", .failure(.networkConnectionLost), .json(200, "movie"))

        let request = try harness.request(host: host)
        try await harness.downloads.start(request, for: harness.key)
        #expect(try await harness.settled().failure == .network)

        try await harness.downloads.start(request, for: harness.key)
        let record = try await harness.settled()
        #expect(record.state == .finished)
        #expect(try await harness.downloads.records(for: harness.key).count == 1)
    }

    @Test func deletingRemovesTheRecordAndTheFile() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-delete.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        try await harness.downloads.start(try harness.request(host: host), for: harness.key)
        let record = try await harness.settled()
        let file = try #require(harness.downloads.fileURL(for: record))

        try await harness.downloads.delete(record.id)

        #expect(try await harness.downloads.records(for: harness.key).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
    }

    @Test func signingOutDeletesOnlyThatAccountsDownloads() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let other = DownloadRecord(
            key: SessionKey(serverID: "server-2", userID: "user-2"),
            itemID: "item-2",
            mediaSourceID: "item-2",
            fileExtension: "mp4",
            state: .finished,
            metadata: DownloadMetadata(title: "Spring", kind: .movie)
        )
        try await harness.store.save(other)
        let host = "downloads-sign-out.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        try await harness.downloads.start(try harness.request(host: host), for: harness.key)
        _ = try await harness.settled()

        try await harness.downloads.deleteAll(for: harness.key)

        #expect(try await harness.downloads.records(for: harness.key).isEmpty)
        #expect(try await harness.store.records() == [other])
    }

    @Test func aDownloadLeftRunningByAnEarlierLaunchIsInterrupted() async throws {
        let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let key = SessionKey(serverID: "server-1", userID: "user-1")
        let store = DownloadStore(directory: directory)
        try await store.save(
            DownloadRecord(
                key: key, itemID: "item-1", mediaSourceID: "item-1", fileExtension: "mp4",
                metadata: DownloadMetadata(title: "Sintel", kind: .movie)))
        let secrets = InMemorySecretStore()
        let downloads = Downloads(
            store: store,
            transfers: DownloadTransfers(
                configuration: StubURLProtocol.configuration(), pinning: nil, mediaDirectory: store.mediaDirectory),
            identity: DeviceIdentity(secrets: secrets, deviceName: "iPhone", version: "1.1.0"),
            sessions: SessionStore(
                secrets: secrets,
                defaults: try #require(UserDefaults(suiteName: "serafin-tests-\(UUID().uuidString)")))
        )
        await downloads.activate()

        var record = try await downloads.record(forItem: "item-1", key: key)
        for _ in 0..<1000 where record?.state == .downloading {
            try await Task.sleep(for: .milliseconds(5))
            record = try await downloads.record(forItem: "item-1", key: key)
        }
        #expect(record?.state == .failed)
        #expect(record?.failure == .interrupted)
    }

    @Test func theTracksAskedForAreSavedWithTheDownload() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-tracks.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        var request = try harness.request(host: host)
        request.tracks = DownloadTracks(audio: [DownloadTrack(index: 1, codec: "aac")], defaultAudio: 1)

        try await harness.downloads.start(request, for: harness.key)

        #expect(try await harness.settled().tracks == request.tracks)
    }

    @Test func whereADownloadStoppedPlayingIsKept() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-position.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        try await harness.downloads.start(try harness.request(host: host), for: harness.key)
        let record = try await harness.settled()

        try await harness.downloads.savePosition(.seconds(95), of: record.id)

        let kept = try #require(try await harness.downloads.record(forItem: "item-1", key: harness.key))
        #expect(kept.playback?.position == .seconds(95))
        #expect(kept.state == .finished)
    }

    @Test func whereADownloadStopsIsKeptForTheServerAsJellyfinRecordsIt() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-stop-for-server.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        var request = try harness.request(host: host)
        request.metadata.runtime = .seconds(888)
        try await harness.downloads.start(request, for: harness.key)
        let record = try await harness.settled()

        try await harness.downloads.savePosition(.seconds(400), of: record.id)
        let partway = try #require(try await harness.downloads.playbackChanges(for: harness.key).first)
        #expect(partway.itemID == "item-1")
        #expect(partway.position == .seconds(400))
        #expect(!partway.isPlayed)

        // Stopped near the end, it's watched, and resumes from the start.
        try await harness.downloads.savePosition(.seconds(860), of: record.id)
        let changes = try await harness.downloads.playbackChanges(for: harness.key)
        #expect(changes.count == 1)
        #expect(changes.first?.position == .zero)
        #expect(changes.first?.isPlayed == true)
        let kept = try #require(try await harness.downloads.record(forItem: "item-1", key: harness.key))
        #expect(kept.playback?.position == .seconds(860))
        #expect(kept.playback?.isPlayed == true)
        #expect(kept.playback?.changed == changes.first?.changed)
    }

    @Test func aDownloadMarkedWatchedWithNoServerKeepsTheMarkForIt() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-mark-for-server.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        try await harness.downloads.start(try harness.request(host: host), for: harness.key)
        _ = try await harness.settled()

        try await harness.downloads.setPlayed(true, ofItem: "item-1", key: harness.key)
        try await harness.downloads.setPlayed(true, ofItem: "item-9", key: harness.key)

        let kept = try #require(try await harness.downloads.record(forItem: "item-1", key: harness.key))
        #expect(kept.playback?.position == .zero)
        #expect(kept.playback?.isPlayed == true)
        let changes = try await harness.downloads.playbackChanges(for: harness.key)
        #expect(changes.map(\.itemID) == ["item-1"])
        #expect(changes.first?.position == .zero)
        #expect(changes.first?.isPlayed == true)
    }

    @Test func signingOutForgetsTheProgressWaitingForTheServer() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let otherKey = SessionKey(serverID: "server-2", userID: "user-2")
        let mine = DownloadRecord(
            key: harness.key, itemID: "item-1", mediaSourceID: "item-1", fileExtension: "mp4", state: .finished,
            metadata: DownloadMetadata(title: "Sintel", kind: .movie))
        let theirs = DownloadRecord(
            key: otherKey, itemID: "item-2", mediaSourceID: "item-2", fileExtension: "mp4", state: .finished,
            metadata: DownloadMetadata(title: "Spring", kind: .movie))
        for record in [mine, theirs] {
            try await harness.store.save(record)
            try await harness.downloads.savePosition(.seconds(60), of: record.id)
        }

        // Deleted before the server heard where it stopped, which still waits for it.
        try await harness.downloads.delete(mine.id)
        #expect(try await harness.downloads.playbackChanges(for: harness.key).count == 1)

        try await harness.downloads.deleteAll(for: harness.key)
        #expect(try await harness.downloads.playbackChanges(for: harness.key).isEmpty)
        #expect(try await harness.downloads.playbackChanges(for: otherKey).count == 1)

        try await harness.downloads.deleteAll(forServer: "server-2")
        #expect(try await harness.store.changes().isEmpty)
    }

    @Test func aPositionForADeletedDownloadIsDropped() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-position-deleted.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        try await harness.downloads.start(try harness.request(host: host), for: harness.key)
        let record = try await harness.settled()
        try await harness.downloads.delete(record.id)

        try await harness.downloads.savePosition(.seconds(95), of: record.id)

        #expect(try await harness.downloads.records(for: harness.key).isEmpty)
    }

    @Test func whereTheServerSaysPlaybackStoppedIsSavedWithTheDownload() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-server-position.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        var request = try harness.request(host: host)
        request.playback = DownloadPlayback(position: .seconds(95), changed: Date(timeIntervalSince1970: 1_790_000_000))

        try await harness.downloads.start(request, for: harness.key)

        #expect(try await harness.settled().playback == request.playback)
    }

    @Test func aPictureSavedWithADownloadIsFoundAndDeletedWithIt() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        let host = "downloads-picture.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))
        try await harness.downloads.start(try harness.request(host: host), for: harness.key)
        let record = try await harness.settled()
        #expect(harness.downloads.artworkURL(.poster, for: record) == nil)

        try await harness.downloads.saveArtwork(png, .poster, of: record.id)

        let poster = try #require(harness.downloads.artworkURL(.poster, for: record))
        #expect(harness.downloads.artworkURL(.backdrop, for: record) == nil)
        try await harness.downloads.delete(record.id)
        #expect(!isSaved(poster))
    }

    @Test func aCopyIsWrittenWithTheSubtitlesAddedThenTheDownloadFinishes() async throws {
        let preparer = FakePreparer()
        let harness = try await DownloadsHarness(preparer: preparer)
        defer { harness.cleanUp() }
        let host = "downloads-prepare.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))

        let started = try await harness.downloads.start(try harness.withSubtitles(host: host), for: harness.key)
        #expect(started.state == .downloading)
        #expect(started.fileExtension == "mov")
        let record = try await harness.prepared()

        #expect(record.state == .finished)
        #expect(record.preparation == nil)
        #expect(record.tracks?.subtitles == [english, spanish])
        let copy = Data("movie\(webVTT)".utf8)
        #expect(record.bytes == Int64(copy.count))
        let file = try #require(harness.downloads.fileURL(for: record))
        #expect(try Data(contentsOf: file) == copy)
        // What arrived and the subtitles are in the copy, so only the copy is kept.
        #expect(try harness.savedFiles() == ["\(record.id).mov"])
        let added = await preparer.jobs.map { job in job.subtitles.map(\.track) }
        #expect(added == [[spanish]])
    }

    @Test func aCopyThatCantBeWrittenFailsTheDownloadAndKeepsNothing() async throws {
        let cases: [(DownloadPreparationError, DownloadFailure, String)] = [
            (.unreadable, .preparationFailed, "unreadable"),
            (.storageFull, .storageFull, "full"),
        ]
        for (error, failure, name) in cases {
            let harness = try await DownloadsHarness(preparer: FakePreparer(failing: [error]))
            defer { harness.cleanUp() }
            let host = "downloads-prepare-\(name).example.com"
            StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))

            try await harness.downloads.start(try harness.withSubtitles(host: host), for: harness.key)
            let record = try await harness.prepared()

            #expect(record.state == .failed)
            #expect(record.failure == failure)
            #expect(harness.downloads.fileURL(for: record) == nil)
            #expect(try harness.savedFiles().isEmpty)
        }
    }

    @Test func anOriginalWhoseCopyCantBeWrittenIsKeptAsItArrived() async throws {
        let harness = try await DownloadsHarness(preparer: FakePreparer(failing: [.unreadable]))
        defer { harness.cleanUp() }
        let host = "downloads-prepare-original.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))

        let request = try harness.withSubtitles(host: host, playsAsItArrives: true)
        try await harness.downloads.start(request, for: harness.key)
        let record = try await harness.prepared()

        #expect(record.state == .finished)
        #expect(record.preparation == nil)
        #expect(record.fileExtension == "mp4")
        // Without the subtitles that were to be added, which aren't in the file.
        #expect(record.tracks?.subtitles == [english])
        #expect(record.tracks?.defaultSubtitles == nil)
        let file = try #require(harness.downloads.fileURL(for: record))
        #expect(try Data(contentsOf: file) == Data("movie".utf8))
        #expect(try harness.savedFiles() == ["\(record.id).mp4"])
    }

    @Test func aDownloadTheServerConvertsStartsAfreshWhenTriedAgain() async throws {
        let harness = try await DownloadsHarness(preparer: FakePreparer())
        defer { harness.cleanUp() }
        let host = "downloads-prepare-afresh.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/item-1/Download", .failure(.networkConnectionLost), .json(200, "movie"))

        let request = try harness.withSubtitles(host: host)
        let failed = try await harness.downloads.start(request, for: harness.key)
        #expect(try await harness.settled().failure == .network)

        try await harness.downloads.start(request, for: harness.key)
        let record = try await harness.prepared()
        #expect(record.state == .finished)
        // The server converts the file anew, so the transfer doesn't carry on from the last.
        #expect(record.id != failed.id)
        #expect(try await harness.downloads.records(for: harness.key).count == 1)
        let file = try #require(harness.downloads.fileURL(for: record))
        #expect(try Data(contentsOf: file) == Data("movie\(webVTT)".utf8))
    }

    @Test func anOriginalWithSubtitlesToAddCarriesOnWhenTriedAgain() async throws {
        let harness = try await DownloadsHarness(preparer: FakePreparer())
        defer { harness.cleanUp() }
        let host = "downloads-prepare-retry.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/item-1/Download", .failure(.networkConnectionLost), .json(200, "movie"))

        let request = try harness.withSubtitles(host: host, playsAsItArrives: true)
        let failed = try await harness.downloads.start(request, for: harness.key)
        #expect(try await harness.settled().failure == .network)

        try await harness.downloads.start(request, for: harness.key)
        let record = try await harness.prepared()
        #expect(record.state == .finished)
        #expect(record.id == failed.id)
        // The subtitles saved when it started are added.
        let file = try #require(harness.downloads.fileURL(for: record))
        #expect(try Data(contentsOf: file) == Data("movie\(webVTT)".utf8))
    }

    @Test func aDownloadWhoseCopyCouldntBeWrittenStartsAfreshWhenTriedAgain() async throws {
        let harness = try await DownloadsHarness(preparer: FakePreparer(failing: [.unreadable]))
        defer { harness.cleanUp() }
        let host = "downloads-prepare-again.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"), .json(200, "movie"))

        let request = try harness.withSubtitles(host: host)
        let failed = try await harness.downloads.start(request, for: harness.key)
        #expect(try await harness.prepared().failure == .preparationFailed)

        try await harness.downloads.start(request, for: harness.key)
        let record = try await harness.prepared()
        #expect(record.state == .finished)
        #expect(record.id != failed.id)
        let file = try #require(harness.downloads.fileURL(for: record))
        #expect(try Data(contentsOf: file) == Data("movie\(webVTT)".utf8))
    }

    @Test func deletingADownloadWhileItsCopyIsWrittenStopsTheCopy() async throws {
        let preparer = StalledPreparer()
        let harness = try await DownloadsHarness(preparer: preparer)
        defer { harness.cleanUp() }
        let host = "downloads-prepare-delete.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/item-1/Download", .json(200, "movie"))

        let record = try await harness.downloads.start(try harness.withSubtitles(host: host), for: harness.key)
        #expect(try await harness.settled().state == .preparing)
        try await eventually { await preparer.isStarted }
        try await harness.downloads.delete(record.id)

        try await eventually { await preparer.isCancelled }
        #expect(try await harness.downloads.records(for: harness.key).isEmpty)
        #expect(try harness.savedFiles().isEmpty)
    }

    @Test func aFileThatWouldNotFitIsRefused() async throws {
        let harness = try await DownloadsHarness()
        defer { harness.cleanUp() }
        var request = try harness.request(host: "downloads-space.example.com")
        request.bytes = Int64.max
        await #expect(throws: DownloadError.notEnoughSpace) {
            try await harness.downloads.start(request, for: harness.key)
        }
        #expect(try await harness.downloads.records(for: harness.key).isEmpty)
    }
}

@Suite struct DownloadPermissionTests {
    @Test func theUsersPolicyDecidesWhetherTheyMayDownload() async throws {
        let host = "download-policy-off.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Users/Me",
            .json(200, #"{"Id":"user-1","Policy":{"IsAdministrator":false,"EnableContentDownloading":false}}"#))
        #expect(try await library(on: host).canDownload() == false)
    }

    @Test func aServerThatDoesntSayAllowsDownloading() async throws {
        let host = "download-policy-missing.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Users/Me", .json(200, #"{"Id":"user-1","Policy":{}}"#))
        #expect(try await library(on: host).canDownload() == true)
    }

    @Test func theUsersPolicyDecidesWhatTheServerMayConvertForThem() async throws {
        let host = "download-policy-conversion.example.com"
        let user =
            #"{"Id":"user-1","Policy":{"EnablePlaybackRemuxing":false,"EnableVideoPlaybackTranscoding":false,"EnableAudioPlaybackTranscoding":true}}"#
        StubURLProtocol.stub("\(host):443", path: "/Users/Me", .json(200, user))
        let permissions = try await library(on: host).conversionPermissions()
        #expect(permissions == ConversionPermissions(remuxing: false, videoTranscoding: false, audioTranscoding: true))
        #expect(permissions.allowsAny)
    }

    @Test func aServerThatDoesntSayAllowsEveryConversion() async throws {
        let host = "download-policy-conversion-missing.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Users/Me", .json(200, #"{"Id":"user-1","Policy":{}}"#))
        #expect(try await library(on: host).conversionPermissions() == .all)
        let nothing = ConversionPermissions(remuxing: false, videoTranscoding: false, audioTranscoding: false)
        #expect(!nothing.allowsAny)
    }
}
