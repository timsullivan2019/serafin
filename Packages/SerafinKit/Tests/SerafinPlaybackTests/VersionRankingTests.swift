import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinPlayback

/// Versions of one movie as the server describes them in its answer for this device: what each holds, and whether the
/// server would send it as it is or through its HLS stream, and why.
enum VersionFixtures {
    static func video(_ codec: String, _ width: Int, _ height: Int, range: VideoRangeType = .sdr) -> MediaStream {
        MediaStream(codec: codec, height: height, index: 0, type: .video, videoRangeType: range, width: width)
    }

    static func audio(_ codec: String, channels: Int, index: Int = 1, language: String = "eng") -> MediaStream {
        MediaStream(channels: channels, codec: codec, index: index, language: language, type: .audio)
    }

    /// A version the server lets the device play as it is.
    static func original(
        _ id: String, _ streams: [MediaStream], audio: Int = 1, video3D: Video3DFormat? = nil, size: Int? = nil
    ) -> MediaSourceInfo {
        MediaSourceInfo(
            protocol: .file, container: "mp4", defaultAudioStreamIndex: audio, id: id, isSupportsDirectPlay: true,
            isSupportsDirectStream: true, isSupportsTranscoding: true, mediaStreams: streams, size: size,
            transcodingURL: nil, video3DFormat: video3D)
    }

    /// A version the server sends through its HLS stream for `reasons`, which carries `videoCodecs` and `audioCodecs`.
    static func streamed(
        _ id: String, _ streams: [MediaStream], reasons: String, videoCodecs: String, audioCodecs: String,
        audio: Int = 1
    ) -> MediaSourceInfo {
        MediaSourceInfo(
            protocol: .file, container: "mkv", defaultAudioStreamIndex: audio, id: id, isSupportsDirectPlay: false,
            isSupportsDirectStream: false, isSupportsTranscoding: true, mediaStreams: streams,
            transcodingURL: "/videos/movie/master.m3u8?MediaSourceId=\(id)&VideoCodec=\(videoCodecs)"
                + "&AudioCodec=\(audioCodecs)&AudioStreamIndex=\(audio)&api_key=token-1&TranscodeReasons=\(reasons)")
    }

    /// A version the server can't send at all, as one over the quality cap that may not be converted.
    static func unsendable(_ id: String, _ streams: [MediaStream]) -> MediaSourceInfo {
        MediaSourceInfo(
            protocol: .file, container: "mkv", defaultAudioStreamIndex: 1, id: id, isSupportsDirectPlay: false,
            isSupportsDirectStream: false, isSupportsTranscoding: false, mediaStreams: streams)
    }

    /// A 4K Dolby Vision file, which a device without Dolby Vision gets converted.
    static func dolbyVision4K(deviceShowsDolbyVision: Bool) -> MediaSourceInfo {
        let streams = [video("hevc", 3840, 2160, range: .dovi), audio("eac3", channels: 6)]
        guard deviceShowsDolbyVision else {
            return streamed(
                "uhd", streams, reasons: "VideoRangeTypeNotSupported", videoCodecs: "h264", audioCodecs: "aac,eac3")
        }
        return streamed(
            "uhd", streams, reasons: "ContainerNotSupported", videoCodecs: "hevc,h264", audioCodecs: "aac,ac3,eac3")
    }

    /// A 1080p H.264 file with stereo AAC, which every device plays as it is.
    static let hd = original("hd", [video("h264", 1920, 1080), audio("aac", channels: 2)])

    /// The versions, in the server's order, as offers for this device.
    static func offers(_ sources: [MediaSourceInfo], allowsDirectPlay: Bool = true) -> [VersionOffer] {
        PlaybackNegotiator.offers(
            in: PlaybackInfoResponse(mediaSources: sources),
            options: PlaybackOptions(allowsDirectPlay: allowsDirectPlay))
    }
}

@Suite struct VersionRankingTests {
    private typealias Fixtures = VersionFixtures

    private func preferred(_ sources: [MediaSourceInfo]) -> String? {
        VersionRanking.preferred(among: Fixtures.offers(sources))?.id
    }

    // The plan's three fixtures.

    @Test func aDeviceWithoutDolbyVisionPlaysThe1080pRatherThanConvertTheDolbyVision4K() {
        #expect(preferred([Fixtures.dolbyVision4K(deviceShowsDolbyVision: false), Fixtures.hd]) == "hd")
        // Whatever order the server lists them in.
        #expect(preferred([Fixtures.hd, Fixtures.dolbyVision4K(deviceShowsDolbyVision: false)]) == "hd")
    }

    @Test func aDeviceWithDolbyVisionPlaysThe4KEvenThoughItsRepackaged() {
        #expect(preferred([Fixtures.hd, Fixtures.dolbyVision4K(deviceShowsDolbyVision: true)]) == "uhd")
        #expect(preferred([Fixtures.dolbyVision4K(deviceShowsDolbyVision: true), Fixtures.hd]) == "uhd")
    }

    @Test func two1080pVersionsWithDifferentAudioPlayTheOneWithMoreChannels() {
        let stereo = Fixtures.original(
            "stereo", [Fixtures.video("h264", 1920, 1080), Fixtures.audio("aac", channels: 2)])
        let surround = Fixtures.original(
            "surround", [Fixtures.video("h264", 1920, 1080), Fixtures.audio("eac3", channels: 6)])
        #expect(preferred([stereo, surround]) == "surround")
        #expect(preferred([surround, stereo]) == "surround")
    }

    // Further cases.

    @Test func audioTheServerConvertsLosesToAudioThatPlaysAsItIs() {
        // TrueHD 7.1 has more channels, but AVPlayer can't decode it, so the server converts it.
        let stereo = Fixtures.original(
            "stereo", [Fixtures.video("h264", 1920, 1080), Fixtures.audio("aac", channels: 2)])
        let trueHD = Fixtures.streamed(
            "truehd", [Fixtures.video("h264", 1920, 1080), Fixtures.audio("truehd", channels: 8)],
            reasons: "AudioCodecNotSupported", videoCodecs: "h264", audioCodecs: "aac,ac3,eac3")
        #expect(Fixtures.offers([trueHD]).first?.delivery == .audioConverted)
        #expect(preferred([trueHD, stereo]) == "stereo")
    }

    @Test func aVersionWithOnlyItsAudioConvertedStillBeatsASmallerPicture() {
        let uhd = Fixtures.streamed(
            "uhd", [Fixtures.video("hevc", 3840, 2160), Fixtures.audio("truehd", channels: 8)],
            reasons: "ContainerNotSupported,AudioCodecNotSupported", videoCodecs: "hevc,h264", audioCodecs: "aac,eac3")
        #expect(Fixtures.offers([uhd]).first?.delivery == .audioConverted)
        #expect(preferred([Fixtures.hd, uhd]) == "uhd")
    }

    @Test func whenEveryPictureIsConvertedTheSmallestPlays() {
        // Under a low quality cap the server converts both, so the one it shrinks least plays.
        let uhd = Fixtures.streamed(
            "uhd", [Fixtures.video("hevc", 3840, 2160), Fixtures.audio("aac", channels: 2)],
            reasons: "ContainerBitrateExceedsLimit", videoCodecs: "h264", audioCodecs: "aac")
        let hd = Fixtures.streamed(
            "hd", [Fixtures.video("h264", 1920, 1080), Fixtures.audio("aac", channels: 2)],
            reasons: "ContainerBitrateExceedsLimit", videoCodecs: "h264", audioCodecs: "aac")
        #expect(Fixtures.offers([uhd, hd]).map(\.delivery) == [.videoConverted, .videoConverted])
        #expect(preferred([uhd, hd]) == "hd")
    }

    @Test func aPictureKeptBeatsAnyConvertedOne() {
        let sd = Fixtures.original("sd", [Fixtures.video("h264", 720, 480), Fixtures.audio("aac", channels: 2)])
        #expect(preferred([Fixtures.dolbyVision4K(deviceShowsDolbyVision: false), sd]) == "sd")
    }

    @Test func aVersionTheServerCantSendComesLast() {
        let unsendable = Fixtures.unsendable(
            "unsendable", [Fixtures.video("hevc", 3840, 2160), Fixtures.audio("aac", channels: 2)])
        #expect(Fixtures.offers([unsendable]).first?.delivery == nil)
        // Even after a version the server converts.
        #expect(preferred([unsendable, Fixtures.dolbyVision4K(deviceShowsDolbyVision: false)]) == "uhd")
        #expect(preferred([unsendable, Fixtures.hd]) == "hd")
        #expect(preferred([unsendable]) == "unsendable")
    }

    @Test func aFlatVersionBeats3D() {
        let threeD = Fixtures.original(
            "3d", [Fixtures.video("h264", 3840, 2160), Fixtures.audio("aac", channels: 2)], video3D: .halfSideBySide)
        #expect(preferred([threeD, Fixtures.hd]) == "hd")
    }

    @Test func theServersOrderSettlesTheRest() {
        let first = Fixtures.original(
            "first", [Fixtures.video("h264", 1920, 1080), Fixtures.audio("aac", channels: 2)])
        let second = Fixtures.original(
            "second", [Fixtures.video("h264", 1920, 1080), Fixtures.audio("aac", channels: 2)])
        #expect(preferred([first, second]) == "first")
        #expect(preferred([second, first]) == "second")
    }

    @Test func noVersionsMeansNoChoice() {
        #expect(VersionRanking.preferred(among: []) == nil)
    }

    @Test func turningDirectPlayOffSendsEveryVersionThroughTheServersStream() {
        var hd = Fixtures.hd
        hd.transcodingURL =
            "/videos/movie/master.m3u8?VideoCodec=h264&AudioCodec=aac&TranscodeReasons=ContainerNotSupported"
        #expect(Fixtures.offers([hd]).first?.delivery == .original)
        #expect(Fixtures.offers([hd], allowsDirectPlay: false).first?.delivery == .repackaged)
        hd.transcodingURL = nil
        #expect(Fixtures.offers([hd], allowsDirectPlay: false).first?.delivery == nil)
    }
}

@Suite struct VersionNegotiationTests {
    private typealias Fixtures = VersionFixtures
    private let movie = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"

    private func plan(_ sources: [MediaSourceInfo], options: PlaybackOptions = PlaybackOptions()) throws
        -> PlaybackPlan
    {
        try PlaybackNegotiator.plan(
            from: PlaybackInfoResponse(mediaSources: sources, playSessionID: "session"),
            itemID: movie,
            options: options,
            client: try stubClient(on: "versions.example.com")
        )
    }

    @Test func withNoVersionNamedThePreferredOnePlays() throws {
        let plan = try plan([Fixtures.dolbyVision4K(deviceShowsDolbyVision: false), Fixtures.hd])
        #expect(plan.mediaSourceID == "hd")
        #expect(plan.method == .directPlay)
    }

    @Test func aNamedVersionPlaysWhateverTheRanking() throws {
        let plan = try plan(
            [Fixtures.dolbyVision4K(deviceShowsDolbyVision: false), Fixtures.hd],
            options: PlaybackOptions(mediaSourceID: "uhd"))
        #expect(plan.mediaSourceID == "uhd")
        #expect(plan.method == .transcode)
    }

    @Test func aNamedVersionTheServerCantSendIsReported() throws {
        let uhd = Fixtures.unsendable("uhd", [Fixtures.video("hevc", 3840, 2160)])
        #expect(throws: PlaybackError.notPlayable) {
            try plan([uhd, Fixtures.hd], options: PlaybackOptions(mediaSourceID: "uhd"))
        }
    }

    @Test func theAudioPlayedIsTheChosenVersionsDefault() throws {
        let surround = Fixtures.original(
            "surround",
            [
                Fixtures.video("h264", 1920, 1080), Fixtures.audio("aac", channels: 2),
                Fixtures.audio("eac3", channels: 6, index: 2),
            ],
            audio: 2)
        let plan = try plan([Fixtures.hd, surround])
        #expect(plan.mediaSourceID == "surround")
        #expect(plan.audioStreamIndex == 2)
    }

    @Test func onlyAnAnswerWithNoVersionsAndNoCompatibleStreamLacksTheVersionNamed() {
        #expect(
            PlaybackNegotiator.lacksNamedVersion(PlaybackInfoResponse(errorCode: .noCompatibleStream, mediaSources: []))
        )
        #expect(PlaybackNegotiator.lacksNamedVersion(PlaybackInfoResponse(errorCode: .noCompatibleStream)))
        #expect(!PlaybackNegotiator.lacksNamedVersion(PlaybackInfoResponse(errorCode: .notAllowed, mediaSources: [])))
        #expect(!PlaybackNegotiator.lacksNamedVersion(PlaybackInfoResponse(mediaSources: [Fixtures.hd])))
    }

    @Test func aVersionTheServerNoLongerHasGivesWayToThePreferredOne() async throws {
        // Jellyfin answers a request naming a version it doesn't have with no versions and NoCompatibleStream.
        let host = "gone-version.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/\(movie)/PlaybackInfo",
            .json(200, try Fixture.json("PlaybackInfoNoCompatibleStream")),
            .json(200, try Fixture.json("PlaybackInfoDirectPlay")))
        let options = PlaybackOptions(audioStreamIndex: 4, subtitleStreamIndex: 7, mediaSourceID: "renamed")
        let plan = try await PlaybackNegotiator(client: try stubClient(on: host), userID: "user-1")
            .plan(for: movie, options: options)

        #expect(plan.mediaSourceID == movie)
        #expect(plan.audioStreamIndex == 1)
        let requests = try StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").map(body)
        #expect(requests.count == 2)
        #expect(requests.first?["MediaSourceId"] as? String == "renamed")
        // The version's tracks went with it.
        #expect(requests.last?["MediaSourceId"] as? String == nil)
        #expect(requests.last?["AudioStreamIndex"] as? Int == nil)
        #expect(requests.last?["SubtitleStreamIndex"] as? Int == nil)
    }

    @Test func withNoVersionNamedNoCompatibleStreamIsStillReported() async throws {
        let host = "none-compatible.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/\(movie)/PlaybackInfo",
            .json(200, try Fixture.json("PlaybackInfoNoCompatibleStream")))
        await #expect(throws: PlaybackError.notPlayable) {
            try await PlaybackNegotiator(client: try stubClient(on: host), userID: "user-1")
                .plan(for: movie, options: PlaybackOptions())
        }
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").count == 1)
    }

    @Test func theOffersAskAboutEveryVersion() async throws {
        let host = "offers.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/\(movie)/PlaybackInfo", .json(200, try Fixture.json("PlaybackInfoDirectPlay")))
        let offers = try await PlaybackNegotiator(client: try stubClient(on: host), userID: "user-1")
            .offers(for: movie, options: PlaybackOptions(maxBitrate: 8_000_000, mediaSourceID: "other"))

        #expect(offers.map(\.id) == [movie])
        #expect(offers.map(\.delivery) == [.original])
        let request = try #require(
            StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").first)
        let json = try body(of: request)
        #expect(json["MediaSourceId"] as? String == nil)
        #expect(json["MaxStreamingBitrate"] as? Int == 8_000_000)
    }
}

@Suite struct VersionSwitchTracksTests {
    private typealias Fixtures = VersionFixtures

    /// A 4K version playing, with English and French audio and English subtitles, regular and SDH.
    private let playing = MediaSourceInfo(
        defaultAudioStreamIndex: 1,
        id: "uhd",
        mediaStreams: [
            Fixtures.video("hevc", 3840, 2160),
            Fixtures.audio("truehd", channels: 8, index: 1),
            Fixtures.audio("eac3", channels: 6, index: 2, language: "fre"),
            MediaStream(codec: "subrip", index: 3, language: "eng", type: .subtitle),
            MediaStream(codec: "subrip", index: 4, isHearingImpaired: true, language: "eng", type: .subtitle),
        ]
    )

    /// A 1080p version with the same languages in another order, and SDH subtitles only.
    private let other = MediaSourceInfo(
        defaultAudioStreamIndex: 1,
        id: "hd",
        mediaStreams: [
            Fixtures.video("h264", 1920, 1080),
            Fixtures.audio("aac", channels: 2, index: 1),
            Fixtures.audio("ac3", channels: 6, index: 2),
            Fixtures.audio("eac3", channels: 6, index: 3, language: "fre"),
            MediaStream(codec: "subrip", index: 4, isHearingImpaired: true, language: "eng", type: .subtitle),
        ]
    )

    /// A version in English only, with no subtitles.
    private let englishOnly = MediaSourceInfo(
        defaultAudioStreamIndex: 1,
        id: "sd",
        mediaStreams: [Fixtures.video("h264", 720, 480), Fixtures.audio("aac", channels: 2, index: 1)]
    )

    private func plan(audio: Int?) throws -> PlaybackPlan {
        PlaybackPlan(
            itemID: "movie",
            mediaSource: playing,
            url: try #require(URL(string: "https://example.com/stream")),
            method: .directStream,
            playSessionID: nil,
            startPosition: .zero,
            audioStreamIndex: audio,
            subtitleStreamIndex: 3
        )
    }

    @Test func theDefaultAudioLeavesTheChoiceToTheOtherVersion() throws {
        #expect(PlayerEngine.matchingAudio(in: other, for: try plan(audio: nil)) == nil)
        #expect(PlayerEngine.matchingAudio(in: other, for: try plan(audio: 1)) == nil)
    }

    @Test func audioPickedCarriesOnInTheSameLanguage() throws {
        // French Dolby Digital Plus 5.1, picked, is track 3 in the other version.
        #expect(PlayerEngine.matchingAudio(in: other, for: try plan(audio: 2)) == 3)
        // A version without French plays its own default.
        #expect(PlayerEngine.matchingAudio(in: englishOnly, for: try plan(audio: 2)) == nil)
    }

    @Test func subtitlesShowingCarryOnInTheSameLanguage() throws {
        let plan = try plan(audio: nil)
        // English, not SDH, showing: the other version has English SDH only, which stands in.
        #expect(
            PlayerEngine.matchingSubtitles(in: other, for: .stream(3), from: plan, rules: nil, audioIndex: nil)
                == .stream(4))
        // English SDH showing: the other version's English SDH.
        #expect(
            PlayerEngine.matchingSubtitles(in: other, for: .stream(4), from: plan, rules: nil, audioIndex: nil)
                == .stream(4))
    }

    @Test func noSubtitlesAndGeneratedOnesStayAsTheyAre() throws {
        let plan = try plan(audio: nil)
        #expect(PlayerEngine.matchingSubtitles(in: other, for: .off, from: plan, rules: nil, audioIndex: nil) == .off)
        #expect(
            PlayerEngine.matchingSubtitles(in: other, for: .generated, from: plan, rules: nil, audioIndex: nil)
                == .generated)
    }

    @Test func aVersionWithoutTheSubtitlesShowingFallsBackToNone() throws {
        #expect(
            PlayerEngine.matchingSubtitles(
                in: englishOnly, for: .stream(3), from: try plan(audio: nil), rules: nil, audioIndex: nil) == .off)
    }

    @Test func theOtherVersionsSubtitlesDecideWhetherItMayPlayAsItIs() {
        let subtitles = PlayerEngine.streams(.subtitle, of: other)
        #expect(subtitles.map(\.index) == [4])
        #expect(PlayerEngine.allowsDirectPlay(showing: -1, among: subtitles))
        #expect(!PlayerEngine.allowsDirectPlay(showing: 4, among: subtitles))
    }
}

@Suite struct DownloadVersionTests {
    private typealias Fixtures = VersionFixtures
    private let movie = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"

    /// The server's answer offering `sources`.
    private func answer(_ sources: [MediaSourceInfo]) throws -> String {
        let data = try JSONEncoder().encode(PlaybackInfoResponse(mediaSources: sources, playSessionID: "s"))
        return String(decoding: data, as: UTF8.self)
    }

    /// Plans the movie's download of `version` on `host`, which answers with `answers`, in order.
    private func plan(on host: String, version: String? = nil, answers: [String]) async throws -> DownloadPlan {
        StubURLProtocol.stubSequence(
            "\(host):443", path: "/Items/\(movie)/PlaybackInfo", answers.map { .json(200, $0) })
        return try await DownloadPlanner(client: try stubClient(on: host), userID: "user-1", video: VideoSupport.none)
            .plan(for: movie, mediaSourceID: version)
    }

    private func requests(on host: String) throws -> [[String: Any]] {
        try StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movie)/PlaybackInfo").map(body)
    }

    @Test func eachVersionDownloadsAsTheServerWouldSendIt() {
        #expect(DownloadPlanner.delivery(of: Fixtures.hd) == .original)
        #expect(DownloadPlanner.delivery(of: Fixtures.dolbyVision4K(deviceShowsDolbyVision: false)) == .videoConverted)
        #expect(DownloadPlanner.delivery(of: Fixtures.unsendable("none", [Fixtures.video("hevc", 3840, 2160)])) == nil)
    }

    @Test func withNoVersionNamedThePreferredOneDownloads() async throws {
        let plan = try await plan(
            on: "download-preferred.example.com",
            answers: [try answer([Fixtures.dolbyVision4K(deviceShowsDolbyVision: false), Fixtures.hd])])
        guard case .original(let original) = plan else {
            Issue.record("Expected the original, got \(plan)")
            return
        }
        #expect(original.mediaSourceID == "hd")
    }

    @Test func theVersionPickedDownloads() async throws {
        let host = "download-picked.example.com"
        // Jellyfin answers a request naming a version with that version alone.
        let plan = try await plan(on: host, version: "hd", answers: [try answer([Fixtures.hd])])
        guard case .original(let original) = plan else {
            Issue.record("Expected the original, got \(plan)")
            return
        }
        #expect(original.mediaSourceID == "hd")
        #expect(try requests(on: host).first?["MediaSourceId"] as? String == "hd")
    }

    @Test func aVersionTheServerNoLongerHasGivesWayToThePreferredOne() async throws {
        let host = "download-gone.example.com"
        let plan = try await plan(
            on: host, version: "renamed",
            answers: [
                try Fixture.json("PlaybackInfoNoCompatibleStream"),
                try answer([Fixtures.dolbyVision4K(deviceShowsDolbyVision: false), Fixtures.hd]),
            ])
        guard case .original(let original) = plan else {
            Issue.record("Expected the original, got \(plan)")
            return
        }
        #expect(original.mediaSourceID == "hd")
        let sent = try requests(on: host)
        #expect(sent.map { $0["MediaSourceId"] as? String } == ["renamed", nil])
    }
}

@MainActor @Suite struct EngineVersionTests {
    private let episode = BaseItemDto(
        id: "1f3d9c1e78e12aae4c078801aeccb6de", runTimeTicks: 1_200_000_000, type: .episode)

    @Test func aDownloadedCopyPlaysTheOneVersionItSaved() async throws {
        let host = "copy-versions.example.com"
        let engine = PlayerEngine(client: try stubClient(on: host), userID: "user-1", pinning: nil)
        let itemID = try #require(episode.id)
        let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mp4")
        let copy = DownloadedCopy(file: file, mediaSourceID: itemID, tracks: DownloadTracks()) { _ in }

        let load = Task.immediate { await engine.load(episode, options: PlaybackOptions(), from: copy) }
        for _ in 0..<1000 where engine.plan == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        await engine.selectVersion("2a4e0d2f89f23bbf5d189912bfddc7ef")

        #expect(engine.versions.isEmpty)
        #expect(engine.pendingVersion == nil)
        #expect(engine.plan?.mediaSourceID == itemID)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(itemID)/PlaybackInfo").isEmpty)
        load.cancel()
        await engine.stop()
    }

    @Test func theOffersAreAskedForUnderTheCapGiven() async throws {
        let host = "engine-offers.example.com"
        let itemID = try #require(episode.id)
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/\(itemID)/PlaybackInfo", .json(200, try Fixture.json("PlaybackInfoDirectPlay"))
        )
        let engine = PlayerEngine(client: try stubClient(on: host), userID: "user-1", pinning: nil)

        let offers = try await engine.versionOffers(of: itemID, maxBitrate: 4_000_000)

        #expect(offers.count == 1)
        let request = try #require(
            StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(itemID)/PlaybackInfo").first)
        #expect(try body(of: request)["MaxStreamingBitrate"] as? Int == 4_000_000)
    }
}
