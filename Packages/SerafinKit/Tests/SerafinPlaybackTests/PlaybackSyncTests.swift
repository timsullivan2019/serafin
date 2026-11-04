import Foundation
import JellyfinAPI
import Testing

@testable import SerafinCore
@testable import SerafinPlayback

/// An account's downloads on a throwaway store, and the sync that sends their progress to a stubbed server.
private struct SyncHarness {
    let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
    let key = SessionKey(serverID: "server-1", userID: "user-1")
    let host: String
    let store: DownloadStore
    let downloads: Downloads
    let sync: PlaybackSync

    init(host: String) throws {
        self.host = host
        let secrets = InMemorySecretStore()
        store = DownloadStore(directory: directory)
        downloads = Downloads(
            store: store,
            transfers: DownloadTransfers(
                configuration: StubURLProtocol.configuration(), pinning: nil, mediaDirectory: store.mediaDirectory),
            identity: DeviceIdentity(secrets: secrets, deviceName: "iPhone", version: "1.1.0"),
            sessions: SessionStore(
                secrets: secrets,
                defaults: try #require(UserDefaults(suiteName: "serafin-tests-\(UUID().uuidString)")))
        )
        sync = PlaybackSync(client: try stubClient(on: host), key: key, downloads: downloads)
    }

    /// Saves a finished download of the fifteen-minute `itemID`, last stopped as `playback` says.
    @discardableResult
    func download(_ itemID: String, playback: DownloadPlayback? = nil) async throws -> DownloadRecord {
        let record = DownloadRecord(
            key: key, itemID: itemID, mediaSourceID: itemID, fileExtension: "mp4", state: .finished,
            metadata: DownloadMetadata(title: "Sintel", kind: .movie, runtime: .seconds(888)), playback: playback)
        try await store.save(record)
        return record
    }

    /// Has the server list `items` when asked for the account's items by ID.
    func serverHas(_ items: [[String: Any]]) throws {
        let page: [String: Any] = ["Items": items, "TotalRecordCount": items.count, "StartIndex": 0]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: page), as: UTF8.self)
        StubURLProtocol.stub("\(host):443", path: "/Items", .json(200, json))
    }

    /// The requests that sent `itemID`'s progress.
    func sent(_ itemID: String) -> [StubURLProtocol.Received] {
        StubURLProtocol.requests(to: "\(host):443", path: "/UserItems/\(itemID)/UserData")
    }

    /// Has the server answer `status` to progress sent for `itemID`.
    func serverAnswers(_ status: Int, toProgressOf itemID: String) {
        StubURLProtocol.stub("\(host):443", path: "/UserItems/\(itemID)/UserData", .json(status, "{}"))
    }

    /// The account's download of `itemID`.
    func record(_ itemID: String) async throws -> DownloadRecord {
        try #require(try await downloads.record(forItem: itemID, key: key))
    }

    /// The changes to playback waiting for the server.
    func waiting() async throws -> [PlaybackChange] {
        try await downloads.playbackChanges(for: key)
    }

    /// Lets the downloads be saved, or not, as when the device is out of space.
    func setWritable(_ isWritable: Bool) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: isWritable ? 0o755 : 0o555], ofItemAtPath: directory.path(percentEncoded: false))
    }

    func cleanUp() {
        try? setWritable(true)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// The server's item `id`, as it lists it with the account's data for it.
private func item(_ id: String, played: Bool = false, ticks: Int = 0, lastPlayed: String? = nil) -> [String: Any] {
    var userData: [String: Any] = ["Key": id, "Played": played, "PlaybackPositionTicks": ticks]
    userData["LastPlayedDate"] = lastPlayed
    return ["Id": id, "Name": "Sintel", "Type": "Movie", "UserData": userData]
}

@Suite struct PlaybackSyncTests {
    @Test func whereADownloadStoppedReachesTheServerOnceItAnswers() async throws {
        let harness = try SyncHarness(host: "sync-send.example.com")
        defer { harness.cleanUp() }
        let record = try await harness.download("aaaa1111")
        try await harness.downloads.savePosition(.seconds(400), of: record.id)
        let change = try #require(try await harness.waiting().first)
        try harness.serverHas([item("aaaa1111", lastPlayed: "2026-01-01T00:00:00.0000000Z")])
        harness.serverAnswers(200, toProgressOf: "aaaa1111")

        #expect(await harness.sync.run())

        let sent = try #require(harness.sent("aaaa1111").first)
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.authorization?.contains("Token=token-1") == true)
        #expect(sent.query("userId") == "user-1")
        let json = try body(of: sent)
        #expect(json["PlaybackPositionTicks"] as? Int == 4_000_000_000)
        #expect(json["Played"] as? Bool == false)
        // Jellyfin counts a play when it starts, which the server didn't hear, so the count stays as it is.
        #expect(json["PlayCount"] == nil)
        let lastPlayed = try #require(json["LastPlayedDate"] as? String)
        // The SDK writes dates to the millisecond.
        let date = try Date(lastPlayed, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        #expect(abs(date.timeIntervalSince(change.changed)) < 0.001)
        #expect(try await harness.waiting().isEmpty)
        #expect(try await harness.record("aaaa1111").playback?.position == .seconds(400))
    }

    @Test func aStopNearTheEndAndAMarkReachTheServerAsJellyfinRecordsThem() async throws {
        let harness = try SyncHarness(host: "sync-watched.example.com")
        defer { harness.cleanUp() }
        let finished = try await harness.download("aaaa1111")
        try await harness.download("bbbb2222")
        try await harness.downloads.savePosition(.seconds(860), of: finished.id)
        try await harness.downloads.setPlayed(false, ofItem: "bbbb2222", key: harness.key)
        try harness.serverHas([item("aaaa1111"), item("bbbb2222", played: true)])
        harness.serverAnswers(200, toProgressOf: "aaaa1111")
        harness.serverAnswers(200, toProgressOf: "bbbb2222")

        #expect(await harness.sync.run())

        let watched = try body(of: try #require(harness.sent("aaaa1111").first))
        #expect(watched["Played"] as? Bool == true)
        #expect(watched["PlaybackPositionTicks"] as? Int == 0)
        let unwatched = try body(of: try #require(harness.sent("bbbb2222").first))
        #expect(unwatched["Played"] as? Bool == false)
        #expect(unwatched["PlaybackPositionTicks"] as? Int == 0)
        #expect(try await harness.waiting().isEmpty)
    }

    @Test func aNewerChangeOnTheServerWins() async throws {
        let harness = try SyncHarness(host: "sync-server-wins.example.com")
        defer { harness.cleanUp() }
        let record = try await harness.download("aaaa1111")
        try await harness.downloads.savePosition(.seconds(400), of: record.id)
        // Watched to the end on another device after it stopped on this one.
        try harness.serverHas([item("aaaa1111", played: true, lastPlayed: "2099-01-01T00:00:00.0000000Z")])

        #expect(await harness.sync.run() == false)

        #expect(harness.sent("aaaa1111").isEmpty)
        #expect(try await harness.waiting().isEmpty)
        let lastPlayed = Date(timeIntervalSince1970: 4_070_908_800)
        let server = DownloadPlayback(position: .zero, changed: lastPlayed, isPlayed: true)
        #expect(try await harness.record("aaaa1111").playback == server)
    }

    @Test func progressWaitsWhileTheServerCantTakeIt() async throws {
        let harness = try SyncHarness(host: "sync-unreachable.example.com")
        defer { harness.cleanUp() }
        let record = try await harness.download("aaaa1111")
        try await harness.downloads.savePosition(.seconds(400), of: record.id)
        StubURLProtocol.stub("\(harness.host):443", path: "/Items", .failure(.cannotConnectToHost))

        #expect(await harness.sync.run() == false)
        #expect(try await harness.waiting().count == 1)

        // Answering, but failing to keep it, the server is sent it again next time, and the download keeps its own.
        try harness.serverHas([item("aaaa1111", ticks: 9_000_000_000, lastPlayed: "2026-01-01T00:00:00.0000000Z")])
        harness.serverAnswers(500, toProgressOf: "aaaa1111")

        #expect(await harness.sync.run() == false)
        #expect(harness.sent("aaaa1111").count == 1)
        #expect(try await harness.waiting().count == 1)
        #expect(try await harness.record("aaaa1111").playback?.position == .seconds(400))
    }

    @Test func progressTheServerTurnsDownOrHasNoItemForIsDropped() async throws {
        let harness = try SyncHarness(host: "sync-dropped.example.com")
        defer { harness.cleanUp() }
        let refused = try await harness.download("aaaa1111")
        let gone = try await harness.download("bbbb2222")
        try await harness.downloads.savePosition(.seconds(400), of: refused.id)
        try await harness.downloads.savePosition(.seconds(400), of: gone.id)
        try harness.serverHas([item("aaaa1111")])
        harness.serverAnswers(403, toProgressOf: "aaaa1111")

        #expect(await harness.sync.run() == false)

        #expect(harness.sent("aaaa1111").count == 1)
        #expect(harness.sent("bbbb2222").isEmpty)
        #expect(try await harness.waiting().isEmpty)
    }

    @Test func eachDownloadTakesOnWhatTheServerHas() async throws {
        let harness = try SyncHarness(host: "sync-server-playback.example.com")
        defer { harness.cleanUp() }
        try await harness.download("aaaa1111", playback: DownloadPlayback(position: .seconds(100)))
        try await harness.download("bbbb2222", playback: DownloadPlayback(position: .seconds(100)))
        // Played part way on another device, and marked unwatched on another.
        let partway = item("aaaa1111", ticks: 6_000_000_000, lastPlayed: "2026-10-04T12:00:00.0000000Z")
        try harness.serverHas([partway, item("bbbb2222")])

        #expect(await harness.sync.run() == false)

        let lastPlayed = Date(timeIntervalSince1970: 1_791_115_200)
        let server = DownloadPlayback(position: .seconds(600), changed: lastPlayed, isPlayed: false)
        #expect(try await harness.record("aaaa1111").playback == server)
        #expect(try await harness.record("bbbb2222").playback == nil)
    }

    @Test func aChangeMadeWhileProgressIsSentIsSentToo() async throws {
        let harness = try SyncHarness(host: "sync-meanwhile.example.com")
        defer { harness.cleanUp() }
        let first = try await harness.download("aaaa1111")
        let second = try await harness.download("bbbb2222")
        try await harness.downloads.savePosition(.seconds(400), of: first.id)
        let page = ["Items": [item("aaaa1111"), item("bbbb2222")]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: page), as: UTF8.self)
        StubURLProtocol.stub("\(harness.host):443", path: "/Items", .held("sync-meanwhile", .json(200, json)))
        harness.serverAnswers(200, toProgressOf: "aaaa1111")
        harness.serverAnswers(200, toProgressOf: "bbbb2222")

        let sending = Task { await harness.sync.run() }
        try await StubURLProtocol.waitForRequest(to: "\(harness.host):443", path: "/Items")
        try await harness.downloads.savePosition(.seconds(500), of: second.id)
        let again = Task { await harness.sync.run() }
        StubURLProtocol.release("sync-meanwhile")

        #expect(await sending.value)
        #expect(await again.value)
        #expect(harness.sent("aaaa1111").count == 1)
        #expect(harness.sent("bbbb2222").count == 1)
        #expect(try await harness.waiting().isEmpty)
    }

    @Test func progressThatCantBeForgottenIsntSentAgain() async throws {
        let harness = try SyncHarness(host: "sync-unsaved.example.com")
        defer { harness.cleanUp() }
        let record = try await harness.download("aaaa1111")
        try await harness.downloads.savePosition(.seconds(400), of: record.id)
        try harness.serverHas([item("aaaa1111")])
        harness.serverAnswers(200, toProgressOf: "aaaa1111")
        try harness.setWritable(false)

        #expect(await harness.sync.run())
        #expect(await harness.sync.run() == false)
        #expect(harness.sent("aaaa1111").count == 1)
        #expect(try await harness.waiting().count == 1)

        // Once the downloads can be saved again, it's forgotten, still without being sent again.
        try harness.setWritable(true)
        #expect(await harness.sync.run() == false)
        #expect(harness.sent("aaaa1111").count == 1)
        #expect(try await harness.waiting().isEmpty)
    }

    @Test func whatTheServerHasIsKeptAsADownloadKeepsIt() {
        let date = Date(timeIntervalSince1970: 1_791_115_200)
        let partway = UserItemDataDto(key: "k", lastPlayedDate: date, playbackPositionTicks: 6_000_000_000)
        let watched = UserItemDataDto(isPlayed: true, key: "k", lastPlayedDate: date, playbackPositionTicks: 0)
        #expect(DownloadPlayback(partway) == DownloadPlayback(position: .seconds(600), changed: date, isPlayed: false))
        #expect(DownloadPlayback(watched) == DownloadPlayback(position: .zero, changed: date, isPlayed: true))
        // Never started, or marked unwatched, which forgets when it was played.
        #expect(DownloadPlayback(UserItemDataDto(isPlayed: false, key: "k", playbackPositionTicks: 0)) == nil)
        #expect(DownloadPlayback(UserItemDataDto(key: "k")) == nil)
    }

    @Test func onlyAnErrorThatWouldComeAgainDropsAChange() {
        #expect(PlaybackSync.isTurnedDown(SerafinError.unexpectedResponse(status: 404)))
        #expect(!PlaybackSync.isTurnedDown(SerafinError.unexpectedResponse(status: 503)))
        #expect(!PlaybackSync.isTurnedDown(URLError(.timedOut)))
    }
}
