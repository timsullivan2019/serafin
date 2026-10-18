import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

@Suite struct DownloadPlannerTests {
    private let movie = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"
    private let mkv = "6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f"

    private func plan(on host: String, item: String, json: String) async throws -> DownloadPlan {
        StubURLProtocol.stub("\(host):443", path: "/Items/\(item)/PlaybackInfo", .json(200, json))
        return try await DownloadPlanner(client: try stubClient(on: host), userID: "user-1", video: VideoSupport.none)
            .plan(for: item)
    }

    @Test func aFileThePlayerOpensIsDownloadedAsItIs() async throws {
        let host = "download-original.example.com"
        let plan = try await plan(on: host, item: movie, json: try Fixture.json("PlaybackInfoDirectPlay"))

        guard case .original(let original) = plan else {
            Issue.record("Expected the original, got \(plan)")
            return
        }
        #expect(original.mediaSourceID == movie)
        #expect(original.fileExtension == "mp4")
        #expect(original.bytes == 1_789_000_000)
        let url = try #require(URLComponents(url: original.url, resolvingAgainstBaseURL: false))
        #expect(url.path == "/Items/\(movie)/Download")
        #expect(url.query == nil)
    }

    @Test func theServerIsAskedForTheOriginalAloneWithNoBitrateCap() async throws {
        let host = "download-request.example.com"
        _ = try await plan(on: host, item: movie, json: try Fixture.json("PlaybackInfoDirectPlay"))

        let sent = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").first)
        let json = try body(of: sent)
        #expect(json["EnableDirectPlay"] as? Bool == true)
        #expect(json["EnableDirectStream"] as? Bool == false)
        #expect(json["EnableTranscoding"] as? Bool == false)
        #expect(json["MaxStreamingBitrate"] as? Int == DownloadPlanner.bitrate)
    }

    @Test func aFileThePlayerCantOpenNeedsConverting() async throws {
        let plan = try await plan(
            on: "download-mkv.example.com", item: mkv, json: try Fixture.json("PlaybackInfoDirectStream"))
        #expect(plan == .needsConversion)
    }

    @Test func noCompatibleStreamNeedsConverting() async throws {
        let plan = try await plan(
            on: "download-none.example.com", item: movie, json: try Fixture.json("PlaybackInfoNoCompatibleStream"))
        #expect(plan == .needsConversion)
    }

    @Test func aServerThatRefusesPlaybackIsAnError() async throws {
        await #expect(throws: PlaybackError.notAllowed) {
            _ = try await plan(
                on: "download-refused.example.com", item: movie,
                json: #"{"MediaSources":[],"ErrorCode":"NotAllowed"}"#)
        }
    }

    @Test func aStreamFromElsewhereIsNotDownloaded() async throws {
        let json = """
            {"MediaSources":[{"Id":"\(movie)","Protocol":"Http","Container":"mp4","SupportsDirectPlay":true,\
            "IsRemote":true}],"PlaySessionId":"s"}
            """
        let plan = try await plan(on: "download-remote.example.com", item: movie, json: json)
        #expect(plan == .needsConversion)
    }

    @Test func theFileKeepsItsOwnExtension() async throws {
        let json = """
            {"MediaSources":[{"Id":"\(movie)","Protocol":"File","Container":"mov,mp4,m4a,3gp,3g2,mj2",\
            "Path":"D:\\\\Films\\\\Spring.mov","SupportsDirectPlay":true,"IsRemote":false}],"PlaySessionId":"s"}
            """
        guard case .original(let original) = try await plan(on: "download-mov.example.com", item: movie, json: json)
        else {
            Issue.record("Expected the original")
            return
        }
        #expect(original.fileExtension == "mov")
    }

    @Test func aContainerListPicksMP4() throws {
        var source = MediaSourceInfo()
        source.container = "mov,mp4,m4a,3gp,3g2,mj2"
        #expect(DownloadPlanner.fileExtension(for: source) == "mp4")
        source.container = "mkv"
        #expect(DownloadPlanner.fileExtension(for: source) == nil)
    }
}
