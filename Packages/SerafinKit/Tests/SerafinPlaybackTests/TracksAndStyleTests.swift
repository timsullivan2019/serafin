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
        #expect(PlayerEngine.needsNewStream(toShow: nil, in: burnedIn))
        // The stream carries the English text too, but switching to it would leave the old ones in the picture.
        #expect(PlayerEngine.needsNewStream(toShow: 2, in: burnedIn))

        let text = try plan(.directStream, subtitle: 2)
        #expect(!PlayerEngine.needsNewStream(toShow: nil, in: text))
        #expect(!PlayerEngine.needsNewStream(toShow: 4, in: text))
        #expect(PlayerEngine.needsNewStream(toShow: 5, in: text))
    }

    @Test func askingAgainNamesTheVersionSoTheServerKeepsTheChoice() throws {
        let off = PlayerEngine.optionsAskingAgain(
            PlaybackOptions(subtitleStreamIndex: -1), for: try plan(.transcode, subtitle: 5))
        #expect(off.mediaSourceID == "source-1")
        #expect(off.subtitleStreamIndex == -1)
    }

    @Test func aChoiceCarriesOnToTheNextEpisodeByLanguageAndKind() throws {
        let next = try plan(.directStream, subtitle: 2)
        #expect(PlayerEngine.choice(showing: nil, in: next) == .off)
        #expect(PlayerEngine.choice(showing: 3, in: next) == .language("eng", isForced: false, isHearingImpaired: true))
        #expect(PlayerEngine.streamIndex(for: .off, in: next) == -1)
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
