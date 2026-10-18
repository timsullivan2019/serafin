import Foundation
import Testing

@testable import SerafinCore

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
        #expect(saved.fileName == "\(saved.id).mp4")
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

    @Test func filesNoDownloadNamesAreDeleted() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DownloadStore(directory: directory)
        let kept = record("item-1")
        try await store.save(kept)
        try Data("movie".utf8).write(to: store.fileURL(for: kept))
        let orphan = store.fileURL(named: "orphan.mp4")
        try Data("left over".utf8).write(to: orphan)
        try await store.removeOrphanedFiles()
        #expect(FileManager.default.fileExists(atPath: store.fileURL(for: kept).path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: orphan.path(percentEncoded: false)))
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

/// Downloads on a throwaway folder, moving files from a stubbed server. Every test uses its own host.
private struct DownloadsHarness {
    let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
    let key = SessionKey(serverID: "server-1", userID: "user-1")
    let store: DownloadStore
    let downloads: Downloads

    init() async throws {
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
            sessions: sessions
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
}
