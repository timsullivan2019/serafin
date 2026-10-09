import Foundation
import Testing

@testable import SerafinDesign

@Suite struct PlayerControlsTests {
    @Test func theScrubberMapsPositionsToFractionsAndBack() {
        let length = Duration.seconds(5400)
        #expect(ScrubberMath.fraction(of: .seconds(1350), in: length) == 0.25)
        #expect(ScrubberMath.fraction(of: .seconds(9000), in: length) == 1)
        #expect(ScrubberMath.fraction(of: .seconds(10), in: .zero) == 0)
        #expect(ScrubberMath.position(at: 0.25, in: length) == .seconds(1350))
        #expect(ScrubberMath.position(at: -1, in: length) == .zero)
        #expect(ScrubberMath.position(at: 2, in: length) == length)
    }

    @Test func aSeekArrivesWithinHalfASecondOrAThousandthOfALongVideo() {
        let episode = Duration.seconds(1320)
        #expect(ScrubberMath.hasArrived(at: 0.5, from: .seconds(660), in: episode))
        #expect(ScrubberMath.hasArrived(at: 0.5, from: .milliseconds(660_400), in: episode))
        #expect(!ScrubberMath.hasArrived(at: 0.5, from: .seconds(650), in: episode))
        // Three hours: within 10.8 seconds.
        let film = Duration.seconds(10_800)
        #expect(ScrubberMath.hasArrived(at: 0.5, from: .seconds(5_410), in: film))
        #expect(!ScrubberMath.hasArrived(at: 0.5, from: .seconds(5_420), in: film))
    }

    @Test func timesShowHoursOnlyWhenThereAreAny() {
        #expect(ScrubberMath.timecode(.seconds(754)) == "12:34")
        #expect(ScrubberMath.timecode(.seconds(5940)) == "1:39:00")
    }

    @Test func scrubbingTicksAtEachTenthAndBothEnds() {
        #expect(!ScrubberMath.passesDetent(from: 0.12, to: 0.15, start: 0.5))
        #expect(ScrubberMath.passesDetent(from: 0.18, to: 0.21, start: 0.5))
        #expect(ScrubberMath.passesDetent(from: 0.21, to: 0.18, start: 0.5))
        #expect(ScrubberMath.passesDetent(from: 0.95, to: 1, start: 0.5))
        #expect(ScrubberMath.passesDetent(from: 0.05, to: 0, start: 0.5))
        #expect(!ScrubberMath.passesDetent(from: 0.3, to: 0.3, start: 0.3))
    }

    @Test func scrubbingTicksWhereTheDragBegan() {
        #expect(ScrubberMath.passesDetent(from: 0.41, to: 0.45, start: 0.43))
        #expect(ScrubberMath.passesDetent(from: 0.45, to: 0.41, start: 0.43))
        #expect(ScrubberMath.passesDetent(from: 0.42, to: 0.43, start: 0.43))
        #expect(!ScrubberMath.passesDetent(from: 0.44, to: 0.46, start: 0.43))
    }

    @Test func speedsReadAsMultiples() {
        let english = Locale(identifier: "en_US")
        #expect(PlaybackSpeed.label(1, locale: english) == "1×")
        #expect(PlaybackSpeed.label(1.25, locale: english) == "1.25×")
        #expect(PlaybackSpeed.label(0.75, locale: english) == "0.75×")
        #expect(PlaybackSpeed.choices == [0.75, 1, 1.25, 1.5, 2])
    }
}
