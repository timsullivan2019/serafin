import Foundation
import SwiftUI
import Testing

@testable import SerafinDesign

@Suite struct NextEpisodeCountdownTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1000)

    @Test func itCountsDownFromItsLength() {
        let countdown = NextEpisodeCountdown(length: .seconds(10), runningFrom: start)
        #expect(countdown.isRunning)
        #expect(countdown.left(at: start) == .seconds(10))
        #expect(countdown.left(at: start + 2.5) == .milliseconds(7500))
        #expect(countdown.left(at: start + 12) == .zero)
        #expect(countdown.fractionPassed(at: start + 2.5) == 0.25)
        #expect(countdown.fractionPassed(at: start + 12) == 1)
    }

    @Test func itSaysWholeSecondsAndWhenTheyChange() {
        let countdown = NextEpisodeCountdown(length: .seconds(10), runningFrom: start)
        #expect(countdown.secondsLeft(at: start) == 10)
        #expect(countdown.secondsLeft(at: start + 2.5) == 8)
        #expect(countdown.secondsLeft(at: start + 9.5) == 1)
        #expect(countdown.secondsLeft(at: start + 10) == 0)
        #expect(countdown.untilNextSecond(at: start + 2.5) == .milliseconds(500))
        #expect(countdown.untilNextSecond(at: start + 3) == .seconds(1))
        #expect(countdown.untilNextSecond(at: start + 10) == .zero)
    }

    @Test func itHoldsWhilePausedAndCarriesOnWhereItStopped() {
        var countdown = NextEpisodeCountdown(length: .seconds(10), runningFrom: start)
        countdown.pause(at: start + 4)
        #expect(!countdown.isRunning)
        #expect(countdown.left(at: start + 100) == .seconds(6))
        countdown.resume(at: start + 100)
        #expect(countdown.left(at: start + 101) == .seconds(5))
        // Pausing or resuming twice changes nothing.
        countdown.resume(at: start + 200)
        #expect(countdown.left(at: start + 101) == .seconds(5))
    }

    @Test func aHeldCountdownStartsWhereItsTold() {
        let countdown = NextEpisodeCountdown(length: .seconds(10), left: .seconds(7), runningFrom: nil)
        #expect(countdown.left(at: start) == .seconds(7))
        #expect(
            NextEpisodeCountdown(length: .seconds(10), left: .seconds(30), runningFrom: nil).left(at: start)
                == .seconds(10))
    }
}

@MainActor @Suite struct NextEpisodeCardTests {
    private let next = MockMedia.episodes[1]

    private func card(secondsLeft: Int?) -> NextEpisodeCard {
        NextEpisodeCard(
            NextEpisodePrompt(card: next, artwork: nil, tint: .gray, secondsLeft: secondsLeft), playNow: {}, cancel: {})
    }

    @Test func voiceOverReadsTheEpisodeAndWhenItPlays() {
        #expect(card(secondsLeft: 8).accessibilityLabel == "Next episode, Gran Dillama, plays in 8 seconds")
        #expect(card(secondsLeft: 1).accessibilityLabel == "Next episode, Gran Dillama, plays in 1 second")
        #expect(card(secondsLeft: nil).accessibilityLabel == "Next episode, Gran Dillama")
    }

    @Test func theTitleLineLeadsWithTheEpisodeCode() {
        #expect(NextEpisodeCard.titleLine(for: next) == "S1 E2 · Gran Dillama")
        #expect(NextEpisodeCard.titleLine(for: MockMedia.movies[1]) == MockMedia.movies[1].title)
    }
}

@Suite struct TransportLayoutTests {
    /// Skip back, play and skip forward as the controls lay them out.
    private let transport = CGSize(width: 336, height: 94)
    /// Their row on an iPhone 17 Pro Max on its side, between the controls' margins.
    private let row = CGRect(x: 78, y: 162, width: 800, height: 94)

    @Test func theTransportStaysInTheMiddleWhereTheCardIsClearOfIt() {
        let layout = TransportLayout(row: row, transport: transport)
        #expect(layout.reserve(for: nil) == 0)
        // Well below the transport, as on an iPad.
        #expect(layout.reserve(for: CGRect(x: 558, y: 600, width: 320, height: 134)) == 0)
        // Beside it with room to spare.
        #expect(layout.reserve(for: CGRect(x: 760, y: 199, width: 118, height: 134)) == 0)
    }

    @Test func theTransportMovesBesideACardThatWouldCoverIt() {
        let layout = TransportLayout(row: row, transport: transport)
        let card = CGRect(x: 558, y: 199, width: 320, height: 134)
        let reserve = layout.reserve(for: card)
        #expect(reserve == row.maxX - card.minX + TransportLayout.gap)
        // In the middle of what's left, it ends well before the card.
        let transportEnd = row.minX + (row.width - reserve) / 2 + transport.width / 2
        #expect(transportEnd + TransportLayout.gap <= card.minX)
    }

    @Test func theCardNarrowsToLeaveTheTransportRoomOnASmallIPhone() {
        // An iPhone SE on its side, 635 points between the margins.
        let small = TransportLayout(row: CGRect(x: 16, y: 141, width: 635, height: 94), transport: transport)
        #expect(small.cardWidth == 635 - 336 - 2 * TransportLayout.gap)
        #expect(TransportLayout(row: row, transport: transport).cardWidth == NextEpisodeCard.maximumWidth)
        // Before anything is measured.
        #expect(TransportLayout().cardWidth == NextEpisodeCard.maximumWidth)
    }
}
