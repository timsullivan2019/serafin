import Foundation
import JellyfinAPI
import Testing

@testable import SerafinCore

/// A client signed in on a stubbed server at `host`.
private func segmentClient(on host: String) throws -> JellyfinClient {
    let configuration = JellyfinClient.Configuration(
        url: try #require(URL(string: "https://\(host)")),
        accessToken: "token-1",
        client: "Serafin",
        deviceName: "iPhone",
        deviceID: "device-1",
        version: "0.1.0"
    )
    return JellyfinClient(configuration: configuration, sessionConfiguration: StubURLProtocol.configuration())
}

/// An ID shaped like Jellyfin's, since the repository asks about nothing else.
private let episodeID = "0b82ed8e9f1daed4e2a44e4d233e29b4"
private let movieID = "f137a2dd21bbc1b99aa5c0f6bf02a805"

@Suite struct PlaybackSegmentTests {
    private func segment(_ kind: PlaybackSegment.Kind, _ start: Int, _ end: Int) -> PlaybackSegment {
        PlaybackSegment(kind: kind, start: .seconds(start), end: .seconds(end))
    }

    @Test func malformedSegmentsAreIgnored() {
        let segments = [
            segment(.intro, 90, 30),  // ends before it starts
            segment(.recap, 40, 40),  // no length
            PlaybackSegment(kind: .preview, start: .seconds(-5), end: .seconds(10)),
            segment(.credits, 1200, 1320),
        ]
        #expect(PlaybackSegment.normalized(segments) == [segment(.credits, 1200, 1320)])
    }

    @Test func segmentsComeInOrderWithoutOverlaps() {
        let segments = [
            segment(.intro, 30, 90),
            segment(.recap, 0, 45),  // overlaps the intro's start
            segment(.advert, 50, 60),  // inside the intro
            segment(.intro, 30, 90),  // a duplicate
            segment(.credits, 1200, 1320),
        ]
        #expect(
            PlaybackSegment.normalized(segments) == [
                segment(.recap, 0, 45), segment(.intro, 45, 90), segment(.credits, 1200, 1320),
            ])
    }

    @Test func theSegmentPlayingRunsFromItsStartToJustBeforeItsEnd() {
        let segments = [segment(.intro, 30, 90), segment(.credits, 1200, 1320)]
        #expect(PlaybackSegment.playing(at: .seconds(29), in: segments) == nil)
        #expect(PlaybackSegment.playing(at: .seconds(30), in: segments) == segments[0])
        #expect(PlaybackSegment.playing(at: .milliseconds(89_999), in: segments) == segments[0])
        #expect(PlaybackSegment.playing(at: .seconds(90), in: segments) == nil)
        #expect(PlaybackSegment.playing(at: .seconds(1250), in: segments) == segments[1])
    }

    @Test func everyKindTheServerMarksIsKept() throws {
        let kinds: [(MediaSegmentType?, PlaybackSegment.Kind)] = [
            (.intro, .intro), (.recap, .recap), (.outro, .credits), (.preview, .preview), (.commercial, .advert),
            (.unknown, .unknown), (nil, .unknown),
        ]
        for (type, kind) in kinds {
            let segment = try #require(
                PlaybackSegment(MediaSegmentDto(endTicks: 900_000_000, startTicks: 300_000_000, type: type)))
            #expect(segment == PlaybackSegment(kind: kind, start: .seconds(30), end: .seconds(90)))
        }
        #expect(PlaybackSegment(MediaSegmentDto(startTicks: 300, type: .intro)) == nil)
    }
}

@Suite struct SegmentRepositoryTests {
    @Test func theServersMediaSegmentsAreAskedForOnceAndComeInOrder() async throws {
        let host = "mediasegments.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/MediaSegments/\(episodeID)", .json(200, try Fixture.json("MediaSegments")))
        let repository = SegmentRepository(client: try segmentClient(on: host))

        let segments = await repository.segments(of: episodeID, isEpisode: true)
        #expect(
            segments == [
                PlaybackSegment(kind: .recap, start: .zero, end: .seconds(20)),
                PlaybackSegment(kind: .intro, start: .seconds(30), end: .seconds(90)),
                PlaybackSegment(kind: .unknown, start: .seconds(600), end: .seconds(630)),
                PlaybackSegment(kind: .credits, start: .seconds(1200), end: .seconds(1320)),
            ])
        // Asked about again, the item isn't asked for again.
        #expect(await repository.segments(of: episodeID, isEpisode: true) == segments)
        let requests = StubURLProtocol.requests(to: "\(host):443", path: "/MediaSegments/\(episodeID)")
        #expect(requests.count == 1)
        #expect(
            requests.first?.queryValues("includeSegmentTypes") == [
                "Intro", "Recap", "Outro", "Preview", "Commercial", "Unknown",
            ])
    }

    @Test func aMovieWithoutSegmentsHasNoneAndNothingFails() async throws {
        let host = "nosegments.example.com"
        StubURLProtocol.stub("\(host):443", path: "/MediaSegments/\(movieID)", .json(404, "{}"))
        let repository = SegmentRepository(client: try segmentClient(on: host))
        #expect(await repository.segments(of: movieID, isEpisode: false) == [])
        // Intro Skipper's endpoints are for episodes, so a movie never asks them.
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Episode/\(movieID)/IntroSkipperSegments").isEmpty)
    }

    @Test func aServerThatListsNoSegmentsIsTakenAtItsWord() async throws {
        // Since Jellyfin 10.10, Intro Skipper puts what it finds in the media segments, which leave out what an
        // administrator hid, so its own endpoints aren't asked behind them.
        let host = "emptysegments.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/MediaSegments/\(episodeID)",
            .json(200, #"{"Items":[],"TotalRecordCount":0,"StartIndex":0}"#))
        let repository = SegmentRepository(client: try segmentClient(on: host))
        #expect(await repository.segments(of: episodeID, isEpisode: true) == [])
        #expect(
            StubURLProtocol.requests(to: "\(host):443", path: "/Episode/\(episodeID)/IntroSkipperSegments").isEmpty)
    }

    @Test func anOlderServerAsksIntroSkipperForAnEpisode() async throws {
        let host = "introskipper-10-10.example.com"
        StubURLProtocol.stub("\(host):443", path: "/MediaSegments/\(episodeID)", .json(404, "{}"))
        StubURLProtocol.stub(
            "\(host):443", path: "/Episode/\(episodeID)/IntroSkipperSegments",
            .json(200, try Fixture.json("IntroSkipperSegments-10.10")))
        let repository = SegmentRepository(client: try segmentClient(on: host))
        #expect(
            await repository.segments(of: episodeID, isEpisode: true) == [
                PlaybackSegment(kind: .intro, start: .milliseconds(31_500), end: .milliseconds(91_250)),
                PlaybackSegment(kind: .credits, start: .seconds(1240), end: .seconds(1320)),
            ])
    }

    @Test func newerPluginBuildsNameTheirTimesDifferentlyAndFindMoreKinds() {
        // Builds for Jellyfin 10.11 and 12.0 answer with Start and End, and with recaps, previews and adverts. A slot
        // the plugin marks not valid, one that ends before it starts, and kinds Serafin doesn't know are left out.
        let data = Data((try? Fixture.json("IntroSkipperSegments-10.11"))?.utf8 ?? "".utf8)
        #expect(
            IntroSkipper.segments(inSegmentsAnswer: data) == [
                PlaybackSegment(kind: .recap, start: .zero, end: .seconds(20)),
                PlaybackSegment(kind: .intro, start: .milliseconds(31_500), end: .milliseconds(91_250)),
                PlaybackSegment(kind: .credits, start: .seconds(1240), end: .seconds(1320)),
            ])
        #expect(IntroSkipper.segments(inSegmentsAnswer: Data("{}".utf8)) == [])
        #expect(IntroSkipper.segments(inSegmentsAnswer: Data("[1, 2]".utf8)) == [])
    }

    @Test func theOriginalPluginOnlyKnowsTheIntro() async throws {
        let host = "introskipper-original.example.com"
        StubURLProtocol.stub("\(host):443", path: "/MediaSegments/\(episodeID)", .json(404, "{}"))
        StubURLProtocol.stub("\(host):443", path: "/Episode/\(episodeID)/IntroSkipperSegments", .json(404, "{}"))
        StubURLProtocol.stub(
            "\(host):443", path: "/Episode/\(episodeID)/IntroTimestamps",
            .json(200, try Fixture.json("IntroTimestamps")))
        let repository = SegmentRepository(client: try segmentClient(on: host))
        #expect(
            await repository.segments(of: episodeID, isEpisode: true) == [
                PlaybackSegment(kind: .intro, start: .milliseconds(31_500), end: .milliseconds(91_250))
            ])
    }

    @Test func aPluginWithNothingForTheEpisodeOrNoPluginAtAllHasNone() async throws {
        let host = "introskipper-nothing.example.com"
        StubURLProtocol.stub("\(host):443", path: "/MediaSegments/\(episodeID)", .json(404, "{}"))
        StubURLProtocol.stub("\(host):443", path: "/Episode/\(episodeID)/IntroSkipperSegments", .json(200, "{}"))
        #expect(
            await SegmentRepository(client: try segmentClient(on: host)).segments(of: episodeID, isEpisode: true) == [])
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Episode/\(episodeID)/IntroTimestamps").isEmpty)

        // A server without the plugin answers 404 everywhere.
        let bare = "no-plugin.example.com"
        StubURLProtocol.stub("\(bare):443", .json(404, "{}"))
        #expect(
            await SegmentRepository(client: try segmentClient(on: bare)).segments(of: episodeID, isEpisode: true) == [])
    }

    @Test func anIDThatIsntJellyfinsIsNeverSent() async throws {
        let host = "badid.example.com"
        let repository = SegmentRepository(client: try segmentClient(on: host))
        #expect(await repository.segments(of: "../Users", isEpisode: true) == [])
        #expect(StubURLProtocol.lastRequest(to: "\(host):443") == nil)
    }
}

@Suite struct PlaybackPreferencesTests {
    @Test func theAccountsAutoplaySettingIsReadAndOnUnlessTurnedOff() {
        let off = PlaybackPreferences(configuration: [
            "EnableNextEpisodeAutoPlay": .bool(false), "SubtitleMode": .string("Always"),
        ])
        #expect(!off.playsNextEpisodeAutomatically)
        #expect(off.languages.subtitleMode == .always)
        #expect(
            PlaybackPreferences(configuration: ["EnableNextEpisodeAutoPlay": .bool(true)]).playsNextEpisodeAutomatically
        )
        #expect(PlaybackPreferences(configuration: [:]).playsNextEpisodeAutomatically)
    }
}
