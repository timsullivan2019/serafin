import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

/// A client signed in as `user-1` with `token-1`, talking to a stubbed server at `host`.
func stubClient(on host: String) throws -> JellyfinClient {
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

/// The JSON body of a request the stub received.
func body(of received: StubURLProtocol.Received) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: received.body) as? [String: Any])
}

@Suite struct PlaybackNegotiatorTests {
    private let movie = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"

    private func negotiate(
        on host: String,
        item: String,
        fixture: String,
        options: PlaybackOptions = PlaybackOptions()
    ) async throws -> PlaybackPlan {
        StubURLProtocol.stub("\(host):443", path: "/Items/\(item)/PlaybackInfo", .json(200, try Fixture.json(fixture)))
        return try await PlaybackNegotiator(client: try stubClient(on: host), userID: "user-1")
            .plan(for: item, options: options)
    }

    @Test func aFileAVPlayerCanReadPlaysDirectly() async throws {
        let host = "direct-play.example.com"
        let plan = try await negotiate(on: host, item: movie, fixture: "PlaybackInfoDirectPlay")

        #expect(plan.method == .directPlay)
        #expect(plan.playSessionID == "session-direct-play")
        #expect(plan.mediaSourceID == movie)
        #expect(plan.audioStreamIndex == 1)
        #expect(plan.streams(.audio).count == 2)
        let url = try #require(URLComponents(url: plan.url, resolvingAgainstBaseURL: false))
        #expect(url.path == "/Videos/\(movie)/stream")
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["static"] == "true")
        #expect(query["mediaSourceId"] == movie)
        #expect(query["deviceId"] == "device-1")
        #expect(query["tag"] == "3e0b0d2f8c1a9e7d")
        #expect(query["ApiKey"] == "token-1")
    }

    @Test func aFileInAnotherContainerIsRepackagedAsHLS() async throws {
        let host = "direct-stream.example.com"
        let item = "6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f"
        let plan = try await negotiate(on: host, item: item, fixture: "PlaybackInfoDirectStream")

        #expect(plan.method == .directStream)
        #expect(plan.url.host() == host)
        #expect(plan.url.path() == "/videos/\(item)/master.m3u8")
        #expect(plan.url.query()?.contains("VideoCodec=h264") == true)
        #expect(plan.playSessionID == "session-direct-stream")
    }

    @Test(arguments: [
        // The container alone: the server copies the video and audio into HLS.
        ("ContainerNotSupported", "h264", "aac", true),
        // HEVC without Apple's codec tag: the server rewrites the tag as it copies.
        ("ContainerNotSupported,VideoCodecTagNotSupported", "hevc,h264", "aac", true),
        // Dolby Vision the player can't show: the server has to change the video.
        ("ContainerNotSupported,VideoRangeTypeNotSupported", "hevc,h264", "aac", false),
        // Audio the stream doesn't carry: the server converts it.
        ("ContainerNotSupported", "h264", "ac3,eac3", false),
        // No reasons given: nothing to say it only repackages.
        ("", "h264", "aac", false),
    ])
    func repackagingIsToldApartFromConverting(reasons: String, videoCodecs: String, audioCodecs: String, copies: Bool)
        throws
    {
        let response = try JSONDecoder().decode(
            PlaybackInfoResponse.self,
            from: Data(try Fixture.json("PlaybackInfoDirectStream").utf8)
        )
        let source = try #require(response.mediaSources?.first)
        let url =
            "/videos/6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f/master.m3u8?VideoCodec=\(videoCodecs)&AudioCodec=\(audioCodecs)"
            + "&AudioStreamIndex=1&api_key=token-1&TranscodeReasons=\(reasons)"
        #expect(PlaybackNegotiator.copiesVideoAndAudio(url, from: source, audioStreamIndex: nil) == copies)
    }

    @Test(arguments: [
        // A text subtitle the server converts and adds to the HLS stream: the video is still copied.
        ("SubtitleCodecNotSupported", "&SubtitleMethod=Hls", true),
        ("ContainerNotSupported,SubtitleCodecNotSupported", "&SubtitleMethod=Hls", true),
        // A subtitle burned into the picture: the server converts the video.
        ("SubtitleCodecNotSupported", "&SubtitleMethod=Encode", false),
        // No word on how the subtitle is delivered: nothing to say the video is copied.
        ("SubtitleCodecNotSupported", "", false),
    ])
    func subtitlesTheServerAddsAreRepackaging(reasons: String, method: String, copies: Bool) throws {
        let response = try JSONDecoder().decode(
            PlaybackInfoResponse.self,
            from: Data(try Fixture.json("PlaybackInfoDirectStream").utf8)
        )
        let source = try #require(response.mediaSources?.first)
        let url =
            "/videos/6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f/master.m3u8?VideoCodec=h264&AudioCodec=aac&AudioStreamIndex=1"
            + "&SubtitleStreamIndex=2\(method)&api_key=token-1&TranscodeReasons=\(reasons)"
        #expect(PlaybackNegotiator.copiesVideoAndAudio(url, from: source, audioStreamIndex: nil) == copies)
    }

    @Test func aFileAVPlayerCantDecodeIsTranscoded() async throws {
        let host = "transcode.example.com"
        let item = "7d6e5f4a3b2c1d0e9f8a7b6c5d4e3f2a"
        let plan = try await negotiate(on: host, item: item, fixture: "PlaybackInfoTranscode")

        #expect(plan.method == .transcode)
        #expect(plan.url.path() == "/videos/\(item)/master.m3u8")
        #expect(plan.playSessionID == "session-transcode")
    }

    @Test func theRequestCarriesTheProfileAndTheChoices() async throws {
        let host = "request.example.com"
        let options = PlaybackOptions(
            maxBitrate: 8_000_000,
            startPosition: .seconds(90),
            audioStreamIndex: 2,
            subtitleStreamIndex: 3
        )
        _ = try await negotiate(on: host, item: movie, fixture: "PlaybackInfoDirectPlay", options: options)
        let request = try #require(
            StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").first)
        let json = try body(of: request)

        #expect(request.request.httpMethod == "POST")
        #expect(json["UserId"] as? String == "user-1")
        #expect(json["StartTimeTicks"] as? Int == 900_000_000)
        #expect(json["AudioStreamIndex"] as? Int == 2)
        #expect(json["SubtitleStreamIndex"] as? Int == 3)
        #expect(json["MaxStreamingBitrate"] as? Int == 8_000_000)
        #expect(json["EnableDirectPlay"] as? Bool == true)
        #expect(json["AllowVideoStreamCopy"] as? Bool == true)
        let profile = try #require(json["DeviceProfile"] as? [String: Any])
        #expect(profile["Name"] as? String == "Serafin")
        #expect(profile["MaxStreamingBitrate"] as? Int == 8_000_000)
    }

    @Test func askingAgainForAVersionNamesIt() async throws {
        // Jellyfin keeps a chosen subtitle or audio stream only when the request names the version it belongs to.
        let host = "again.example.com"
        var options = PlaybackOptions(subtitleStreamIndex: -1)
        options.mediaSourceID = movie
        _ = try await negotiate(on: host, item: movie, fixture: "PlaybackInfoDirectPlay", options: options)
        let request = try #require(
            StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").first)
        let json = try body(of: request)
        #expect(json["MediaSourceId"] as? String == movie)
        #expect(json["SubtitleStreamIndex"] as? Int == -1)
    }

    @Test func theProfileSaysWhatThisDevicePlays() async throws {
        let host = "av1-request.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/\(movie)/PlaybackInfo", .json(200, try Fixture.json("PlaybackInfoDirectPlay")))
        let negotiator = PlaybackNegotiator(
            client: try stubClient(on: host), userID: "user-1", video: VideoSupport(av1Level: 13, dolbyVision: true))
        _ = try await negotiator.plan(for: movie, options: PlaybackOptions())
        let request = try #require(
            StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").first)
        let profile = try #require(try body(of: request)["DeviceProfile"] as? [String: Any])
        let direct = try #require((profile["DirectPlayProfiles"] as? [[String: Any]])?.first)
        #expect(direct["VideoCodec"] as? String == "h264,hevc,av1")
    }

    @Test func turningDirectPlayOffUsesTheServersStream() throws {
        // A source the server would play directly, which also has a prepared stream.
        var response = try JSONDecoder().decode(
            PlaybackInfoResponse.self,
            from: Data(try Fixture.json("PlaybackInfoDirectPlay").utf8)
        )
        response.mediaSources?[0].transcodingURL = "/videos/\(movie)/master.m3u8?api_key=token-1"
        let plan = try PlaybackNegotiator.plan(
            from: response,
            itemID: movie,
            options: PlaybackOptions(allowsDirectPlay: false),
            client: try stubClient(on: "no-direct-play.example.com")
        )
        #expect(plan.method == .directStream)
        #expect(plan.url.path() == "/videos/\(movie)/master.m3u8")
    }

    @Test func noPlayableVersionIsReported() async throws {
        await #expect(throws: PlaybackError.notPlayable) {
            try await negotiate(on: "unplayable.example.com", item: movie, fixture: "PlaybackInfoNoCompatibleStream")
        }
    }

    @Test(arguments: [(PlaybackErrorCode.notAllowed, PlaybackError.notAllowed), (.rateLimitExceeded, .tooManyStreams)])
    func serverRefusalsAreNamed(code: PlaybackErrorCode, error: PlaybackError) {
        #expect(PlaybackError(code) == error)
    }

    @Test func anEndedSignInIsReported() async throws {
        let host = "signed-out-playback.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/\(movie)/PlaybackInfo", .json(401, "{}"))
        await #expect(throws: SerafinError.notSignedIn) {
            try await PlaybackNegotiator(client: try stubClient(on: host), userID: "user-1")
                .plan(for: movie, options: PlaybackOptions())
        }
    }
}

@Suite struct ProgressReporterTests {
    private let movie = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"

    private func plan(on host: String) async throws -> PlaybackPlan {
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/\(movie)/PlaybackInfo", .json(200, try Fixture.json("PlaybackInfoDirectPlay")))
        return try await PlaybackNegotiator(client: try stubClient(on: host), userID: "user-1")
            .plan(for: movie, options: PlaybackOptions(startPosition: .seconds(60)))
    }

    private func stubReports(on host: String) {
        for path in ["/Sessions/Playing", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped"] {
            StubURLProtocol.stub("\(host):443", path: path, .json(204, ""))
        }
    }

    @Test func startProgressAndStopAreReportedInOrderWithTheirPositions() async throws {
        let host = "reports.example.com"
        stubReports(on: host)
        let reporter = ProgressReporter(client: try stubClient(on: host), plan: try await plan(on: host))

        await reporter.start(at: .seconds(60), isPaused: false)
        await reporter.progress(at: .seconds(70), isPaused: false)
        await reporter.progress(at: .seconds(75), isPaused: true)
        await reporter.stop(at: .seconds(75))

        let start = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Sessions/Playing").first)
        let startBody = try body(of: start)
        #expect(startBody["ItemId"] as? String == movie)
        #expect(startBody["PositionTicks"] as? Int == 600_000_000)
        #expect(startBody["PlayMethod"] as? String == "DirectPlay")
        #expect(startBody["PlaySessionId"] as? String == "session-direct-play")
        #expect(startBody["CanSeek"] as? Bool == true)

        let progress = try StubURLProtocol.requests(to: "\(host):443", path: "/Sessions/Playing/Progress").map(body)
        #expect(progress.map { $0["PositionTicks"] as? Int } == [700_000_000, 750_000_000])
        #expect(progress.map { $0["IsPaused"] as? Bool } == [false, true])

        let stop = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Sessions/Playing/Stopped").first)
        #expect(try body(of: stop)["PositionTicks"] as? Int == 750_000_000)
    }

    @Test func nothingIsReportedBeforeTheStartOrTwiceAtTheEnd() async throws {
        let host = "quiet-reports.example.com"
        stubReports(on: host)
        let reporter = ProgressReporter(client: try stubClient(on: host), plan: try await plan(on: host))

        await reporter.progress(at: .seconds(5), isPaused: false)
        await reporter.stop(at: .seconds(5))
        await reporter.start(at: .zero, isPaused: false)
        await reporter.stop(at: .seconds(1))
        await reporter.stop(at: .seconds(2))

        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Sessions/Playing/Progress").isEmpty)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Sessions/Playing/Stopped").count == 1)
    }

    @Test func aNewPlanStopsTheOldPlaybackAndStartsTheNew() async throws {
        let host = "replaced-reports.example.com"
        stubReports(on: host)
        let first = try await plan(on: host)
        let reporter = ProgressReporter(client: try stubClient(on: host), plan: first)
        await reporter.start(at: .zero, isPaused: false)

        await reporter.replace(with: first.with(audio: 2), at: .seconds(30), isPaused: false)

        let starts = try StubURLProtocol.requests(to: "\(host):443", path: "/Sessions/Playing").map(body)
        #expect(starts.map { $0["AudioStreamIndex"] as? Int } == [1, 2])
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Sessions/Playing/Stopped").count == 1)
    }

    @Test func aFailedReportDoesNotThrow() async throws {
        let host = "failing-reports.example.com"
        StubURLProtocol.stub("\(host):443", .failure(.notConnectedToInternet))
        let plan = try PlaybackNegotiator.plan(
            from: try JSONDecoder().decode(
                PlaybackInfoResponse.self,
                from: Data(try Fixture.json("PlaybackInfoDirectPlay").utf8)
            ),
            itemID: movie,
            options: PlaybackOptions(),
            client: try stubClient(on: host)
        )
        let reporter = ProgressReporter(client: try stubClient(on: host), plan: plan)
        await reporter.start(at: .zero, isPaused: false)
        await reporter.stop(at: .seconds(1))
    }
}

@Suite struct NextEpisodeTests {
    private func episode(_ id: String) -> BaseItemDto {
        BaseItemDto(id: id, seriesID: "show", type: .episode)
    }

    @Test func theNextEpisodeFollowsTheCurrentOne() {
        let episodes = [episode("e1"), episode("e2"), episode("e3")]
        #expect(NextEpisode.episode(after: "e2", in: episodes)?.id == "e3")
        #expect(NextEpisode.episode(after: "e3", in: episodes) == nil)
        #expect(NextEpisode.episode(after: "missing", in: episodes) == nil)
    }

    @Test func theServerIsAskedForTheEpisodesEitherSide() async throws {
        let host = "next-episode.example.com"
        StubURLProtocol.stub(
            "\(host):443",
            path: "/Shows/show/Episodes",
            .json(
                200,
                #"{"Items":[{"Id":"e1","Type":"Episode"},{"Id":"e2","Type":"Episode"},{"Id":"e3","Type":"Episode"}],"TotalRecordCount":3}"#
            )
        )
        let next = try await NextEpisode(client: try stubClient(on: host), userID: "user-1").after(episode("e2"))
        #expect(next?.id == "e3")
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/show/Episodes").first)
        #expect(request.query("adjacentTo") == "e2")
    }
}
