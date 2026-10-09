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
}
