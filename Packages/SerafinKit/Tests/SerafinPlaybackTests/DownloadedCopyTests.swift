import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

@Suite struct DownloadedCopyTests {
    private let movie = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"
    private let file = URL(filePath: "/downloads/6F9619FF-8B86-D011-B42D-00C04FC964FF.mp4")

    /// A movie's version as the server describes it for direct play: the video, English and French audio, English
    /// subtitles inside the file, French subtitles in a separate file, and forced pictures the server would burn in.
    private var source: MediaSourceInfo {
        MediaSourceInfo(
            defaultAudioStreamIndex: 1,
            defaultSubtitleStreamIndex: 3,
            id: movie,
            mediaStreams: [
                MediaStream(codec: "h264", index: 0, isDefault: true, type: .video),
                MediaStream(
                    channelLayout: "stereo", codec: "aac", displayTitle: "English - AAC - Stereo", index: 1,
                    isDefault: true, language: "eng", type: .audio),
                MediaStream(
                    channelLayout: "5.1", codec: "ac3", index: 2, language: "fre", title: "Surround", type: .audio),
                MediaStream(
                    codec: "mov_text", deliveryMethod: .embed, index: 3, isExternal: false, isTextSubtitleStream: true,
                    language: "eng", type: .subtitle),
                MediaStream(
                    codec: "subrip", deliveryMethod: .external,
                    deliveryURL: "/Videos/\(movie)/\(movie)/Subtitles/4/0/Stream.srt?ApiKey=token-1", index: 4,
                    isExternal: true, language: "fre", type: .subtitle),
                MediaStream(
                    codec: "pgssub", deliveryMethod: .encode, index: 5, isForced: true, language: "eng",
                    type: .subtitle),
            ]
        )
    }

    private func copy(tracks: DownloadTracks?) -> DownloadedCopy {
        DownloadedCopy(file: file, mediaSourceID: movie, tracks: tracks) { _ in }
    }

    @Test func aDownloadKeepsTheTracksInsideItsFile() {
        let tracks = DownloadTracks(source)
        #expect(tracks.audio.map(\.index) == [1, 2])
        #expect(tracks.subtitles.map(\.index) == [3])
        #expect(tracks.defaultAudio == 1)
        #expect(tracks.defaultSubtitles == 3)
        #expect(tracks.audio.first?.displayTitle == "English - AAC - Stereo")
        #expect(tracks.audio.last?.title == "Surround")
        #expect(tracks.subtitles.first?.isText == true)
    }

    @Test func subtitlesOutsideTheFileArentWhatItStartsWith() {
        var external = source
        external.defaultSubtitleStreamIndex = 4
        #expect(DownloadTracks(external).defaultSubtitles == nil)
    }

    @Test func noAddressOrTokenIsKept() throws {
        let json = try String(decoding: JSONEncoder().encode(DownloadTracks(source)), as: UTF8.self)
        #expect(!json.contains("token-1"))
        #expect(!json.contains("/Videos"))
    }

    @Test func aCopyPlaysItsFileAsTheOriginalWithNoServer() throws {
        let plan = PlaybackPlan(
            itemID: movie, copy: copy(tracks: DownloadTracks(source)),
            options: PlaybackOptions(startPosition: .seconds(30)))
        #expect(plan.url == file)
        #expect(plan.isDownloaded)
        #expect(plan.method == .directPlay)
        #expect(plan.playSessionID == nil)
        #expect(plan.mediaSourceID == movie)
        #expect(plan.startPosition == .seconds(30))
        #expect(plan.audioStreamIndex == 1)
        #expect(plan.subtitleStreamIndex == 3)
        #expect(plan.audioLanguage == "eng")
        #expect(plan.streams(.audio).map(\.index) == [1, 2])
        #expect(plan.streams(.audio).first?.channelLayout == "stereo")
        let subtitle = try #require(plan.streams(.subtitle).first)
        #expect(plan.streams(.subtitle).count == 1)
        #expect(subtitle.index == 3)
        #expect(subtitle.language == "eng")
        #expect(subtitle.deliveryMethod == .embed)
        #expect(subtitle.isExternal == false)
    }

    @Test func theTracksAskedForStand() {
        let plan = PlaybackPlan(
            itemID: movie, copy: copy(tracks: DownloadTracks(source)),
            options: PlaybackOptions(audioStreamIndex: 2, subtitleStreamIndex: -1))
        #expect(plan.audioStreamIndex == 2)
        #expect(plan.subtitleStreamIndex == -1)
        #expect(plan.audioLanguage == "fre")
    }

    @Test func aCopySavedWithoutItsTracksStillPlays() {
        let plan = PlaybackPlan(itemID: movie, copy: copy(tracks: nil), options: PlaybackOptions())
        #expect(plan.url == file)
        #expect(plan.streams(.audio).isEmpty)
        #expect(plan.streams(.subtitle).isEmpty)
        #expect(plan.audioStreamIndex == nil)
    }

    @Test func everySubtitleInACopyShowsInPlace() {
        let plan = PlaybackPlan(itemID: movie, copy: copy(tracks: DownloadTracks(source)), options: PlaybackOptions())
        #expect(PlayerEngine.carriedSubtitles(of: plan).map(\.index) == [3])
        #expect(!PlayerEngine.needsNewStream(toShow: .stream(3), in: plan))
        #expect(!PlayerEngine.needsNewStream(toShow: .off, in: plan))
        #expect(!PlayerEngine.needsNewStream(toShow: .generated, in: plan))
        #expect(!PlayerEngine.retimesSubtitles(in: plan))
    }

    @Test func aCopyHoldsNoGeneratedSubtitlesBack() {
        let plan = PlaybackPlan(itemID: movie, copy: copy(tracks: DownloadTracks(source)), options: PlaybackOptions())
        // iOS offers only a translation, because the file has English text subtitles. Streaming would load a stream
        // without them to offer the transcription; a copy has no other stream.
        let translationOnly = [LegibleOption(language: "en"), LegibleOption(isGenerated: true, language: "es")]
        #expect(PlayerEngine.withheldGenerated(among: translationOnly, in: plan) == nil)
    }

    @Test func aStreamIsntADownload() throws {
        let streamed = PlaybackPlan(
            itemID: movie, mediaSource: source, url: try #require(URL(string: "https://example.com/Videos/stream")),
            method: .directPlay, playSessionID: "session", startPosition: .zero, audioStreamIndex: 1,
            subtitleStreamIndex: 3)
        #expect(!streamed.isDownloaded)
    }
}

@Suite struct LocalProgressReporterTests {
    /// The positions a reporter keeps, in order.
    private actor Kept {
        var positions: [Duration] = []

        func append(_ position: Duration) {
            positions.append(position)
        }
    }

    @Test func positionsAreKeptOnPausesStopsAndEveryHalfMinute() async {
        let kept = Kept()
        let reporter = LocalProgressReporter { await kept.append($0) }
        await reporter.start(at: .seconds(100), isPaused: false)
        await reporter.progress(at: .seconds(110), isPaused: false)
        await reporter.progress(at: .seconds(131), isPaused: false)
        await reporter.progress(at: .seconds(140), isPaused: true)
        await reporter.progress(at: .seconds(140), isPaused: true)
        await reporter.progress(at: .seconds(400), isPaused: true)
        await reporter.progress(at: .seconds(400), isPaused: false)
        await reporter.stop(at: .seconds(401))
        #expect(await kept.positions == [.seconds(131), .seconds(140), .seconds(400), .seconds(400), .seconds(401)])
    }

    @Test func nothingIsKeptOutsideAPlayback() async {
        let kept = Kept()
        let reporter = LocalProgressReporter { await kept.append($0) }
        await reporter.progress(at: .seconds(100), isPaused: true)
        await reporter.stop(at: .seconds(100))
        await reporter.start(at: .zero, isPaused: false)
        await reporter.stop(at: .seconds(5))
        await reporter.progress(at: .seconds(60), isPaused: true)
        await reporter.stop(at: .seconds(60))
        #expect(await kept.positions == [.seconds(5)])
    }
}
