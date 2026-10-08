import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

/// Settings' subtitle modes, as they pick the subtitles a video starts with.
@Suite struct SubtitleRulesTests {
    private let modes: [SubtitlePlaybackMode] = [.none, .always, .smart, .onlyForced, .default]

    /// What each mode starts `streams` with, for a viewer who reads English, as the modes are listed above.
    private func starts(_ streams: [MediaStream], audio: String?) -> [SubtitleSelection] {
        modes.map { SubtitleRules(mode: $0, languages: ["eng"]).selection(among: streams, audioLanguage: audio) }
    }

    @Test func englishAudioWithEnglishPGS() {
        // The episode from the owner's report: the only subtitles are an English picture track, burned in when shown.
        let streams = [
            MediaStream(codec: "hevc", index: 0, type: .video),
            MediaStream(codec: "aac", index: 1, language: "eng", type: .audio),
            MediaStream(codec: "pgssub", index: 2, isTextSubtitleStream: false, language: "eng", type: .subtitle),
        ]
        // Off, Always, For Other Languages, Forced Only, Automatic.
        #expect(starts(streams, audio: "eng") == [.off, .stream(2), .off, .off, .off])
    }

    @Test func foreignAudioWithEnglishSRT() {
        let streams = [
            MediaStream(codec: "h264", index: 0, type: .video),
            MediaStream(codec: "aac", index: 1, language: "jpn", type: .audio),
            MediaStream(codec: "subrip", index: 2, isTextSubtitleStream: true, language: "eng", type: .subtitle),
            MediaStream(codec: "subrip", index: 3, isTextSubtitleStream: true, language: "jpn", type: .subtitle),
        ]
        #expect(starts(streams, audio: "jpn") == [.off, .stream(2), .stream(2), .off, .stream(2)])
    }

    @Test func aForcedTrackShowsForForcedOnlyAndAutomatic() {
        // Forced English subtitles for the foreign lines of an English film, beside full English ones.
        let streams = [
            MediaStream(codec: "h264", index: 0, type: .video),
            MediaStream(codec: "aac", index: 1, language: "eng", type: .audio),
            MediaStream(
                codec: "subrip", index: 2, isForced: true, isTextSubtitleStream: true, language: "eng", type: .subtitle),
            MediaStream(codec: "pgssub", index: 3, isTextSubtitleStream: false, language: "eng", type: .subtitle),
        ]
        #expect(starts(streams, audio: "eng") == [.off, .stream(3), .off, .stream(2), .stream(2)])
        // Forced subtitles for French audio are in French, so English forced ones don't count for it.
        let french = streams.map { stream in
            var stream = stream
            if stream.type == .audio { stream.language = "fre" }
            return stream
        }
        #expect(
            SubtitleRules(mode: .onlyForced, languages: ["eng"]).selection(among: french, audioLanguage: "fre") == .off)
    }

    @Test func theBestSubtitlesAreFullTextOnesTheFileMarksAsItsDefault() {
        let streams = [
            MediaStream(codec: "pgssub", index: 2, isTextSubtitleStream: false, language: "eng", type: .subtitle),
            MediaStream(
                codec: "subrip", index: 3, isHearingImpaired: true, isTextSubtitleStream: true, language: "eng",
                type: .subtitle),
            MediaStream(codec: "subrip", index: 4, isTextSubtitleStream: true, language: "eng", type: .subtitle),
            MediaStream(
                codec: "subrip", index: 5, isDefault: true, isTextSubtitleStream: true, language: "eng",
                type: .subtitle),
            MediaStream(codec: "ass", index: 6, isTextSubtitleStream: true, language: "eng", type: .subtitle),
        ]
        let always = SubtitleRules(mode: .always, languages: ["eng"])
        // Text the player draws, not SDH, and the file's default among those.
        #expect(always.selection(among: streams, audioLanguage: "eng") == .stream(5))
        // With Closed Captions + SDH on in Accessibility, SDH comes first, and subtitles show even when Off.
        var captions = always
        captions.wantsCaptions = true
        #expect(captions.selection(among: streams, audioLanguage: "eng") == .stream(3))
        captions.mode = .none
        #expect(captions.selection(among: streams, audioLanguage: "eng") == .stream(3))
        // Styled ASS is burned into the picture like an image, so it ranks after plain text.
        let styled = [streams[4], streams[2]]
        #expect(always.selection(among: styled, audioLanguage: "eng") == .stream(4))
    }

    @Test func theAccountsSubtitleLanguageWinsOverTheDevices() {
        let streams = [
            MediaStream(codec: "subrip", index: 2, isTextSubtitleStream: true, language: "eng", type: .subtitle),
            MediaStream(codec: "subrip", index: 3, isTextSubtitleStream: true, language: "ger", type: .subtitle),
        ]
        let german = SubtitleRules(
            preferences: LanguagePreferences(subtitles: "deu", subtitleMode: .always), deviceLanguages: ["en-US"],
            wantsCaptions: false)
        #expect(german.selection(among: streams, audioLanguage: "eng") == .stream(3))
        // With no subtitle language set, the device's languages stand in, not the audio language preferred.
        let unset = SubtitleRules(
            preferences: LanguagePreferences(audio: "jpn", subtitleMode: .always), deviceLanguages: ["de-DE", "en-US"],
            wantsCaptions: false)
        #expect(unset.languages == ["de", "en"])
        #expect(unset.selection(among: streams, audioLanguage: "jpn") == .stream(3))
    }

    @Test func audioWithNoLanguageCountsAsTheViewers() {
        let streams = [
            MediaStream(codec: "subrip", index: 2, isTextSubtitleStream: true, language: "eng", type: .subtitle),
            MediaStream(
                codec: "subrip", index: 3, isForced: true, isTextSubtitleStream: true, language: "und",
                type: .subtitle),
        ]
        #expect(SubtitleRules(mode: .smart, languages: ["eng"]).selection(among: streams, audioLanguage: nil) == .off)
        // Forced subtitles with no language of their own go with any audio.
        #expect(
            SubtitleRules(mode: .default, languages: ["eng"]).selection(among: streams, audioLanguage: "und")
                == .stream(3))
    }

    @Test func languagesCompareWhicheverWayTheyreWritten() {
        #expect(SubtitleRules.language("ger") == "de")
        #expect(SubtitleRules.language("deu") == "de")
        #expect(SubtitleRules.language("de-DE") == "de")
        #expect(SubtitleRules.language("ENG") == "en")
        #expect(SubtitleRules.language("pob") == "pt")
        #expect(SubtitleRules.language("zh-Hans") == "zh")
        #expect(SubtitleRules.language("und") == nil)
        #expect(SubtitleRules.language("") == nil)
        #expect(SubtitleRules.language(nil) == nil)
    }

    @Test func offAndGeneratedSubtitlesAskTheServerForNone() {
        #expect(SubtitleSelection.off.serverIndex == -1)
        #expect(SubtitleSelection.generated.serverIndex == -1)
        #expect(SubtitleSelection.stream(4).serverIndex == 4)
    }
}
