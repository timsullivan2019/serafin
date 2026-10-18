import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

@Suite struct DownloadPlannerTests {
    private let movie = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"
    private let mkv = "6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f"

    /// Plans `item`'s download on `host`, which answers the server's questions about it with `answers`, in order.
    private func plan(
        on host: String,
        item: String,
        maxBitrate: Int? = nil,
        permissions: ConversionPermissions = .all,
        video: VideoSupport = .none,
        answers: [String]
    ) async throws -> DownloadPlan {
        StubURLProtocol.stubSequence("\(host):443", path: "/Items/\(item)/PlaybackInfo", answers.map { .json(200, $0) })
        return try await DownloadPlanner(client: try stubClient(on: host), userID: "user-1", video: video)
            .plan(for: item, maxBitrate: maxBitrate, permissions: permissions)
    }

    /// The server's answer offering `sources`.
    private func answer(_ sources: MediaSourceInfo...) throws -> String {
        let data = try JSONEncoder().encode(PlaybackInfoResponse(mediaSources: sources, playSessionID: "s"))
        return String(decoding: data, as: UTF8.self)
    }

    private func stream(_ type: MediaStreamType, _ index: Int, _ codec: String) -> MediaStream {
        var stream = MediaStream()
        stream.type = type
        stream.index = index
        stream.codec = codec
        return stream
    }

    /// The query of an address the server offers, from its settings.
    private func query(_ items: String...) -> String {
        items.joined(separator: "&")
    }

    /// The settings and reasons of the MP4 the server makes of ``matroska(query:subtitles:)`` by copying its video and
    /// audio into it.
    private var repackaged: String {
        query(
            "VideoCodec=hevc,h264", "AudioCodec=aac,eac3,ac3", "AudioStreamIndex=1", "VideoBitrate=999360000",
            "AudioBitrate=640000", "TranscodeReasons=ContainerNotSupported")
    }

    /// A Matroska file the player can't open, an hour long: 1080p H.264 video at 8 Mbps and English AC-3 audio at
    /// 640 kbps, with English subtitles inside it and Spanish ones in a file of their own, which the server sends as
    /// WebVTT, as the server answers when it judges it with subtitles `subtitles`, or -1 for none. The server offers
    /// an MP4 with the settings in `query`, or none.
    private func matroska(query: String?, subtitles: Int = -1) -> MediaSourceInfo {
        var video = stream(.video, 0, "h264")
        video.bitRate = 8_000_000
        video.width = 1920
        video.height = 1080
        var audio = stream(.audio, 1, "ac3")
        audio.bitRate = 640_000
        audio.language = "eng"
        var english = stream(.subtitle, 2, "subrip")
        english.language = "eng"
        english.isTextSubtitleStream = true
        english.deliveryMethod = .external
        var spanish = stream(.subtitle, 3, "subrip")
        spanish.language = "spa"
        spanish.isExternal = true
        spanish.isTextSubtitleStream = true
        spanish.deliveryMethod = .external
        var source = MediaSourceInfo()
        source.id = mkv
        source.`protocol` = .file
        source.container = "mkv"
        source.isRemote = false
        source.isSupportsDirectPlay = false
        source.isSupportsTranscoding = true
        source.runTimeTicks = 36_000_000_000
        source.defaultAudioStreamIndex = 1
        source.defaultSubtitleStreamIndex = subtitles
        source.mediaStreams = [video, audio, english, spanish]
        source.transcodingURL = query.map { query in
            "/videos/\(mkv)/stream.mp4?DeviceId=device-1&MediaSourceId=\(mkv)&\(query)&PlaySessionId=s&api_key=token-1"
        }
        return source
    }

    /// French image subtitles inside ``matroska(query:subtitles:)``, which the server burns into the picture.
    private var frenchPictures: MediaStream {
        var french = stream(.subtitle, 4, "PGSSUB")
        french.language = "fre"
        french.isTextSubtitleStream = false
        french.deliveryMethod = .encode
        return french
    }

    /// An MP4 the player opens, with English subtitles inside it and `separate` in a file of their own, as the server
    /// answers when it judges it with subtitles `subtitles`, or -1 for none.
    private func mp4(directPlays: Bool, subtitles: Int, separate: MediaStream) -> MediaSourceInfo {
        var english = stream(.subtitle, 2, "mov_text")
        english.language = "eng"
        english.isTextSubtitleStream = true
        english.deliveryMethod = .embed
        var source = MediaSourceInfo()
        source.id = movie
        source.`protocol` = .file
        source.container = "mov,mp4,m4a,3gp,3g2,mj2"
        source.isRemote = false
        source.isSupportsDirectPlay = directPlays
        source.size = 1_789_000_000
        source.defaultAudioStreamIndex = 1
        source.defaultSubtitleStreamIndex = subtitles
        source.mediaStreams = [stream(.video, 0, "h264"), stream(.audio, 1, "aac"), english, separate]
        return source
    }

    /// Spanish subtitles in a file of their own, which the server sends as WebVTT.
    private var spanishText: MediaStream {
        var spanish = stream(.subtitle, 3, "subrip")
        spanish.language = "spa"
        spanish.isExternal = true
        spanish.isTextSubtitleStream = true
        spanish.deliveryMethod = .external
        return spanish
    }

    /// Spanish image subtitles in a file of their own, which the server can only burn into the picture.
    private var spanishPictures: MediaStream {
        var spanish = stream(.subtitle, 3, "PGSSUB")
        spanish.language = "spa"
        spanish.isExternal = true
        spanish.isTextSubtitleStream = false
        spanish.deliveryMethod = .encode
        return spanish
    }

    /// Answers on `host` with WebVTT for subtitles 2 and 3 of `item`'s version of the same ID.
    private func stubSubtitles(on host: String, item: String) {
        for (index, text) in [(2, "Hello"), (3, "Hola")] {
            StubURLProtocol.stub(
                "\(host):443", path: subtitlesPath(item: item, index: index),
                .json(200, "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\n\(text)\n"))
        }
    }

    /// Where the server sends the WebVTT of subtitles `index` of `item`'s version of the same ID.
    private func subtitlesPath(item: String, index: Int) -> String {
        "/Videos/\(item)/\(item)/Subtitles/\(index)/Stream.vtt"
    }

    /// The conversion the server offers of `source`, or nil when it can't be converted.
    private func conversion(
        of source: MediaSourceInfo,
        capped: Bool = false,
        permissions: ConversionPermissions = .all
    ) -> DownloadPlanner.Conversion? {
        let answer = DownloadPlanner.conversion(of: source, capped: capped, permissions: permissions)
        guard case .converts(let conversion) = answer else { return nil }
        return conversion
    }

    // MARK: - Originals

    @Test func aFileThePlayerOpensIsDownloadedAsItIs() async throws {
        let host = "download-original.example.com"
        let plan = try await plan(on: host, item: movie, answers: [try Fixture.json("PlaybackInfoDirectPlay")])

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
        // With nothing to add, it's saved as it arrives.
        #expect(original.preparation == nil)
        let url = try #require(URLComponents(url: original.url, resolvingAgainstBaseURL: false))
        #expect(url.path == "/Items/\(movie)/Download")
        #expect(url.query == nil)

        // At the Maximum quality, no file is turned away for its bitrate.
        let sent = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").first)
        #expect(try body(of: sent)["MaxStreamingBitrate"] as? Int == DownloadPlanner.bitrate)
    }

    @Test func theServerIsAskedAsThePlayerAsksWithTheDownloadProfile() async throws {
        let host = "download-request.example.com"
        _ = try await plan(
            on: host, item: movie, maxBitrate: 8_000_000, answers: [try Fixture.json("PlaybackInfoDirectPlay")])

        let sent = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").first)
        let json = try body(of: sent)
        #expect(json["EnableDirectPlay"] as? Bool == true)
        #expect(json["EnableDirectStream"] as? Bool == true)
        #expect(json["EnableTranscoding"] as? Bool == true)
        #expect(json["AllowVideoStreamCopy"] as? Bool == true)
        #expect(json["AllowAudioStreamCopy"] as? Bool == true)
        #expect(json["MaxStreamingBitrate"] as? Int == 8_000_000)
        #expect(json["SubtitleStreamIndex"] as? Int == nil)
        let profile = try #require(json["DeviceProfile"] as? [String: Any])
        #expect(profile["MaxStreamingBitrate"] as? Int == 8_000_000)
        let transcoding = try #require((profile["TranscodingProfiles"] as? [[String: Any]])?.first)
        #expect(transcoding["Protocol"] as? String == "http")
        #expect(transcoding["Container"] as? String == "mp4")
    }

    @Test func subtitlesInFilesOfTheirOwnAreAddedToAnOriginal() async throws {
        let host = "download-original-subtitles.example.com"
        stubSubtitles(on: host, item: movie)
        let source = mp4(directPlays: true, subtitles: 3, separate: spanishText)
        let plan = try await plan(on: host, item: movie, answers: [try answer(source)])

        guard case .original(let original) = plan else {
            Issue.record("Expected the original, got \(plan)")
            return
        }
        #expect(original.tracks.subtitles.map(\.index) == [2, 3])
        #expect(original.tracks.defaultSubtitles == 3)
        let preparation = try #require(original.preparation)
        #expect(preparation.subtitles.map(\.index) == [3])
        let added = String(decoding: preparation.subtitles.first?.webVTT ?? Data(), as: UTF8.self)
        #expect(added.contains("Hola"))
        // The file plays as it arrives, so it's kept without them if they can't be added.
        #expect(preparation.playsAsItArrives)
        #expect(preparation.dolbyVision == nil)
        // Only the subtitles outside the file are fetched.
        #expect(StubURLProtocol.requests(to: "\(host):443", path: subtitlesPath(item: movie, index: 2)).isEmpty)
    }

    @Test func aVersionTurnedDownForItsSubtitlesIsAskedAboutAgainWithout() async throws {
        let host = "download-subtitles-off.example.com"
        // The account's Spanish subtitles are pictures in a file of their own, which only burning in can show.
        let plan = try await plan(
            on: host, item: movie,
            answers: [
                try answer(mp4(directPlays: false, subtitles: 3, separate: spanishPictures)),
                try answer(mp4(directPlays: true, subtitles: -1, separate: spanishPictures)),
            ])

        guard case .original(let original) = plan else {
            Issue.record("Expected the original, got \(plan)")
            return
        }
        #expect(original.mediaSourceID == movie)
        #expect(original.tracks.subtitles.map(\.index) == [2])
        #expect(original.tracks.defaultSubtitles == nil)
        #expect(original.preparation == nil)
        let sent = try StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").map(body)
        #expect(sent.count == 2)
        #expect(sent.first?["SubtitleStreamIndex"] as? Int == nil)
        #expect(sent.last?["SubtitleStreamIndex"] as? Int == -1)
        #expect(sent.last?["MediaSourceId"] as? String == movie)
    }

    @Test func aVersionTurnedDownWithNoSubtitlesIsAskedAboutOnce() async throws {
        let host = "download-turned-down.example.com"
        let source = mp4(directPlays: false, subtitles: -1, separate: spanishText)
        let plan = try await plan(on: host, item: movie, answers: [try answer(source)])
        #expect(plan == .refused(.unavailable))
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").count == 1)
    }

    @Test func theFileKeepsItsOwnExtension() async throws {
        let json = """
            {"MediaSources":[{"Id":"\(movie)","Protocol":"File","Container":"mov,mp4,m4a,3gp,3g2,mj2",\
            "Path":"D:\\\\Films\\\\Spring.mov","SupportsDirectPlay":true,"IsRemote":false}],"PlaySessionId":"s"}
            """
        let plan = try await plan(on: "download-mov.example.com", item: movie, answers: [json])
        guard case .original(let original) = plan else {
            Issue.record("Expected the original, got \(plan)")
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

    // MARK: - Conversions

    @Test func aFileThePlayerCantOpenIsTheMP4TheServerMakes() async throws {
        let host = "download-repackaged.example.com"
        stubSubtitles(on: host, item: mkv)
        let plan = try await plan(on: host, item: mkv, answers: [try answer(matroska(query: repackaged, subtitles: 3))])

        guard case .converted(let converted) = plan else {
            Issue.record("Expected a conversion, got \(plan)")
            return
        }
        #expect(converted.mediaSourceID == mkv)
        #expect(converted.fileExtension == "mp4")
        // An hour of the video and audio the server copies.
        #expect(converted.bytes == 3_888_000_000)
        let url = try #require(URLComponents(url: converted.url, resolvingAgainstBaseURL: false))
        #expect(url.host == host)
        #expect(url.path == "/videos/\(mkv)/stream.mp4")
        let names = (url.queryItems ?? []).map(\.name)
        #expect(names.contains("MediaSourceId"))
        #expect(names.contains("TranscodeReasons"))
        #expect(!names.contains("api_key"))
        // The MP4 carries the one audio track the server picked.
        #expect(converted.tracks.audio.map(\.index) == [1])
        #expect(converted.tracks.defaultAudio == 1)
        #expect(converted.tracks.subtitles.map(\.index) == [2, 3])
        #expect(converted.tracks.defaultSubtitles == 3)
        #expect(converted.tracks.burnedIn == nil)
        let preparation = try #require(converted.preparation)
        #expect(preparation.subtitles.map(\.index) == [2, 3])
        #expect(preparation.playsAsItArrives == false)
        #expect(preparation.dolbyVision == nil)
    }

    @Test func subtitlesAreFetchedWithTheTokenInTheHeader() async throws {
        let host = "download-subtitles-fetched.example.com"
        stubSubtitles(on: host, item: mkv)
        _ = try await plan(on: host, item: mkv, answers: [try answer(matroska(query: repackaged))])

        let fetched = StubURLProtocol.requests(to: "\(host):443", path: subtitlesPath(item: mkv, index: 3))
        #expect(fetched.count == 1)
        #expect(fetched.first?.authorization?.contains("Token=token-1") == true)
        #expect(fetched.first?.request.url?.query == nil)
    }

    @Test func subtitlesTheServerCantSendAsWebVTTAreLeftOut() async throws {
        let host = "download-subtitles-missing.example.com"
        StubURLProtocol.stub("\(host):443", path: subtitlesPath(item: mkv, index: 2), .json(500, ""))
        StubURLProtocol.stub(
            "\(host):443", path: subtitlesPath(item: mkv, index: 3),
            .json(200, "1\n00:00:01,000 --> 00:00:02,000\nHola\n"))
        let plan = try await plan(on: host, item: mkv, answers: [try answer(matroska(query: repackaged, subtitles: 3))])

        guard case .converted(let converted) = plan else {
            Issue.record("Expected a conversion, got \(plan)")
            return
        }
        #expect(converted.tracks.subtitles.isEmpty)
        #expect(converted.tracks.defaultSubtitles == nil)
        #expect(converted.preparation?.subtitles.isEmpty == true)
    }

    @Test func aServerThatCantBeReachedForSubtitlesStopsTheDownload() async throws {
        let host = "download-subtitles-offline.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: subtitlesPath(item: mkv, index: 2), .failure(.notConnectedToInternet))
        await #expect(throws: SerafinError.offline) {
            _ = try await plan(on: host, item: mkv, answers: [try answer(matroska(query: repackaged))])
        }
    }

    @Test func subtitlesBurnedInAreTheOnlyOnesTheCopyShows() async throws {
        let host = "download-burned-in.example.com"
        var source = matroska(
            query: query(repackaged, "SubtitleStreamIndex=4", "SubtitleMethod=Encode"), subtitles: 4)
        source.mediaStreams?.append(frenchPictures)
        let plan = try await plan(on: host, item: mkv, answers: [try answer(source)])

        guard case .converted(let converted) = plan else {
            Issue.record("Expected a conversion, got \(plan)")
            return
        }
        #expect(converted.tracks.subtitles.map(\.index) == [4])
        #expect(converted.tracks.burnedIn == 4)
        #expect(converted.tracks.defaultSubtitles == 4)
        #expect(converted.preparation?.subtitles.isEmpty == true)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: subtitlesPath(item: mkv, index: 2)).isEmpty)
    }

    @Test func withoutVideoConversionSubtitlesAreLeftOutRatherThanBurnedIn() async throws {
        let host = "download-burn-in-not-allowed.example.com"
        stubSubtitles(on: host, item: mkv)
        var burning = matroska(
            query: query(repackaged, "SubtitleStreamIndex=4", "SubtitleMethod=Encode"), subtitles: 4)
        burning.mediaStreams?.append(frenchPictures)
        var without = matroska(query: repackaged)
        without.mediaStreams?.append(frenchPictures)
        let plan = try await plan(
            on: host, item: mkv, permissions: ConversionPermissions(videoTranscoding: false),
            answers: [try answer(burning), try answer(without)])

        guard case .converted(let converted) = plan else {
            Issue.record("Expected a conversion, got \(plan)")
            return
        }
        #expect(converted.tracks.burnedIn == nil)
        #expect(converted.tracks.subtitles.map(\.index) == [2, 3])
        let sent = try StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(mkv)/PlaybackInfo").map(body)
        #expect(sent.count == 2)
        #expect(sent.last?["SubtitleStreamIndex"] as? Int == -1)
        #expect(sent.last?["MediaSourceId"] as? String == mkv)
    }

    @Test func videoThePlayerCantPlayIsntDownloadedWithoutVideoConversion() async throws {
        var source = matroska(
            query: query(
                "VideoCodec=hevc,h264", "AudioCodec=aac,eac3,ac3", "AudioStreamIndex=1",
                "TranscodeReasons=VideoCodecNotSupported"))
        source.mediaStreams?[0].codec = "av1"
        let plan = try await plan(
            on: "download-av1.example.com", item: mkv, permissions: ConversionPermissions(videoTranscoding: false),
            answers: [try answer(source)])
        #expect(plan == .refused(.notAllowed))
        // With it, the video is converted and the audio copied.
        let converted = try #require(conversion(of: source))
        #expect(!converted.copiesVideo)
        #expect(converted.copiesAudio)
    }

    @Test func videoAboveTheQualityIsntDownloadedWithoutVideoConversion() async throws {
        let capped = query(
            "VideoCodec=hevc,h264", "AudioCodec=aac,eac3,ac3", "AudioStreamIndex=1", "VideoBitrate=3616000",
            "AudioBitrate=384000", "TranscodeReasons=ContainerNotSupported,%20VideoBitrateNotSupported")
        let plan = try await plan(
            on: "download-over-quality.example.com", item: mkv, maxBitrate: 4_000_000,
            permissions: ConversionPermissions(videoTranscoding: false), answers: [try answer(matroska(query: capped))])
        #expect(plan == .refused(.overQuality))
        // With it, the video is converted to fit.
        let converted = try #require(conversion(of: matroska(query: capped), capped: true))
        #expect(!converted.copiesVideo)
        #expect(converted.videoBitrate == 3_616_000)
    }

    @Test func atTheMaximumQualityVideoOfUnknownBitrateIsCopied() {
        var source = matroska(query: repackaged)
        source.mediaStreams?[0].bitRate = nil
        let noVideo = ConversionPermissions(videoTranscoding: false)
        #expect(conversion(of: source, permissions: noVideo)?.copiesVideo == true)
        #expect(DownloadPlanner.conversion(of: source, capped: true, permissions: noVideo) == .refused(.overQuality))
        // The server converts it when it may.
        #expect(conversion(of: source)?.copiesVideo == false)
    }

    @Test func videoLargerThanTheAddressAllowsIsConverted() {
        let smaller = matroska(query: query(repackaged, "MaxWidth=1280", "MaxHeight=720"))
        #expect(conversion(of: smaller)?.copiesVideo == false)
        let noVideo = ConversionPermissions(videoTranscoding: false)
        #expect(DownloadPlanner.conversion(of: smaller, capped: false, permissions: noVideo) == .refused(.notAllowed))
        // Jellyfin lists every reason in one parameter.
        let rotated = matroska(
            query: query(
                "VideoCodec=hevc,h264", "AudioCodec=aac,eac3,ac3", "AudioStreamIndex=1", "VideoBitrate=999360000",
                "AudioBitrate=640000", "TranscodeReasons=ContainerNotSupported,%20VideoRotationNotSupported"))
        #expect(conversion(of: rotated)?.copiesVideo == false)
    }

    @Test func audioThePlayerCantPlayTakesAudioConversion() throws {
        var source = matroska(
            query: query(
                "VideoCodec=hevc,h264", "AudioCodec=aac,eac3,ac3", "AudioStreamIndex=1", "AudioBitrate=640000",
                "TranscodeReasons=ContainerNotSupported,%20AudioCodecNotSupported"))
        source.mediaStreams?[1].codec = "truehd"
        let noAudio = ConversionPermissions(audioTranscoding: false)
        #expect(DownloadPlanner.conversion(of: source, capped: false, permissions: noAudio) == .refused(.notAllowed))
        let converted = try #require(conversion(of: source))
        #expect(converted.copiesVideo)
        #expect(!converted.copiesAudio)
        #expect(converted.audioStreamIndex == 1)
    }

    @Test func copyingBothIntoTheMP4TakesThePermissionToRepackage() {
        let noRemuxing = ConversionPermissions(remuxing: false)
        let source = matroska(query: repackaged)
        #expect(DownloadPlanner.conversion(of: source, capped: false, permissions: noRemuxing) == .refused(.notAllowed))
        // Converting the audio isn't repackaging.
        var dts = source
        dts.mediaStreams?[1].codec = "dts"
        #expect(conversion(of: dts, permissions: noRemuxing)?.copiesAudio == false)
    }

    @Test func withNoMP4OnOfferNothingIsDownloaded() async throws {
        let none = matroska(query: nil)
        #expect(DownloadPlanner.conversion(of: none, capped: false, permissions: .all) == .refused(.unavailable))
        let nothing = ConversionPermissions(remuxing: false, videoTranscoding: false, audioTranscoding: false)
        #expect(DownloadPlanner.conversion(of: none, capped: false, permissions: nothing) == .refused(.notAllowed))
        // A playlist isn't a file to save.
        var playlist = matroska(query: repackaged)
        playlist.transcodingURL = playlist.transcodingURL?.replacingOccurrences(of: "stream.mp4", with: "master.m3u8")
        #expect(DownloadPlanner.conversion(of: playlist, capped: false, permissions: .all) == .refused(.unavailable))

        let plan = try await plan(
            on: "download-none.example.com", item: movie, answers: [try Fixture.json("PlaybackInfoNoCompatibleStream")])
        #expect(plan == .refused(.unavailable))
    }

    @Test func aStreamFromElsewhereIsNotDownloaded() async throws {
        let json = """
            {"MediaSources":[{"Id":"\(movie)","Protocol":"Http","Container":"mp4","SupportsDirectPlay":true,\
            "IsRemote":true}],"PlaySessionId":"s"}
            """
        let plan = try await plan(on: "download-remote.example.com", item: movie, answers: [json])
        #expect(plan == .refused(.unavailable))
    }

    @Test func aServerThatRefusesPlaybackIsAnError() async throws {
        await #expect(throws: PlaybackError.notAllowed) {
            _ = try await plan(
                on: "download-refused.example.com", item: movie,
                answers: [#"{"MediaSources":[],"ErrorCode":"NotAllowed"}"#])
        }
    }

    @Test func theTokenIsTakenOutOfTheAddress() {
        let address =
            "/videos/a/stream.mp4?MediaSourceId=a&api_key=secret&TranscodeReasons=ContainerNotSupported,"
            + "%20AudioCodecNotSupported&ApiKey=secret&API_KEY=secret"
        let kept =
            "/videos/a/stream.mp4?MediaSourceId=a&TranscodeReasons=ContainerNotSupported,%20AudioCodecNotSupported"
        #expect(DownloadPlanner.addressWithoutToken(address) == kept)
        #expect(DownloadPlanner.addressWithoutToken("/videos/a/stream.mp4?api_key=secret") == "/videos/a/stream.mp4")
    }

    @Test func theSizeIsEstimatedFromWhatsCopiedAndWhatsConverted() {
        let source = matroska(query: repackaged)
        let copied = DownloadPlanner.Conversion(
            mediaSourceID: mkv, address: "/", copiesVideo: true, copiesAudio: true, audioStreamIndex: 1, burnedIn: nil,
            videoBitrate: 999_360_000, audioBitrate: 640_000)
        #expect(DownloadPlanner.estimatedBytes(of: source, conversion: copied) == 3_888_000_000)
        // An hour of video converted at 4 Mbps and audio at 256 kbps.
        let converted = DownloadPlanner.Conversion(
            mediaSourceID: mkv, address: "/", copiesVideo: false, copiesAudio: false, audioStreamIndex: 1,
            burnedIn: nil, videoBitrate: 4_000_000, audioBitrate: 256_000)
        #expect(DownloadPlanner.estimatedBytes(of: source, conversion: converted) == 1_915_200_000)
        // Converted at no more than the original's bitrate.
        let atMaximum = DownloadPlanner.Conversion(
            mediaSourceID: mkv, address: "/", copiesVideo: false, copiesAudio: true, audioStreamIndex: 1,
            burnedIn: 4, videoBitrate: 999_360_000, audioBitrate: 640_000)
        #expect(DownloadPlanner.estimatedBytes(of: source, conversion: atMaximum) == 3_888_000_000)
        var unknown = source
        unknown.mediaStreams?[0].bitRate = nil
        #expect(DownloadPlanner.estimatedBytes(of: unknown, conversion: copied) == nil)
        unknown.runTimeTicks = nil
        #expect(DownloadPlanner.estimatedBytes(of: unknown, conversion: converted) == nil)
    }

    // MARK: - Dolby Vision

    @Test func dolbyVisionIsSignalledWhereTheDeviceShowsIt() {
        var source = matroska(query: repackaged)
        source.mediaStreams?[0].codec = "hevc"
        source.mediaStreams?[0].dvProfile = 8
        source.mediaStreams?[0].dvLevel = 6
        source.mediaStreams?[0].dvBlSignalCompatibilityID = 1
        source.mediaStreams?[0].videoRangeType = .doviWithHDR10
        let shows = VideoSupport(dolbyVision: true)
        let profile8 = DolbyVisionConfiguration(profile: 8, level: 6, baseLayerCompatibility: 1)
        #expect(DownloadPlanner.dolbyVision(of: source, on: shows) == profile8)
        #expect(DownloadPlanner.dolbyVision(of: source, on: .none) == nil)
        // Without the compatibility the server read, the range says.
        source.mediaStreams?[0].dvBlSignalCompatibilityID = nil
        source.mediaStreams?[0].videoRangeType = .doviWithHLG
        #expect(DownloadPlanner.dolbyVision(of: source, on: shows)?.baseLayerCompatibility == 4)
        // Profile 7 doesn't play.
        source.mediaStreams?[0].dvProfile = 7
        #expect(DownloadPlanner.dolbyVision(of: source, on: shows) == nil)
        source.mediaStreams?[0].dvProfile = 5
        source.mediaStreams?[0].videoRangeType = .dovi
        #expect(DownloadPlanner.dolbyVision(of: source, on: shows)?.baseLayerCompatibility == 0)
        source.mediaStreams?[0].videoRangeType = .doviInvalid
        #expect(DownloadPlanner.dolbyVision(of: source, on: shows) == nil)
        // Profile 10 in AV1, only on a device that shows it.
        source.mediaStreams?[0].codec = "av1"
        source.mediaStreams?[0].dvProfile = 10
        source.mediaStreams?[0].videoRangeType = .dovi
        #expect(DownloadPlanner.dolbyVision(of: source, on: shows) == nil)
        let inAV1 = VideoSupport(av1Level: 13, dolbyVision: true, dolbyVisionInAV1: true)
        #expect(DownloadPlanner.dolbyVision(of: source, on: inAV1)?.profile == 10)
    }

    @Test func aCopiedDolbyVisionVideoKeepsItsConfiguration() async throws {
        var source = matroska(query: repackaged)
        source.mediaStreams = Array((source.mediaStreams ?? []).prefix(2))
        source.mediaStreams?[0].codec = "hevc"
        source.mediaStreams?[0].dvProfile = 8
        source.mediaStreams?[0].dvLevel = 6
        source.mediaStreams?[0].videoRangeType = .doviWithHDR10
        let plan = try await plan(
            on: "download-dolby-vision.example.com", item: mkv, video: VideoSupport(dolbyVision: true),
            answers: [try answer(source)])

        guard case .converted(let converted) = plan else {
            Issue.record("Expected a conversion, got \(plan)")
            return
        }
        #expect(converted.preparation?.dolbyVision?.profile == 8)
        #expect(converted.preparation?.dolbyVision?.baseLayerCompatibility == 1)
    }

    // MARK: - Subtitles

    @Test func onlyWebVTTIsAdded() {
        #expect(DownloadPlanner.isWebVTT(Data("WEBVTT\n\n".utf8)))
        var marked = Data([0xEF, 0xBB, 0xBF])
        marked.append(contentsOf: "WEBVTT".utf8)
        #expect(DownloadPlanner.isWebVTT(marked))
        #expect(!DownloadPlanner.isWebVTT(Data("1\n00:00:01,000 --> 00:00:02,000\n".utf8)))
        #expect(!DownloadPlanner.isWebVTT(Data()))
    }

    @Test func atMostSixtyFourSubtitleStreamsAreAdded() {
        var source = MediaSourceInfo()
        source.mediaStreams = (0..<70).map { index in
            var subtitles = stream(.subtitle, index, "subrip")
            subtitles.deliveryMethod = index == 0 ? .encode : .external
            return subtitles
        }
        let added = DownloadPlanner.addedSubtitles(of: source)
        #expect(added.count == DownloadPlanner.maximumAddedSubtitles)
        #expect(added.first?.index == 1)
    }
}
