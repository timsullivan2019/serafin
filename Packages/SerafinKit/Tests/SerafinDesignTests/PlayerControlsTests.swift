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

    @Test func timesShowHoursOnlyWhenThereAreAny() {
        #expect(ScrubberMath.timecode(.seconds(754)) == "12:34")
        #expect(ScrubberMath.timecode(.seconds(5940)) == "1:39:00")
    }

    @Test func speedsReadAsMultiples() {
        let english = Locale(identifier: "en_US")
        #expect(PlaybackSpeed.label(1, locale: english) == "1×")
        #expect(PlaybackSpeed.label(1.25, locale: english) == "1.25×")
        #expect(PlaybackSpeed.label(0.75, locale: english) == "0.75×")
        #expect(PlaybackSpeed.choices == [0.75, 1, 1.25, 1.5, 2])
    }
}
