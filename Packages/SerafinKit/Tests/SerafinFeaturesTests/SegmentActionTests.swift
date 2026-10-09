import Foundation
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

@Suite struct SegmentActionTests {
    private let recap = PlaybackSegment(kind: .recap, start: .zero, end: .seconds(20))
    private let intro = PlaybackSegment(kind: .intro, start: .seconds(30), end: .seconds(90))
    private let unknown = PlaybackSegment(kind: .unknown, start: .seconds(600), end: .seconds(630))
    private let credits = PlaybackSegment(kind: .credits, start: .seconds(1200), end: .seconds(1320))
    private var segments: [PlaybackSegment] { [recap, intro, unknown, credits] }

    private func action(
        at seconds: Int,
        dismissed: PlaybackSegment? = nil,
        skippedBefore: Set<PlaybackSegment> = [],
        automatic: Set<PlaybackSegment.Kind> = [],
        hasNextEpisode: Bool = true
    ) -> SegmentAction {
        SegmentAction.at(
            .seconds(seconds), in: segments, dismissed: dismissed, skippedBefore: skippedBefore, automatic: automatic,
            hasNextEpisode: hasNextEpisode)
    }

    @Test func aMarkedStretchOffersItsPillForAsLongAsItPlays() {
        #expect(action(at: 25) == .none)
        #expect(action(at: 30) == .offer(intro))
        #expect(action(at: 89) == .offer(intro))
        #expect(action(at: 90) == .none)
        #expect(action(at: 610) == .offer(unknown))
    }

    @Test func creditsOfferTheNextEpisodeOrAPillWithoutOne() {
        #expect(action(at: 1200) == .nextEpisode(credits))
        // A film's or a last episode's credits.
        #expect(action(at: 1200, hasNextEpisode: false) == .offer(credits))
        // Settings can't skip credits by themselves.
        #expect(action(at: 1200, automatic: [.intro, .recap, .preview, .advert]) == .nextEpisode(credits))
    }

    @Test func aKindSettingsSkipIsSkippedOnceThenOffered() {
        #expect(action(at: 31, automatic: [.intro]) == .skip(intro))
        #expect(action(at: 31, skippedBefore: [intro], automatic: [.intro]) == .offer(intro))
        // Other kinds still offer their pill, and a stretch of no named kind never skips by itself.
        #expect(action(at: 5, automatic: [.intro]) == .offer(recap))
        #expect(action(at: 610, automatic: [.intro, .recap, .preview, .advert]) == .offer(unknown))
    }

    @Test func aDismissedStretchOffersNothing() {
        #expect(action(at: 40, dismissed: intro) == .none)
        #expect(action(at: 1250, dismissed: credits) == .none)
        #expect(action(at: 5, dismissed: intro) == .offer(recap))
    }

    @Test func skippingLandsHalfASecondBeforeTheEnd() {
        #expect(intro.skipTarget == .milliseconds(89_500))
        let blip = PlaybackSegment(kind: .advert, start: .seconds(10), end: .milliseconds(10_200))
        #expect(blip.skipTarget == .seconds(10))
    }
}

@MainActor @Suite struct SegmentStateTests {
    private let intro = PlaybackSegment(kind: .intro, start: .seconds(30), end: .seconds(90))
    private let credits = PlaybackSegment(kind: .credits, start: .seconds(1200), end: .seconds(1320))

    @Test func anAutomaticSkipHappensOnceWithANotice() {
        let screen = PlayerScreenModel()
        let segments = [intro, credits]
        let skipped = screen.updateSegment(
            at: .seconds(31), in: segments, itemID: "ep1", automatic: [.intro], hasNextEpisode: true)
        #expect(skipped == intro)
        #expect(screen.skippedNotice == .intro)
        #expect(screen.segmentAction == .none)
        // Landing half a second before the end offers nothing more.
        #expect(
            screen.updateSegment(
                at: intro.skipTarget, in: segments, itemID: "ep1", automatic: [.intro], hasNextEpisode: true) == nil)
        #expect(screen.segmentAction == .none)
        // Going back into it offers the pill instead of skipping again.
        _ = screen.updateSegment(
            at: .seconds(100), in: segments, itemID: "ep1", automatic: [.intro], hasNextEpisode: true)
        #expect(
            screen.updateSegment(
                at: .seconds(40), in: segments, itemID: "ep1", automatic: [.intro], hasNextEpisode: true)
                == nil)
        #expect(screen.segmentAction == .offer(intro))
    }

    @Test func aPillPutAwayStaysAwayUntilPlaybackLeavesItsStretch() {
        let screen = PlayerScreenModel()
        _ = screen.updateSegment(at: .seconds(40), in: [intro], itemID: "ep1", automatic: [], hasNextEpisode: false)
        #expect(screen.segmentAction == .offer(intro))
        screen.dismiss(intro)
        _ = screen.updateSegment(at: .seconds(41), in: [intro], itemID: "ep1", automatic: [], hasNextEpisode: false)
        #expect(screen.segmentAction == .none)
        _ = screen.updateSegment(at: .seconds(95), in: [intro], itemID: "ep1", automatic: [], hasNextEpisode: false)
        _ = screen.updateSegment(at: .seconds(35), in: [intro], itemID: "ep1", automatic: [], hasNextEpisode: false)
        #expect(screen.segmentAction == .offer(intro))
    }

    @Test func theNextEpisodeStartsAfresh() {
        let screen = PlayerScreenModel()
        _ = screen.updateSegment(
            at: .seconds(31), in: [intro], itemID: "ep1", automatic: [.intro], hasNextEpisode: true)
        // The next episode has its intro at the same time, and skips it too.
        let skipped = screen.updateSegment(
            at: .seconds(31), in: [intro], itemID: "ep2", automatic: [.intro], hasNextEpisode: true)
        #expect(skipped == intro)
    }

    @Test func theCreditsOfferTheNextEpisodeUntilPutAway() {
        let screen = PlayerScreenModel()
        _ = screen.updateSegment(at: .seconds(1201), in: [credits], itemID: "ep1", automatic: [], hasNextEpisode: true)
        #expect(screen.segmentAction == .nextEpisode(credits))
        screen.dismiss(credits)
        _ = screen.updateSegment(at: .seconds(1210), in: [credits], itemID: "ep1", automatic: [], hasNextEpisode: true)
        #expect(screen.segmentAction == .none)
    }

    @Test func theNoticeGoesAfterAMoment() async {
        let screen = PlayerScreenModel()
        _ = screen.updateSegment(
            at: .seconds(31), in: [intro], itemID: "ep1", automatic: [.intro], hasNextEpisode: true)
        await screen.clearNoticeLater(after: .milliseconds(10))
        #expect(screen.skippedNotice == nil)
    }
}

@Suite struct AutomaticSkipsTests {
    @Test func everythingIsOffUntilTurnedOn() throws {
        let defaults = try #require(UserDefaults(suiteName: "automatic-skips-\(UUID().uuidString)"))
        #expect(AutomaticSkips.kinds(in: defaults).isEmpty)
        defaults.set(true, forKey: try #require(AutomaticSkips.key(for: .intro)))
        defaults.set(true, forKey: try #require(AutomaticSkips.key(for: .advert)))
        #expect(AutomaticSkips.kinds(in: defaults) == [.intro, .advert])
        // Credits follow the account's autoplay setting, and unnamed stretches always ask.
        #expect(AutomaticSkips.key(for: .credits) == nil)
        #expect(AutomaticSkips.key(for: .unknown) == nil)
    }

    @Test func settingsListEachKindThatCanSkipItself() {
        #expect(AutomaticSkips.kinds == [.intro, .recap, .preview, .advert])
        #expect(AutomaticSkips.kinds.map(SkipSegmentsView.title(for:)) == ["Intros", "Recaps", "Previews", "Ads"])
    }
}
