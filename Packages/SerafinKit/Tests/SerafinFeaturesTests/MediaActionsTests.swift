import SerafinCore
import SerafinDesign
import SwiftUI
import Testing

@testable import SerafinFeatures

@MainActor @Suite struct MediaActionsTests {
    private let item = MediaItem(card: MockMedia.movies[0], source: nil)

    @Test func markingPlayedIsConfirmedWithSuccess() async throws {
        let actions = MediaActions()
        await actions.setPlayed(true, for: item, in: SampleMediaSource())
        let confirmation = try #require(actions.confirmation)
        #expect(confirmation.kind == .played)
        #expect(confirmation.feedback == .success)
        #expect(actions.revision == 1)
    }

    @Test func otherChangesAreConfirmedWithATick() async throws {
        let actions = MediaActions()
        await actions.setPlayed(false, for: item, in: SampleMediaSource())
        #expect(actions.confirmation?.kind == .unplayed)
        #expect(actions.confirmation?.feedback == .selection)
        await actions.setFavourite(true, for: item, in: SampleMediaSource())
        #expect(actions.confirmation?.kind == .favourite)
        await actions.setFavourite(false, for: item, in: SampleMediaSource())
        #expect(actions.confirmation?.kind == .notFavourite)
        #expect(actions.confirmation?.feedback == .selection)
    }

    @Test func theSameChangeTwiceIsConfirmedTwice() async {
        let actions = MediaActions()
        await actions.setPlayed(true, for: item, in: SampleMediaSource())
        let first = actions.confirmation
        await actions.setPlayed(true, for: item, in: SampleMediaSource())
        #expect(actions.confirmation != first)
    }

    @Test func playbackReloadsAndFailuresAreNotConfirmed() async {
        let actions = MediaActions()
        actions.reload()
        #expect(actions.confirmation == nil)
        await actions.setPlayed(true, for: item, in: TestMediaSource(refusesChanges: true))
        #expect(actions.confirmation == nil)
        #expect(actions.failure != nil)
    }
}
