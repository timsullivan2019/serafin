import AVFoundation
import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

@MainActor @Suite struct PlayerEngineLoadTests {
    /// An episode of two minutes, as the server lists it.
    private let episode = BaseItemDto(
        id: "1f3d9c1e78e12aae4c078801aeccb6de", runTimeTicks: 1_200_000_000, type: .episode)

    @Test func theNewItemShowsLoadingBeforeTheFirstWait() throws {
        let engine = PlayerEngine(client: try stubClient(on: "load.example.com"), userID: "user-1", pinning: nil)
        // Started at once, as the app starts it, so everything up to the load's first wait has happened on return.
        let load = Task.immediate {
            await engine.load(episode, options: PlaybackOptions(startPosition: .seconds(5)))
        }
        #expect(engine.item?.id == episode.id)
        #expect(engine.state == .loading)
        #expect(engine.elapsed == .seconds(5))
        #expect(engine.duration == .seconds(120))
        #expect(engine.nextItem == nil)
        #expect(engine.segments.isEmpty)
        #expect(engine.trickplay == nil)
        #expect(engine.chapters.isEmpty)
        load.cancel()
    }

    @Test func aDownloadedCopyPlaysItsFileWithoutAskingTheServer() async throws {
        let host = "load-copy.example.com"
        let engine = PlayerEngine(client: try stubClient(on: host), userID: "user-1", pinning: nil)
        let itemID = try #require(episode.id)
        let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        let tracks = DownloadTracks(audio: [DownloadTrack(index: 1, codec: "aac", language: "eng")], defaultAudio: 1)
        let copy = DownloadedCopy(file: file, mediaSourceID: itemID, tracks: tracks) { _ in }

        let load = Task.immediate { await engine.load(episode, options: PlaybackOptions(), from: copy) }
        for _ in 0..<1000 where engine.plan == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(engine.plan?.url == file)
        #expect(engine.plan?.isDownloaded == true)
        #expect(engine.plan?.audioStreamIndex == 1)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(itemID)/PlaybackInfo").isEmpty)
        load.cancel()
        await engine.stop()
    }

    @Test func theScrubberShowsTheServersThumbnailsOfTheVersionPlaying() throws {
        let version = "1f3d9c1e78e12aae4c078801aeccb6de"
        let other = "2a4e0d2f89f23bbf5d189912bfddc7ef"
        func size(_ width: Int) -> TrickplayInfoDto {
            TrickplayInfoDto(
                height: width * 9 / 16, interval: 10_000, thumbnailCount: 12, tileHeight: 10, tileWidth: 10,
                width: width)
        }
        let item = BaseItemDto(
            id: version, trickplay: [version: ["640": size(640), "320": size(320)], other: ["480": size(480)]])
        let layouts = try [320, 640].map { try #require(Trickplay(size($0))) }

        #expect(
            PlayerEngine.serverTrickplay(in: item, mediaSourceID: version)
                == .server(mediaSourceID: version, layouts: layouts))
        #expect(PlayerEngine.serverTrickplay(in: item, mediaSourceID: "3b5f1e3a90a34cca6e29aa23c0eed8f0") == nil)
        #expect(PlayerEngine.serverTrickplay(in: BaseItemDto(id: version), mediaSourceID: version) == nil)
        #expect(
            PlayerEngine.serverTrickplay(in: BaseItemDto(id: version, trickplay: [:]), mediaSourceID: version) == nil)
    }

    @Test func bitratesAreLoggedInMegabits() {
        #expect(PlayerEngine.megabits(18_200_000) == "18.2")
        #expect(PlayerEngine.megabits(0) == "0.0")
        // AVPlayer reports -1 when it doesn't know.
        #expect(PlayerEngine.megabits(-1) == "unknown")
    }

    @Test func aVersionIsLoggedByWhatItIsNotWhereItIs() {
        let hdr = PlayerEngine.describe(
            bitrate: 18_200_000, codecs: [kCMVideoCodecType_HEVC], range: .pq, size: CGSize(width: 3840, height: 2160))
        #expect(hdr == "18.2 Mbit/s hvc1 PQ 3840×2160")
        // A playlist can leave out everything but the bitrate.
        #expect(PlayerEngine.describe(bitrate: 2_500_000, codecs: [], range: nil, size: nil) == "2.5 Mbit/s")
        #expect(PlayerEngine.describe(bitrate: nil, codecs: [], range: nil, size: .zero) == "unknown Mbit/s")
    }
}
