import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

@Suite struct MediaSegmentsTests {
    private let intro = PlaybackSegment(kind: .intro, start: .seconds(30), end: .seconds(90))
    private let credits = PlaybackSegment(kind: .credits, start: .seconds(1200), end: .seconds(1320))

    @Test func theServersKindsBecomeSkippableStretches() throws {
        let kinds: [(MediaSegmentType, PlaybackSegment.Kind)] = [
            (.intro, .intro), (.recap, .recap), (.outro, .credits), (.preview, .preview), (.commercial, .advert),
        ]
        for (type, kind) in kinds {
            let segment = try #require(
                PlaybackSegment(MediaSegmentDto(endTicks: 900_000_000, startTicks: 300_000_000, type: type)))
            #expect(segment.kind == kind)
            #expect(segment.start == .seconds(30))
            #expect(segment.end == .seconds(90))
        }
    }

    @Test func unknownAndEmptyStretchesAreLeftOut() {
        #expect(PlaybackSegment(MediaSegmentDto(endTicks: 900, startTicks: 0, type: .unknown)) == nil)
        #expect(PlaybackSegment(MediaSegmentDto(endTicks: 300, startTicks: 300, type: .intro)) == nil)
        #expect(PlaybackSegment(MediaSegmentDto(startTicks: 300, type: .intro)) == nil)
    }

    @Test func theOfferRunsFromTheStartUntilTwoSecondsBeforeTheEnd() {
        let segments = [intro, credits]
        #expect(PlaybackSegment.skippable(at: .seconds(29), in: segments) == nil)
        #expect(PlaybackSegment.skippable(at: .seconds(30), in: segments) == intro)
        #expect(PlaybackSegment.skippable(at: .seconds(87), in: segments) == intro)
        #expect(PlaybackSegment.skippable(at: .seconds(88), in: segments) == nil)
        #expect(PlaybackSegment.skippable(at: .seconds(600), in: segments) == nil)
        #expect(PlaybackSegment.skippable(at: .seconds(1250), in: segments) == credits)
        #expect(PlaybackSegment.skippable(at: .seconds(10), in: []) == nil)
    }

    @Test func segmentsAreAskedForAndComeInOrder() async throws {
        let host = "segments.example.com"
        let item = "ep1"
        StubURLProtocol.stub(
            "\(host):443", path: "/MediaSegments/\(item)",
            .json(
                200,
                """
                {"Items":[
                  {"Id":"s2","ItemId":"ep1","Type":"Outro","StartTicks":12000000000,"EndTicks":13200000000},
                  {"Id":"s1","ItemId":"ep1","Type":"Intro","StartTicks":300000000,"EndTicks":900000000},
                  {"Id":"s3","ItemId":"ep1","Type":"Unknown","StartTicks":0,"EndTicks":100}
                ],"TotalRecordCount":3,"StartIndex":0}
                """))
        let segments = try await MediaSegments(client: try stubClient(on: host)).of(item)

        #expect(segments == [intro, credits])
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/MediaSegments/\(item)").first)
        #expect(request.queryValues("includeSegmentTypes") == ["Intro", "Recap", "Outro", "Preview", "Commercial"])
    }

    @Test func aServerWithoutSegmentsSaysSo() async throws {
        let host = "nosegments.example.com"
        StubURLProtocol.stub("\(host):443", path: "/MediaSegments/ep1", .json(404, "{}"))
        await #expect(throws: SerafinError.notFound) {
            try await MediaSegments(client: try stubClient(on: host)).of("ep1")
        }
    }
}
