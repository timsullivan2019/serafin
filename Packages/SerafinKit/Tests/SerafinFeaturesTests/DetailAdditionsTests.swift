import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

private func video(width: Int, height: Int, range: VideoRangeType = .sdr) -> MediaStream {
    MediaStream(height: height, index: 0, type: .video, videoRangeType: range, width: width)
}

private func item(_ streams: [MediaStream], defaultAudio: Int? = nil) -> BaseItemDto {
    BaseItemDto(
        id: "aaaa1111", mediaSources: [MediaSourceInfo(defaultAudioStreamIndex: defaultAudio, mediaStreams: streams)])
}

@Suite struct MediaBadgeTests {
    @Test func resolutionCountsWideFilmsAs4K() {
        #expect(MediaBadges.resolution(of: video(width: 3840, height: 2160)) == "4K")
        #expect(MediaBadges.resolution(of: video(width: 3840, height: 1608)) == "4K")
        #expect(MediaBadges.resolution(of: video(width: 1920, height: 800)) == "HD")
        #expect(MediaBadges.resolution(of: video(width: 1280, height: 720)) == "HD")
        #expect(MediaBadges.resolution(of: video(width: 720, height: 480)) == nil)
    }

    @Test func rangeNamesDolbyVisionHDR10PlusAndHDR() {
        #expect(MediaBadges.range(of: video(width: 3840, height: 2160, range: .doviWithHDR10)) == "Dolby Vision")
        #expect(MediaBadges.range(of: video(width: 3840, height: 2160, range: .hdr10Plus)) == "HDR10+")
        #expect(MediaBadges.range(of: video(width: 3840, height: 2160, range: .hdr10)) == "HDR")
        #expect(MediaBadges.range(of: video(width: 3840, height: 2160, range: .hlg)) == "HDR")
        #expect(MediaBadges.range(of: video(width: 1920, height: 1080)) == nil)
    }

    @Test func audioNamesAtmosChannelsAndLossless() {
        let atmos = MediaStream(
            channels: 8, codec: "eac3", index: 1, profile: "Dolby Digital Plus + Dolby Atmos", type: .audio)
        #expect(MediaBadges.audioBadges(of: atmos) == ["Dolby Atmos", "7.1"])
        let trueHD = MediaStream(channels: 6, codec: "truehd", index: 1, type: .audio)
        #expect(MediaBadges.audioBadges(of: trueHD) == ["5.1", "Lossless"])
        let stereo = MediaStream(channels: 2, codec: "aac", index: 1, type: .audio)
        #expect(MediaBadges.audioBadges(of: stereo).isEmpty)
    }

    @Test func subtitlesGiveSDHOrCC() {
        let sdh = MediaStream(index: 2, isHearingImpaired: true, type: .subtitle)
        let plain = MediaStream(index: 3, type: .subtitle)
        let forced = MediaStream(index: 4, isForced: true, type: .subtitle)
        #expect(MediaBadges.accessibility(of: [plain, sdh]) == ["SDH"])
        #expect(MediaBadges.accessibility(of: [plain]) == ["CC"])
        #expect(MediaBadges.accessibility(of: [forced]).isEmpty)
        #expect(MediaBadges.accessibility(of: []).isEmpty)
    }

    @Test func badgesComeInTheAppleTVAppsOrderFromTheDefaultAudio() {
        let streams = [
            video(width: 3840, height: 2160, range: .dovi),
            MediaStream(channels: 2, codec: "aac", index: 1, type: .audio),
            MediaStream(channels: 6, codec: "flac", index: 2, type: .audio),
            MediaStream(index: 3, isHearingImpaired: true, type: .subtitle),
        ]
        #expect(
            MediaBadges.badges(for: item(streams, defaultAudio: 2)) == ["4K", "Dolby Vision", "5.1", "Lossless", "SDH"])
        #expect(MediaBadges.badges(for: BaseItemDto(id: "x")).isEmpty)
    }
}

@Suite struct TrailerAndChapterTests {
    @Test func onlyHTTPSWebTrailersAreKeptAndStoredOnesComeFirst() {
        var source = BaseItemDto(id: "aaaa1111")
        source.remoteTrailers = [
            NamedURL(name: "Trailer", url: "https://www.youtube.com/watch?v=abc"),
            NamedURL(name: "Plain", url: "http://example.com/trailer"),
            NamedURL(name: "Script", url: "javascript:alert(1)"),
            NamedURL(name: "", url: "https://archive.org/details/x"),
        ]
        let local = [BaseItemDto(id: "bbbb2222", name: "Teaser", runTimeTicks: 600_000_000)]
        let trailers = Trailer.trailers(for: source, local: local)
        #expect(trailers.map(\.name) == ["Teaser", "Trailer", "Trailer"])
        guard case .local(let file) = trailers[0].source else {
            Issue.record("The stored trailer isn't first")
            return
        }
        #expect(file.card.kind == .movie)
        #expect(file.card.runtime == .seconds(60))
        guard case .web(let url) = trailers[1].source else {
            Issue.record("The web trailer is missing")
            return
        }
        #expect(url.host() == "www.youtube.com")
    }

    @Test func chaptersKeepTheirOrderStartsAndNames() {
        var source = BaseItemDto(id: "aaaa1111")
        source.chapters = [
            ChapterInfo(name: "Opening", startPositionTicks: 0),
            ChapterInfo(imageTag: "t", name: nil, startPositionTicks: 3_760 * 10_000_000),
        ]
        let chapters = Chapter.chapters(of: source)
        #expect(chapters.map(\.index) == [0, 1])
        #expect(chapters[0].name == "Opening")
        #expect(chapters[1].name.contains("2"))
        #expect(chapters[1].start == .seconds(3_760))
        #expect(chapters[1].startText == "1:02:40")
        #expect(chapters[0].startText == "0:00")
    }

    @Test func aShareLinkOpensTheItemInJellyfinsWebApp() throws {
        var source = BaseItemDto(id: "aaaa1111")
        source.serverID = "ffff9999"
        let item = MediaItem(card: MockMedia.movies[0], source: source)
        let url = try #require(item.webLink(on: URL(string: "https://media.example.com") ?? URL.temporaryDirectory))
        #expect(url.absoluteString == "https://media.example.com/web/#/details?id=aaaa1111&serverId=ffff9999")
        #expect(MediaItem(card: MockMedia.movies[0], source: nil).webLink(on: URL.temporaryDirectory) == nil)
    }
}
