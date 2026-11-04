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

    @Test func thePreviewIsALittleOverAQuarterOfThePlayerWithinItsBounds() {
        // An iPhone on its side.
        #expect(abs(ScrubberMath.previewWidth(containerWidth: 874, isRegular: false) - 874 * 0.28) < 0.001)
        // Upright, at least 160 points.
        #expect(ScrubberMath.previewWidth(containerWidth: 402, isRegular: false) == ScrubberMath.minimumPreviewWidth)
        // At most 320 points on iPhone, and 480 on iPad.
        #expect(ScrubberMath.previewWidth(containerWidth: 2000, isRegular: false) == 320)
        #expect(ScrubberMath.previewWidth(containerWidth: 2000, isRegular: true) == 480)
        #expect(abs(ScrubberMath.previewWidth(containerWidth: 1376, isRegular: true) - 1376 * 0.28) < 0.001)
        // Never wider than the space inside the margins.
        #expect(
            ScrubberMath.previewWidth(containerWidth: 150, isRegular: false) == 150 - 2 * ScrubberMath.previewMargin)
        #expect(ScrubberMath.previewWidth(containerWidth: 0, isRegular: false) == 0)
    }

    @Test func thePreviewCentresOnTheKnobAboveTheScrubberAndStaysInsideTheEdges() {
        let size = CGSize(width: 200, height: 140)
        let top = 300 - ScrubberMath.previewGap - 140
        #expect(ScrubberMath.previewOrigin(of: size, knob: 400, top: 300, width: 874) == CGPoint(x: 300, y: top))
        #expect(ScrubberMath.previewOrigin(of: size, knob: 20, top: 300, width: 874).x == ScrubberMath.previewMargin)
        #expect(
            ScrubberMath.previewOrigin(of: size, knob: 860, top: 300, width: 874).x
                == 874 - ScrubberMath.previewMargin - 200)
        // A space too narrow for the margins centres it.
        #expect(ScrubberMath.previewOrigin(of: size, knob: 20, top: 300, width: 220).x == 10)
    }

    @Test func thePreviewNamesTheChapterTheKnobIsInside() {
        let chapters = [
            ScrubberChapter(name: "Opening Titles", start: .seconds(10)),
            ScrubberChapter(name: "The Village", start: .seconds(95)),
        ]
        #expect(ScrubberMath.chapter(at: .seconds(5), in: chapters) == nil)
        #expect(ScrubberMath.chapter(at: .seconds(10), in: chapters)?.name == "Opening Titles")
        #expect(ScrubberMath.chapter(at: .milliseconds(94_999), in: chapters)?.name == "Opening Titles")
        #expect(ScrubberMath.chapter(at: .seconds(3_000), in: chapters)?.name == "The Village")
        #expect(ScrubberMath.chapter(at: .seconds(3_000), in: []) == nil)
    }

    @Test func chapterTicksLeaveOutTheEndsAndCrowdedStarts() {
        let chapters = [
            ScrubberChapter(name: "Opening Titles", start: .zero),
            ScrubberChapter(name: "Prologue", start: .seconds(10)),
            ScrubberChapter(name: "The Village", start: .seconds(250)),
            ScrubberChapter(name: "The Road", start: .seconds(255)),
            ScrubberChapter(name: "The Mountain", start: .seconds(500)),
            ScrubberChapter(name: "Closing Credits", start: .seconds(995)),
        ]
        // On a track 300 points wide: none within 6 points of either end or of the tick before.
        #expect(ScrubberMath.tickFractions(for: chapters, in: .seconds(1_000), trackWidth: 300) == [0.25, 0.5])
        #expect(
            ScrubberMath.tickFractions(for: chapters.reversed(), in: .seconds(1_000), trackWidth: 300) == [0.25, 0.5])
        #expect(ScrubberMath.tickFractions(for: chapters, in: .zero, trackWidth: 300).isEmpty)
        #expect(ScrubberMath.tickFractions(for: chapters, in: .seconds(1_000), trackWidth: 10).isEmpty)
    }

    @Test func speedsReadAsMultiples() {
        let english = Locale(identifier: "en_US")
        #expect(PlaybackSpeed.label(1, locale: english) == "1×")
        #expect(PlaybackSpeed.label(1.25, locale: english) == "1.25×")
        #expect(PlaybackSpeed.label(0.75, locale: english) == "0.75×")
        #expect(PlaybackSpeed.choices == [0.75, 1, 1.25, 1.5, 2])
    }
}
