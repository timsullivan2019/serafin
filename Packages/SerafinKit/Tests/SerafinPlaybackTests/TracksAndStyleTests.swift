import AVFoundation
import Foundation
import JellyfinAPI
import Testing

@testable import SerafinPlayback

@Suite struct CarriedTracksTests {
    /// A version with two audio tracks and every kind of subtitle: an MP4 text track, an SRT inside the file, an SRT
    /// beside it, and an image subtitle.
    private let source = MediaSourceInfo(
        id: "source-1",
        mediaStreams: [
            MediaStream(index: 0, type: .video),
            MediaStream(index: 1, language: "eng", type: .audio),
            MediaStream(index: 2, language: "fre", type: .audio),
            MediaStream(codec: "mov_text", deliveryMethod: .embed, index: 3, type: .subtitle),
            MediaStream(codec: "subrip", deliveryMethod: .hls, index: 4, type: .subtitle),
            MediaStream(codec: "subrip", deliveryMethod: .hls, index: 5, isExternal: true, type: .subtitle),
            MediaStream(codec: "pgssub", deliveryMethod: .encode, index: 6, type: .subtitle),
        ]
    )

    private func plan(_ method: PlaybackPlan.Method) throws -> PlaybackPlan {
        PlaybackPlan(
            itemID: "item-1",
            mediaSource: source,
            url: try #require(URL(string: "https://example.com/stream")),
            method: method,
            playSessionID: nil,
            startPosition: .zero,
            audioStreamIndex: 2,
            subtitleStreamIndex: 4
        )
    }

    @Test func theServersStreamCarriesEveryTextSubtitleItSendsAsWebVTT() throws {
        for method in [PlaybackPlan.Method.directStream, .transcode] {
            #expect(PlayerEngine.carriedSubtitles(of: try plan(method)).map(\.index) == [4, 5])
        }
    }

    @Test func theOriginalFileCarriesItsOwnTracksButNotPicturesOrFilesBesideIt() throws {
        #expect(PlayerEngine.carriedSubtitles(of: try plan(.directPlay)).map(\.index) == [3, 4])
    }

    @Test func theFilesOwnAudioTracksAreCarried() throws {
        #expect(PlayerEngine.carriedAudio(of: try plan(.directPlay)).map(\.index) == [1, 2])
    }
}

@Suite struct SubtitleChoiceTests {
    /// English subtitles the server sends in its stream, English SDH, French, and an English image subtitle the server
    /// burns into the picture.
    private let source = MediaSourceInfo(
        id: "source-1",
        mediaStreams: [
            MediaStream(index: 0, type: .video),
            MediaStream(index: 1, language: "eng", type: .audio),
            MediaStream(codec: "subrip", deliveryMethod: .hls, index: 2, language: "eng", type: .subtitle),
            MediaStream(
                codec: "subrip", deliveryMethod: .hls, index: 3, isHearingImpaired: true, language: "eng",
                type: .subtitle),
            MediaStream(codec: "subrip", deliveryMethod: .hls, index: 4, language: "fre", type: .subtitle),
            MediaStream(codec: "pgssub", deliveryMethod: .encode, index: 5, language: "eng", type: .subtitle),
        ]
    )

    private func plan(_ method: PlaybackPlan.Method, subtitle: Int?, source: MediaSourceInfo? = nil) throws
        -> PlaybackPlan
    {
        PlaybackPlan(
            itemID: "item-1",
            mediaSource: source ?? self.source,
            url: try #require(URL(string: "https://example.com/stream")),
            method: method,
            playSessionID: nil,
            startPosition: .zero,
            audioStreamIndex: 1,
            subtitleStreamIndex: subtitle
        )
    }

    @Test func burnedInSubtitlesOnlyChangeWithANewStream() throws {
        let burnedIn = try plan(.transcode, subtitle: 5)
        #expect(PlayerEngine.needsNewStream(toShow: .off, in: burnedIn))
        // The stream carries the English text too, but switching to it would leave the old ones in the picture.
        #expect(PlayerEngine.needsNewStream(toShow: .stream(2), in: burnedIn))
        #expect(PlayerEngine.needsNewStream(toShow: .generated, in: burnedIn))

        let text = try plan(.directStream, subtitle: 2)
        #expect(!PlayerEngine.needsNewStream(toShow: .off, in: text))
        #expect(!PlayerEngine.needsNewStream(toShow: .stream(4), in: text))
        #expect(!PlayerEngine.needsNewStream(toShow: .generated, in: text))
        #expect(PlayerEngine.needsNewStream(toShow: .stream(5), in: text))
    }

    @Test func askingAgainNamesTheVersionSoTheServerKeepsTheChoice() throws {
        let off = PlayerEngine.optionsAskingAgain(
            PlaybackOptions(subtitleStreamIndex: -1), for: try plan(.transcode, subtitle: 5))
        #expect(off.mediaSourceID == "source-1")
        #expect(off.subtitleStreamIndex == -1)
    }

    @Test func aChoiceCarriesOnToTheNextEpisodeByLanguageAndKind() throws {
        let next = try plan(.directStream, subtitle: 2)
        #expect(PlayerEngine.choice(for: .off, in: next) == .off)
        #expect(PlayerEngine.choice(for: .generated, in: next) == .generated)
        #expect(
            PlayerEngine.choice(for: .stream(3), in: next) == .language("eng", isForced: false, isHearingImpaired: true)
        )
        #expect(PlayerEngine.streamIndex(for: .off, in: next) == -1)
        #expect(PlayerEngine.streamIndex(for: .generated, in: next) == -1)
        #expect(
            PlayerEngine.streamIndex(for: .language("eng", isForced: false, isHearingImpaired: true), in: next) == 3)
        #expect(
            PlayerEngine.streamIndex(for: .language("fre", isForced: false, isHearingImpaired: true), in: next) == 4)
        // No German, so Settings' default stands.
        #expect(
            PlayerEngine.streamIndex(for: .language("ger", isForced: false, isHearingImpaired: false), in: next) == nil)
    }

    @Test func onlyATextTrackInsideAnMP4PlaysFromTheOriginalFile() throws {
        let file = MediaSourceInfo(
            id: "source-2",
            mediaStreams: [
                MediaStream(codec: "mov_text", index: 2, type: .subtitle),
                MediaStream(codec: "subrip", index: 3, isExternal: true, type: .subtitle),
            ]
        )
        let plan = try plan(.directPlay, subtitle: nil, source: file)
        #expect(PlayerEngine.allowsDirectPlay(showing: -1, in: plan))
        #expect(PlayerEngine.allowsDirectPlay(showing: 2, in: plan))
        #expect(!PlayerEngine.allowsDirectPlay(showing: 3, in: plan))
    }
}

@Suite struct LegibleSelectionTests {
    /// English audio; English PGS the server burns in; English and French text it sends in its HLS stream.
    private let source = MediaSourceInfo(
        id: "source-1",
        mediaStreams: [
            MediaStream(index: 0, type: .video),
            MediaStream(index: 1, language: "eng", type: .audio),
            MediaStream(codec: "pgssub", deliveryMethod: .encode, index: 2, language: "eng", type: .subtitle),
            MediaStream(codec: "subrip", deliveryMethod: .hls, index: 3, language: "eng", type: .subtitle),
            MediaStream(codec: "subrip", deliveryMethod: .hls, index: 4, language: "fre", type: .subtitle),
        ]
    )

    private func plan(subtitle: Int?) throws -> PlaybackPlan {
        PlaybackPlan(
            itemID: "item-1", mediaSource: source, url: try #require(URL(string: "https://example.com/master.m3u8")),
            method: .directStream, playSessionID: nil, startPosition: .zero, audioStreamIndex: 1,
            subtitleStreamIndex: subtitle)
    }

    /// The legible options AVPlayer lists for such a stream on iOS 27: the closed captions it looks for in the video,
    /// the two text renditions, and the subtitles iOS generates from the English audio.
    private let options = [
        LegibleOption(isClosedCaptions: true),
        LegibleOption(language: "en"),
        LegibleOption(language: "fr"),
        LegibleOption(isGenerated: true, language: "en"),
    ]

    @Test func textSubtitlesSelectTheirOwnOptionNotTheCaptionsOrTheGeneratedOnes() throws {
        let text = try plan(subtitle: 3)
        #expect(PlayerEngine.legiblePosition(for: .stream(3), in: text, among: options) == (1, .stream(3)))
        #expect(PlayerEngine.legiblePosition(for: .stream(4), in: text, among: options) == (2, .stream(4)))
        // Without iOS's extra options the positions are the plain ones.
        let plain = [LegibleOption(language: "en"), LegibleOption(language: "fr")]
        #expect(PlayerEngine.legiblePosition(for: .stream(4), in: text, among: plain) == (1, .stream(4)))
        // When the options don't line up with the server's streams, nothing is guessed and nothing shows.
        #expect(PlayerEngine.legiblePosition(for: .stream(4), in: text, among: [plain[0]]) == (nil, .off))
    }

    @Test func burnedInSubtitlesAndOffSelectNoOptionAtAll() throws {
        let burnedIn = try plan(subtitle: 2)
        #expect(PlayerEngine.legiblePosition(for: .stream(2), in: burnedIn, among: options) == (nil, .stream(2)))
        #expect(PlayerEngine.legiblePosition(for: .off, in: burnedIn, among: options) == (nil, .off))
    }

    @Test func generatedSubtitlesAreTheOnesForTheAudioPlaying() throws {
        let off = try plan(subtitle: -1)
        let spanishToo = options + [LegibleOption(isGenerated: true, language: "es")]
        #expect(PlayerEngine.legiblePosition(for: .generated, in: off, among: spanishToo) == (3, .generated))
        #expect(PlayerEngine.generatedPosition(among: spanishToo, audioLanguage: "spa") == 4)
        // Ones that can't show anything now don't count, and without any, generated subtitles can't show.
        let unselectable = [LegibleOption(isGenerated: true, language: "en", isSelectable: false)]
        #expect(PlayerEngine.generatedPosition(among: unselectable, audioLanguage: "eng") == nil)
        #expect(PlayerEngine.legiblePosition(for: .generated, in: off, among: unselectable) == (nil, .off))
    }

    @Test func aVideoStartsWithWhatSettingsSayUnlessPlayingOnFromAPick() throws {
        // The server remembered English PGS from an earlier playback, but Settings say Off.
        let remembered = try plan(subtitle: 2)
        let off = SubtitleRules(mode: .none, languages: ["eng"])
        #expect(PlayerEngine.startingSubtitles(carrying: nil, rules: off, in: remembered) == .off)
        let always = SubtitleRules(mode: .always, languages: ["eng"])
        #expect(PlayerEngine.startingSubtitles(carrying: nil, rules: always, in: try plan(subtitle: -1)) == .stream(3))
        // A pick carried on from the episode before wins.
        let french = SubtitleChoice.language("fre", isForced: false, isHearingImpaired: false)
        #expect(PlayerEngine.startingSubtitles(carrying: french, rules: off, in: remembered) == .stream(4))
        #expect(PlayerEngine.startingSubtitles(carrying: .generated, rules: off, in: remembered) == .generated)
        #expect(PlayerEngine.startingSubtitles(carrying: .off, rules: always, in: remembered) == .off)
        // A language this episode lacks falls back to Settings.
        let german = SubtitleChoice.language("ger", isForced: false, isHearingImpaired: false)
        #expect(PlayerEngine.startingSubtitles(carrying: german, rules: always, in: remembered) == .stream(3))
        // Without the account's settings, the server's choice stands.
        #expect(PlayerEngine.startingSubtitles(carrying: nil, rules: nil, in: remembered) == .stream(2))
        #expect(PlayerEngine.startingSubtitles(carrying: nil, rules: nil, in: try plan(subtitle: nil)) == .off)
    }
}

@Suite struct SubtitleDiagnosticsTests {
    @Test func theLogListsSubtitleRenditionsWithoutTheirAddresses() {
        let playlist = """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English",DEFAULT=YES,AUTOSELECT=YES,FORCED=NO,LANGUAGE="eng",URI="https://example.com/sub.m3u8?api_key=secret"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Stereo",URI="https://example.com/audio.m3u8?api_key=secret"
            #EXT-X-STREAM-INF:BANDWIDTH=1000000,SUBTITLES="subs"
            main.m3u8?api_key=secret
            """
        let renditions = SubtitleDiagnostics.subtitleRenditions(inPlaylist: playlist)
        #expect(renditions.count == 1)
        #expect(renditions[0].contains("LANGUAGE=\"eng\""))
        #expect(renditions[0].contains("DEFAULT=YES"))
        #expect(!renditions[0].contains("secret"))
        // Jellyfin doesn't say whether its video carries closed captions.
        #expect(SubtitleDiagnostics.closedCaptions(inPlaylist: playlist) == ["CLOSED-CAPTIONS absent"])
        #expect(
            SubtitleDiagnostics.closedCaptions(
                inPlaylist: "#EXT-X-STREAM-INF:BANDWIDTH=1,CLOSED-CAPTIONS=NONE\nmain.m3u8")
                == ["CLOSED-CAPTIONS=NONE"])
    }

    @Test func theLogSaysWhenSubtitlesAreBurnedIn() throws {
        let source = MediaSourceInfo(
            id: "source-1",
            mediaStreams: [
                MediaStream(codec: "pgssub", deliveryMethod: .encode, index: 3, language: "eng", type: .subtitle),
                MediaStream(codec: "subrip", deliveryMethod: .hls, index: 4, language: "eng", type: .subtitle),
            ]
        )
        let plan = PlaybackPlan(
            itemID: "item-1", mediaSource: source, url: try #require(URL(string: "https://example.com/master.m3u8")),
            method: .transcode, playSessionID: nil, startPosition: .zero, audioStreamIndex: nil, subtitleStreamIndex: 3)
        let line = SubtitleDiagnostics.describe(plan)
        #expect(line.contains("burnIn=true"))
        #expect(line.contains("#3 pgssub eng Encode"))
        #expect(line.contains("#4 subrip eng Hls"))
    }
}

@Suite struct SubtitleStyleTests {
    @Test func theStandardSizeLeavesTheSystemsStyleAlone() {
        #expect(SubtitleStyle.standard.textMarkupAttributes.isEmpty)
        #expect(SubtitleStyle.standard.textStyleRules.isEmpty)
    }

    @Test(arguments: [(SubtitleStyle.Size.small, 75), (.large, 133), (.extraLarge, 167)])
    func otherSizesScaleTheSystemsSize(size: SubtitleStyle.Size, percent: Int) {
        let attributes = SubtitleStyle(size: size).textMarkupAttributes
        #expect(attributes[kCMTextMarkupAttribute_RelativeFontSize as String] as? Int == percent)
        #expect(attributes.count == 1)
        #expect(SubtitleStyle(size: size).textStyleRules.count == 1)
    }
}

#if canImport(UIKit)
    import MediaPlayer
    import UIKit

    @Suite struct NowPlayingDetailsTests {
        @Test func theLockScreenGetsTheTitleShowAndArtwork() throws {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { context in
                UIColor.purple.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
            }
            let jpeg = try #require(image.jpegData(compressionQuality: 0.8))
            let info = NowPlayingDetails(
                title: "A Scandal in Bohemia", subtitle: "Sherlock Holmes · S1 E1", artwork: jpeg
            )
            .nowPlayingInfo
            #expect(info[MPMediaItemPropertyTitle] as? String == "A Scandal in Bohemia")
            #expect(info[MPMediaItemPropertyArtist] as? String == "Sherlock Holmes · S1 E1")
            #expect(info[MPMediaItemPropertyArtwork] is MPMediaItemArtwork)
            #expect(info[MPNowPlayingInfoPropertyMediaType] as? UInt == MPNowPlayingInfoMediaType.video.rawValue)
        }

        @Test func theArtworkCanBeDrawnAwayFromTheMainThread() async throws {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 9)).image { context in
                UIColor.purple.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
            }
            let jpeg = try #require(image.jpegData(compressionQuality: 0.8))
            let info = NowPlayingDetails(title: "Metropolis", subtitle: nil, artwork: jpeg).nowPlayingInfo
            nonisolated(unsafe) let artwork = try #require(info[MPMediaItemPropertyArtwork] as? MPMediaItemArtwork)
            // The system asks for the artwork on a queue of its own, as when Picture in Picture hands back the picture.
            let drawn = await Task.detached { artwork.image(at: CGSize(width: 16, height: 9)) != nil }.value
            #expect(drawn)
        }

        @Test func aMovieWithoutArtworkStillHasItsTitle() {
            let info = NowPlayingDetails(title: "Metropolis", subtitle: nil, artwork: nil).nowPlayingInfo
            #expect(info[MPMediaItemPropertyTitle] as? String == "Metropolis")
            #expect(info[MPMediaItemPropertyArtist] == nil)
            #expect(info[MPMediaItemPropertyArtwork] == nil)
        }
    }
#endif
