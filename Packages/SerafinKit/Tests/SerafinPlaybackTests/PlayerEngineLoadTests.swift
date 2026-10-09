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
        load.cancel()
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
