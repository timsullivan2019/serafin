import AVFoundation
import Foundation
import JellyfinAPI
import Testing

@testable import SerafinPlayback

@Suite struct SubtitlePlaylistsTests {
    /// A master playlist as Jellyfin writes one, with relative addresses, two text subtitles and the account's token.
    private let master = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English - SUBRIP",DEFAULT=YES,FORCED=NO,AUTOSELECT=YES,\
        URI="source-1/Subtitles/3/subtitles.m3u8?SegmentLength=30&ApiKey=token",LANGUAGE="eng"
        #EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English Forced - SUBRIP",DEFAULT=NO,FORCED=YES,\
        AUTOSELECT=YES,URI="source-1/Subtitles/4/subtitles.m3u8?SegmentLength=30&ApiKey=token",LANGUAGE="eng"
        #EXT-X-STREAM-INF:BANDWIDTH=8553453,AVERAGE-BANDWIDTH=8553453,VIDEO-RANGE=SDR,\
        CODECS="hvc1.2.4.L120.B0,mp4a.40.2",RESOLUTION=1920x1080,FRAME-RATE=23.976,SUBTITLES="subs"
        main.m3u8?MediaSourceId=source-1&VideoCodec=hevc,h264&SegmentContainer=mp4&SubtitleStreamIndex=3&ApiKey=token

        """

    /// A subtitle playlist as Jellyfin writes one: thirty-second WebVTT segments with its fixed time map.
    private let subtitles = """
        #EXTM3U
        #EXT-X-TARGETDURATION:30
        #EXT-X-VERSION:3
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXTINF:30,
        stream.vtt?CopyTimestamps=true&AddVttTimeMap=true&StartPositionTicks=0&EndPositionTicks=300000000&ApiKey=token
        #EXTINF:30,
        stream.vtt?CopyTimestamps=true&AddVttTimeMap=true&StartPositionTicks=300000000&EndPositionTicks=600000000\
        &ApiKey=token
        #EXTINF:8.005,
        stream.vtt?CopyTimestamps=true&AddVttTimeMap=true&StartPositionTicks=600000000&EndPositionTicks=680050000\
        &ApiKey=token
        #EXT-X-ENDLIST

        """

    private let masterURL = URL(string: "https://media.example/videos/item-1/master.m3u8?SegmentContainer=mp4")
    private let subtitlesURL = URL(
        string: "https://media.example/videos/item-1/source-1/Subtitles/3/subtitles.m3u8?SegmentLength=30&ApiKey=token")

    @Test func playlistsGoToTheLoaderUnderItsOwnSchemesAndBack() throws {
        let secure = try #require(URL(string: "https://media.example/videos/item-1/master.m3u8?ApiKey=token"))
        let loaded = try #require(SubtitlePlaylists.loaderURL(for: secure))
        #expect(loaded.absoluteString == "serafin-https://media.example/videos/item-1/master.m3u8?ApiKey=token")
        #expect(SubtitlePlaylists.serverURL(for: loaded) == secure)

        let plain = try #require(URL(string: "http://192.168.1.20:8096/videos/item-1/master.m3u8"))
        let loadedPlain = try #require(SubtitlePlaylists.loaderURL(for: plain))
        #expect(loadedPlain.scheme == "serafin-http")
        #expect(SubtitlePlaylists.serverURL(for: loadedPlain) == plain)

        // Only the server's own addresses go to the loader, and only the loader's come back.
        #expect(SubtitlePlaylists.loaderURL(for: try #require(URL(string: "file:///tmp/master.m3u8"))) == nil)
        #expect(SubtitlePlaylists.serverURL(for: secure) == nil)
    }

    @Test func onlyFragmentedMP4SegmentsAreRetimed() throws {
        let mp4 = try #require(URL(string: "https://media.example/videos/item-1/master.m3u8?segmentContainer=MP4"))
        let ts = try #require(URL(string: "https://media.example/videos/item-1/master.m3u8?SegmentContainer=ts"))
        let unsaid = try #require(URL(string: "https://media.example/videos/item-1/master.m3u8"))
        #expect(SubtitlePlaylists.isFragmentedMP4(mp4))
        #expect(!SubtitlePlaylists.isFragmentedMP4(ts))
        // Jellyfin sends MPEG-TS unless asked otherwise.
        #expect(!SubtitlePlaylists.isFragmentedMP4(unsaid))
    }

    @Test func theMasterSendsSubtitlePlaylistsToTheLoaderAndEverythingElseToTheServer() throws {
        let rewritten = SubtitlePlaylists.master(master, from: try #require(masterURL))
        let lines = rewritten.split(separator: "\n").map(String.init)
        #expect(lines.count == 5)
        #expect(lines[0] == "#EXTM3U")
        #expect(
            lines[1].contains(
                #"URI="serafin-https://media.example/videos/item-1/source-1/Subtitles/3/subtitles.m3u8?SegmentLength=30&ApiKey=token""#
            ))
        #expect(lines[1].hasPrefix(#"#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="English - SUBRIP""#))
        #expect(lines[1].hasSuffix(#",LANGUAGE="eng""#))
        #expect(lines[2].contains(#"URI="serafin-https://media.example/videos/item-1/source-1/Subtitles/4/"#))
        #expect(lines[3].hasPrefix("#EXT-X-STREAM-INF:BANDWIDTH=8553453,"))
        #expect(
            lines[4] == "https://media.example/videos/item-1/main.m3u8?MediaSourceId=source-1&VideoCodec=hevc,h264"
                + "&SegmentContainer=mp4&SubtitleStreamIndex=3&ApiKey=token")
    }

    @Test func otherRenditionsInTheMasterGoStraightToTheServer() throws {
        let playlist = """
            #EXTM3U\r
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",URI="audio/english.m3u8"\r
            #EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",NAME="English",INSTREAM-ID="CC1"\r
            #EXT-X-STREAM-INF:BANDWIDTH=1000000,AUDIO="audio"\r
            /videos/item-1/main.m3u8\r

            """
        let lines = SubtitlePlaylists.master(playlist, from: try #require(masterURL)).split(separator: "\n")
        #expect(
            lines[1]
                == #"#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English",URI="https://media.example/videos/item-1/audio/english.m3u8""#
        )
        #expect(lines[2] == #"#EXT-X-MEDIA:TYPE=CLOSED-CAPTIONS,GROUP-ID="cc",NAME="English",INSTREAM-ID="CC1""#)
        #expect(lines[4] == "https://media.example/videos/item-1/main.m3u8")
    }

    @Test func aSubtitlePlaylistBecomesOneSegmentWithoutTheTimeMap() throws {
        let rewritten = SubtitlePlaylists.subtitles(subtitles, from: try #require(subtitlesURL))
        #expect(
            rewritten == """
                #EXTM3U
                #EXT-X-VERSION:3
                #EXT-X-TARGETDURATION:69
                #EXT-X-MEDIA-SEQUENCE:0
                #EXT-X-PLAYLIST-TYPE:VOD
                #EXTINF:68.005,
                https://media.example/videos/item-1/source-1/Subtitles/3/stream.vtt?CopyTimestamps=true\
                &AddVttTimeMap=false&StartPositionTicks=0&EndPositionTicks=680050000&ApiKey=token
                #EXT-X-ENDLIST

                """)
    }

    @Test func rewritingTellsAMasterPlaylistFromASubtitlePlaylist() throws {
        let fromMaster = SubtitlePlaylists.rewrite(master, from: try #require(masterURL))
        #expect(fromMaster.contains("serafin-https://"))
        let fromSubtitles = SubtitlePlaylists.rewrite(subtitles, from: try #require(subtitlesURL))
        #expect(fromSubtitles.contains("AddVttTimeMap=false&StartPositionTicks=0&EndPositionTicks=680050000"))
    }

    @Test func playlistsThatArentJellyfinsOrStillGrowKeepTheirSegments() throws {
        let url = try #require(subtitlesURL)
        let other =
            "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\npart0.vtt\n#EXTINF:10,\npart1.vtt\n#EXT-X-ENDLIST\n"
        #expect(
            SubtitlePlaylists.subtitles(other, from: url)
                == "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\n"
                + "https://media.example/videos/item-1/source-1/Subtitles/3/part0.vtt\n#EXTINF:10,\n"
                + "https://media.example/videos/item-1/source-1/Subtitles/3/part1.vtt\n#EXT-X-ENDLIST\n")

        let growing = subtitles.replacing("#EXT-X-ENDLIST\n", with: "")
        let kept = SubtitlePlaylists.subtitles(growing, from: url)
        #expect(kept.split(separator: "\n").filter { $0.hasPrefix("https://") }.count == 3)
        #expect(kept.contains("AddVttTimeMap=true"))
    }

    @Test func theLoaderHandsAVFoundationTheRewrittenMaster() async throws {
        let host = "loader-master.example"
        StubURLProtocol.stub("\(host):443", path: "/videos/item-1/master.m3u8", .json(200, master))
        let loader = StreamLoader(pinning: nil, configuration: StubURLProtocol.configuration())
        let server = try #require(URL(string: "https://\(host)/videos/item-1/master.m3u8?SegmentContainer=mp4"))
        let asset = AVURLAsset(url: try #require(SubtitlePlaylists.loaderURL(for: server)))
        asset.resourceLoader.setDelegate(loader, queue: StreamLoader.queue)
        let group = try #require(try await asset.loadMediaSelectionGroup(for: .legible))
        #expect(group.options.count == 2)
        #expect(group.options.filter { $0.hasMediaCharacteristic(.containsOnlyForcedSubtitles) }.count == 1)
        #expect(!StubURLProtocol.requests(to: "\(host):443", path: "/videos/item-1/master.m3u8").isEmpty)
    }
}

@Suite struct SubtitleRetimingTests {
    /// English audio, English text the server sends in its HLS stream, and an English image subtitle it burns in.
    private let source = MediaSourceInfo(
        id: "source-1",
        mediaStreams: [
            MediaStream(index: 0, type: .video),
            MediaStream(index: 1, language: "eng", type: .audio),
            MediaStream(codec: "subrip", deliveryMethod: .hls, index: 2, language: "eng", type: .subtitle),
            MediaStream(codec: "pgssub", deliveryMethod: .encode, index: 3, language: "eng", type: .subtitle),
        ]
    )

    private func plan(_ method: PlaybackPlan.Method, subtitle: Int?, container: String = "mp4") throws -> PlaybackPlan {
        PlaybackPlan(
            itemID: "item-1",
            mediaSource: source,
            url: try #require(
                URL(string: "https://media.example/videos/item-1/master.m3u8?SegmentContainer=\(container)")),
            method: method,
            playSessionID: nil,
            startPosition: .zero,
            audioStreamIndex: 1,
            subtitleStreamIndex: subtitle
        )
    }

    @Test func textSubtitlesInTheServersFragmentedMP4StreamAreRetimed() throws {
        #expect(PlayerEngine.retimesSubtitles(in: try plan(.directStream, subtitle: 2)))
        #expect(PlayerEngine.retimesSubtitles(in: try plan(.transcode, subtitle: 2)))
    }

    @Test func streamsWithoutTextSubtitlesOrInMPEGTSPlayAsTheServerSendsThem() throws {
        // No subtitles, or ones burned into the picture: the stream lists no subtitle playlists.
        #expect(!PlayerEngine.retimesSubtitles(in: try plan(.directStream, subtitle: -1)))
        #expect(!PlayerEngine.retimesSubtitles(in: try plan(.transcode, subtitle: 3)))
        // The original file has its subtitles inside it, in time.
        #expect(!PlayerEngine.retimesSubtitles(in: try plan(.directPlay, subtitle: 2)))
        // Jellyfin's time map is right for MPEG-TS.
        #expect(!PlayerEngine.retimesSubtitles(in: try plan(.directStream, subtitle: 2, container: "ts")))
    }
}
