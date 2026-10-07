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
