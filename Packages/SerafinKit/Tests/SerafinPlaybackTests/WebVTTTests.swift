import Foundation
import Testing

@testable import SerafinPlayback

@Suite struct WebVTTTests {
    private func cues(_ text: String) -> [SubtitleCue] {
        WebVTT.cues(in: Data(text.utf8))
    }

    @Test func readsEachCuesTimesAndText() {
        let file = """
            WEBVTT

            1
            00:00:01.000 --> 00:00:02.500
            Hello
            there

            00:03.250 --> 00:04.000 line:90% align:center
            <i>Goodbye</i> &amp; <v Narrator>thanks</v>
            """
        #expect(
            cues(file) == [
                SubtitleCue(start: .seconds(1), end: .milliseconds(2500), text: "Hello\nthere"),
                SubtitleCue(start: .milliseconds(3250), end: .seconds(4), text: "Goodbye & thanks"),
            ])
    }

    @Test func takesAByteOrderMarkAndWindowsLineEnds() {
        let file = "\u{FEFF}WEBVTT\r\n\r\nNOTE made on Windows\r\n\r\n00:00:01.000 --> 00:00:02.000\r\nHello\r\n"
        #expect(cues(file) == [SubtitleCue(start: .seconds(1), end: .seconds(2), text: "Hello")])
    }

    @Test func readsNothingFromAFileThatIsntWebVTT() {
        #expect(cues("1\n00:00:01,000 --> 00:00:02,000\nHello\n").isEmpty)
        #expect(cues("").isEmpty)
    }

    @Test func leavesOutCuesItCantTimeOrThatSayNothing() {
        let file = """
            WEBVTT

            00:00:01.000 --> 00:00:00.500
            Ends before it starts

            00:00:61.000 --> 00:01:02.000
            Sixty-one seconds

            00:00:01.0 --> 00:00:02.000
            Too few digits

            00:00:01.000 --> 00:00:02.000

            00:00:03.000 --> 00:00:04.000
            <b></b>

            00:00:05.000 --> 00:00:06.000
            Kept
            """
        #expect(cues(file) == [SubtitleCue(start: .seconds(5), end: .seconds(6), text: "Kept")])
    }

    @Test func readsTimestampsWithAndWithoutHours() {
        #expect(WebVTT.time("01:02.003") == .milliseconds(62_003))
        #expect(WebVTT.time("1:00:00.000") == .seconds(3600))
        #expect(WebVTT.time("100:00:00.000") == .seconds(360_000))
        #expect(WebVTT.time("00:60.000") == nil)
        #expect(WebVTT.time("00:00:00,000") == nil)
        #expect(WebVTT.time("+1:00.000") == nil)
        #expect(WebVTT.time("12345:00:00.000") == nil)
        #expect(WebVTT.times("00:00:01.000 --> 00:00:02.000 position:10%")?.1 == .seconds(2))
        #expect(WebVTT.times("00:00:01.000 00:00:02.000")?.0 == nil)
    }

    @Test func takesOutTagsAndDecodesCharacterReferences() {
        #expect(WebVTT.plainText("<c.yellow>Hi</c> <00:00:01.000>there") == "Hi there")
        #expect(
            WebVTT.decodingReferences("Tom &amp; Jerry &lt;3 &#233;t&#xE9; &unknown; & alone")
                == "Tom & Jerry <3 \u{E9}t\u{E9} &unknown; & alone")
        #expect(WebVTT.decodingReferences("&#0; &#x110000;") == "&#0; &#x110000;")
    }

    @Test func keepsAtMostTheTextOneSampleHolds() {
        let long = String(repeating: "\u{E9}", count: WebVTT.maximumTextBytes)
        let found = cues("WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n\(long)\n")
        #expect(found.first?.text.utf8.count == WebVTT.maximumTextBytes)
    }
}

@Suite struct TimedTextTests {
    @Test func fillsTheGapsBetweenSubtitles() {
        let cues = [
            SubtitleCue(start: .seconds(1), end: .seconds(2), text: "One"),
            SubtitleCue(start: .seconds(3), end: .seconds(4), text: "Two"),
        ]
        #expect(
            TimedText.stretches(of: cues) == [
                TimedText.Stretch(start: .zero, end: .seconds(1), text: ""),
                TimedText.Stretch(start: .seconds(1), end: .seconds(2), text: "One"),
                TimedText.Stretch(start: .seconds(2), end: .seconds(3), text: ""),
                TimedText.Stretch(start: .seconds(3), end: .seconds(4), text: "Two"),
            ])
    }

    @Test func showsOverlappingSubtitlesTogetherInFileOrder() {
        let cues = [
            SubtitleCue(start: .seconds(1), end: .seconds(2), text: "Bottom"),
            SubtitleCue(start: .zero, end: .seconds(3), text: "Top"),
        ]
        #expect(
            TimedText.stretches(of: cues) == [
                TimedText.Stretch(start: .zero, end: .seconds(1), text: "Top"),
                TimedText.Stretch(start: .seconds(1), end: .seconds(2), text: "Bottom\nTop"),
                TimedText.Stretch(start: .seconds(2), end: .seconds(3), text: "Top"),
            ])
    }

    @Test func joinsSubtitlesThatFollowOnWithTheSameText() {
        let cues = [
            SubtitleCue(start: .zero, end: .seconds(1), text: "Same"),
            SubtitleCue(start: .seconds(1), end: .seconds(2), text: "Same"),
        ]
        #expect(TimedText.stretches(of: cues) == [TimedText.Stretch(start: .zero, end: .seconds(2), text: "Same")])
        #expect(TimedText.stretches(of: []).isEmpty)
    }

    @Test func writesASampleAsItsLengthThenItsText() {
        #expect(TimedText.sample("Hi") == Data([0, 2, 0x48, 0x69]))
        #expect(TimedText.sample("") == Data([0, 0]))
    }
}
