import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

@Suite struct DownloadPlannerTests {
    private let movie = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"
    private let mkv = "6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f"

    /// Plans `item`'s download on `host`, which answers the server's questions about it with `json`, in order.
    private func plan(on host: String, item: String, json: String...) async throws -> DownloadPlan {
        StubURLProtocol.stubSequence("\(host):443", path: "/Items/\(item)/PlaybackInfo", json.map { .json(200, $0) })
        return try await DownloadPlanner(client: try stubClient(on: host), userID: "user-1", video: VideoSupport.none)
            .plan(for: item)
    }

    /// An MP4 with English subtitles inside it and Spanish ones in a file of their own, as the server answers when it
    /// judges the movie with the subtitles `subtitles`, or -1 for none.
    private func movieWithSubtitles(directPlays: Bool, subtitles: Int) -> String {
        """
        {"MediaSources":[{"Id":"\(movie)","Protocol":"File","Container":"mov,mp4,m4a,3gp,3g2,mj2","IsRemote":false,\
        "SupportsDirectPlay":\(directPlays),"DefaultAudioStreamIndex":1,"DefaultSubtitleStreamIndex":\(subtitles),\
        "MediaStreams":[{"Codec":"h264","Type":"Video","Index":0},{"Codec":"aac","Type":"Audio","Index":1},\
        {"Codec":"mov_text","Language":"eng","Type":"Subtitle","Index":2,"IsExternal":false},\
        {"Codec":"subrip","Language":"spa","Type":"Subtitle","Index":3,"IsExternal":true}]}],"PlaySessionId":"s"}
        """
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
        // The file's own audio and text subtitles go with it, for the player with no server.
        #expect(original.tracks.audio.map(\.index) == [1, 2])
        #expect(original.tracks.subtitles.map(\.index) == [3])
        #expect(original.tracks.defaultAudio == 1)
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

    @Test func subtitlesOutsideTheFileDontStopADownload() async throws {
        let host = "download-subtitles.example.com"
        // The account's Spanish subtitles are in a file of their own, so the server turns direct play down with them.
        let plan = try await plan(
            on: host, item: movie, json: movieWithSubtitles(directPlays: false, subtitles: 3),
            movieWithSubtitles(directPlays: true, subtitles: -1))

        guard case .original(let original) = plan else {
            Issue.record("Expected the original, got \(plan)")
            return
        }
        #expect(original.mediaSourceID == movie)
        #expect(original.tracks.subtitles.map(\.index) == [2])
        #expect(original.tracks.defaultSubtitles == nil)
        let sent = try StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").map(body)
        #expect(sent.count == 2)
        #expect(sent.first?["SubtitleStreamIndex"] == nil)
        #expect(sent.last?["SubtitleStreamIndex"] as? Int == -1)
        #expect(sent.last?["MediaSourceId"] as? String == movie)
    }

    @Test func aVersionTurnedDownWithNoSubtitlesIsAskedAboutOnce() async throws {
        let host = "download-subtitles-off.example.com"
        let plan = try await plan(on: host, item: movie, json: movieWithSubtitles(directPlays: false, subtitles: -1))
        #expect(plan == .needsConversion)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").count == 1)
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
