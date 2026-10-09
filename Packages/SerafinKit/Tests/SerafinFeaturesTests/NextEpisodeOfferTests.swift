import Foundation
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

@MainActor @Suite struct NextEpisodeOfferTests {
    private let credits = PlaybackSegment(kind: .credits, start: .seconds(1200), end: .seconds(1320))
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    /// Tells `screen` where an episode of 1,330 seconds with `segments` is.
    private func update(
        _ screen: PlayerScreenModel,
        at seconds: Int,
        segments: [PlaybackSegment]? = nil,
        itemID: String = "ep1",
        hasNextEpisode: Bool = true,
        hasEnded: Bool = false,
        countsDown: Bool = true,
        countdownRuns: Bool = true
    ) {
        screen.updateNextEpisode(
            at: .seconds(seconds), duration: .seconds(1330), segments: segments ?? [credits], itemID: itemID,
            hasNextEpisode: hasNextEpisode, hasEnded: hasEnded, countsDown: countsDown, countdownRuns: countdownRuns,
            now: start)
    }

    @Test func theCardComesAtTheCreditsOrTenSecondsBeforeTheEnd() {
        #expect(PlayerScreenModel.nextEpisodePlace(in: [credits], duration: .seconds(1330)) == .seconds(1200))
        #expect(PlayerScreenModel.nextEpisodePlace(in: [], duration: .seconds(1330)) == .seconds(1320))
        // Other stretches don't count, and an episode too short for the countdown, or of no known length, has none.
        let intro = PlaybackSegment(kind: .intro, start: .seconds(30), end: .seconds(90))
        #expect(PlayerScreenModel.nextEpisodePlace(in: [intro], duration: .seconds(1330)) == .seconds(1320))
        #expect(PlayerScreenModel.nextEpisodePlace(in: [], duration: .seconds(8)) == nil)
        #expect(PlayerScreenModel.nextEpisodePlace(in: [], duration: .zero) == nil)
    }

    @Test func theCardShowsFromItsPlaceThroughTheEnd() {
        let screen = PlayerScreenModel()
        update(screen, at: 1199)
        #expect(screen.nextEpisodeOffer == nil)
        update(screen, at: 1200)
        #expect(screen.nextEpisodeOffer == "ep1")
        #expect(screen.countdown == NextEpisodeCountdown(length: .seconds(10), runningFrom: start))
        #expect(screen.secondsLeft == 10)
        // After the credits and as the episode ends, the same card stays, with its countdown.
        let countdown = screen.countdown
        update(screen, at: 1325)
        update(screen, at: 1330, hasEnded: true)
        #expect(screen.nextEpisodeOffer == "ep1")
        #expect(screen.countdown == countdown)
    }

    @Test func withoutCreditsTheCardComesTenSecondsBeforeTheEnd() {
        let screen = PlayerScreenModel()
        update(screen, at: 1319, segments: [])
        #expect(screen.nextEpisodeOffer == nil)
        update(screen, at: 1320, segments: [])
        #expect(screen.nextEpisodeOffer == "ep1")
    }

    @Test func goingBackBeforeItsPlaceTakesTheCardAway() {
        let screen = PlayerScreenModel()
        update(screen, at: 1205)
        update(screen, at: 600)
        #expect(screen.nextEpisodeOffer == nil)
        #expect(screen.countdown == nil)
        #expect(screen.secondsLeft == nil)
        // Reaching it again starts the countdown afresh.
        update(screen, at: 1200)
        #expect(screen.secondsLeft == 10)
    }

    @Test func aCardPutAwayStaysAwayUntilPlaybackComesBackToIt() {
        let screen = PlayerScreenModel()
        update(screen, at: 1210)
        screen.cancelNextEpisode()
        #expect(screen.nextEpisodeOffer == nil)
        #expect(screen.hasCancelledNextEpisode(after: "ep1"))
        update(screen, at: 1300)
        update(screen, at: 1330, hasEnded: true)
        #expect(screen.nextEpisodeOffer == nil)
        update(screen, at: 1100)
        #expect(!screen.hasCancelledNextEpisode(after: "ep1"))
        update(screen, at: 1200)
        #expect(screen.nextEpisodeOffer == "ep1")
    }

    @Test func theNextEpisodeOffersItsOwnCard() {
        let screen = PlayerScreenModel()
        update(screen, at: 1210)
        screen.cancelNextEpisode()
        update(screen, at: 1210, itemID: "ep2")
        #expect(screen.nextEpisodeOffer == "ep2")
        #expect(!screen.hasCancelledNextEpisode(after: "ep1"))
    }

    @Test func aLastEpisodeOffersNothing() {
        let screen = PlayerScreenModel()
        update(screen, at: 1210, hasNextEpisode: false)
        #expect(screen.nextEpisodeOffer == nil)
        update(screen, at: 1330, hasNextEpisode: false, hasEnded: true)
        #expect(screen.nextEpisodeOffer == nil)
    }

    @Test func theCardWaitsForPlayNowWhenTheAccountDoesntPlayOn() {
        let screen = PlayerScreenModel()
        update(screen, at: 1210, countsDown: false)
        #expect(screen.nextEpisodeOffer == "ep1")
        #expect(screen.countdown == nil)
        #expect(screen.secondsLeft == nil)
    }

    @Test func theCountdownHoldsWhilePlaybackIsPausedOrScrubbedAndCarriesOn() throws {
        let screen = PlayerScreenModel()
        update(screen, at: 1200)
        screen.setCountdownRunning(false, now: start + 3)
        #expect(screen.secondsLeft == 7)
        #expect(try #require(screen.countdown).left(at: start + 60) == .seconds(7))
        screen.setCountdownRunning(true, now: start + 60)
        #expect(try #require(screen.countdown).left(at: start + 62) == .seconds(5))
    }

    @Test func aCardThatComesWhilePausedHoldsItsCountdown() throws {
        let screen = PlayerScreenModel()
        update(screen, at: 1200, countdownRuns: false)
        let countdown = try #require(screen.countdown)
        #expect(!countdown.isRunning)
        #expect(countdown.left(at: start + 60) == .seconds(10))
    }

    @Test func playingNextTakesTheCardAway() {
        let screen = PlayerScreenModel()
        update(screen, at: 1200)
        screen.handOff()
        #expect(screen.nextEpisodeOffer == nil)
        #expect(screen.countdown == nil)
        #expect(!screen.hasCancelledNextEpisode(after: "ep1"))
    }

    @Test func theNextEpisodePlaysWhenTheCountdownEnds() async {
        let screen = PlayerScreenModel(countdownLength: .milliseconds(40))
        screen.updateNextEpisode(
            at: .seconds(1200), duration: .seconds(1330), segments: [credits], itemID: "ep1", hasNextEpisode: true,
            hasEnded: false, countsDown: true, countdownRuns: true)
        var played = false
        await screen.tickCountdown { played = true }
        #expect(played)
    }

    @Test func aHeldCountdownNeverPlays() async {
        let screen = PlayerScreenModel(countdownLength: .milliseconds(40))
        update(screen, at: 1200, countdownRuns: false)
        var played = false
        await screen.tickCountdown { played = true }
        #expect(!played)
        #expect(screen.secondsLeft == 1)
    }
}
