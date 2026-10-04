import Foundation
import JellyfinAPI
import SerafinCore
import os

/// Asks the server how to play an item, given Serafin's ``JellyfinAPI/DeviceProfile/serafin(maxBitrate:)``, and
/// turns the answer into a ``PlaybackPlan``.
public struct PlaybackNegotiator: Sendable {
    private static let logger = Logger(serafinCategory: "negotiation")

    private let client: JellyfinClient
    private let userID: String

    /// Creates a negotiator.
    ///
    /// - Parameters:
    ///   - client: The signed-in account's client.
    ///   - userID: The account's user ID.
    public init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
    }

    /// The plan for playing `itemID` with `options`.
    ///
    /// - Throws: A ``PlaybackError`` when the server can't offer a playable version, or SerafinCore's
    ///   `SerafinError` when it can't be reached or no longer accepts the sign-in.
    public func plan(for itemID: String, options: PlaybackOptions) async throws -> PlaybackPlan {
        let body = PlaybackInfoDto(
            allowAudioStreamCopy: true,
            allowVideoStreamCopy: true,
            audioStreamIndex: options.audioStreamIndex,
            deviceProfile: .serafin(maxBitrate: options.maxBitrate),
            enableDirectPlay: options.allowsDirectPlay,
            enableDirectStream: true,
            enableTranscoding: true,
            isAutoOpenLiveStream: false,
            maxStreamingBitrate: options.maxBitrate ?? DeviceProfile.uncappedBitrate,
            mediaSourceID: options.mediaSourceID,
            startTimeTicks: Ticks.from(options.startPosition),
            subtitleStreamIndex: options.subtitleStreamIndex,
            userID: userID
        )
        let response: PlaybackInfoResponse
        do {
            response = try await client.send(Paths.getPostedPlaybackInfo(itemID: itemID, body)).value
        } catch {
            throw SerafinError.translating(error, statuses: [401: .notSignedIn, 404: .notFound])
        }
        return try Self.plan(from: response, itemID: itemID, options: options, client: client)
    }

    /// Chooses a version and a delivery from the server's answer: the original file when the server allows it,
    /// otherwise the HLS stream the server prepared, which repackages or converts.
    static func plan(
        from response: PlaybackInfoResponse,
        itemID: String,
        options: PlaybackOptions,
        client: JellyfinClient
    ) throws -> PlaybackPlan {
        if let code = response.errorCode {
            throw PlaybackError(code)
        }
        let sources = response.mediaSources ?? []
        guard let source = sources.first(where: { $0.id == options.mediaSourceID }) ?? sources.first else {
            throw PlaybackError.notPlayable
        }

        let method: PlaybackPlan.Method
        let url: URL?
        if options.allowsDirectPlay, source.isSupportsDirectPlay == true {
            method = .directPlay
            url = staticURL(for: source, itemID: itemID, client: client)
        } else if let transcodingURL = source.transcodingURL {
            let repackages =
                source.isSupportsDirectStream == true
                || copiesVideoAndAudio(transcodingURL, from: source, audioStreamIndex: options.audioStreamIndex)
            method = repackages ? .directStream : .transcode
            url = client.url(path: transcodingURL)
        } else {
            throw PlaybackError.notPlayable
        }
        guard let url else { throw PlaybackError.notPlayable }
        if method != .directPlay {
            logger.debug("\(Self.describe(source), privacy: .public)")
        }
        return PlaybackPlan(
            itemID: itemID,
            mediaSource: source,
            url: url,
            method: method,
            playSessionID: response.playSessionID,
            startPosition: options.startPosition,
            audioStreamIndex: options.audioStreamIndex ?? source.defaultAudioStreamIndex,
            subtitleStreamIndex: options.subtitleStreamIndex ?? source.defaultSubtitleStreamIndex
        )
    }

    /// The reasons Jellyfin gives that its HLS stream fixes by copying the video and audio into a new container: the
    /// container itself, and HEVC's codec tag, which the server rewrites as `hvc1` as it copies.
    static let repackagingReasons: Set<String> = ["ContainerNotSupported", "VideoCodecTagNotSupported"]

    /// Whether the server's HLS stream copies the original video and audio rather than converting them.
    ///
    /// Jellyfin sends repackaging and conversion through the same HLS address and calls both a transcode, so this
    /// follows the server's own rules: every reason it gives must be one repackaging fixes, and the stream must accept
    /// the original video and audio codecs. A subtitle the player can't read from the file doesn't count against it
    /// when the server adds the subtitle to the stream as text; burning it into the picture means converting the video.
    ///
    /// - Parameters:
    ///   - transcodingURL: The server's HLS address for the version.
    ///   - source: The version.
    ///   - audioStreamIndex: The audio asked for, or nil for the server's choice.
    static func copiesVideoAndAudio(_ transcodingURL: String, from source: MediaSourceInfo, audioStreamIndex: Int?)
        -> Bool
    {
        let query = URLComponents(string: transcodingURL)?.queryItems ?? []
        let reasons = list("TranscodeReasons", in: query)
        let subtitleIsAdded = value("SubtitleMethod", in: query).map {
            $0.caseInsensitiveCompare("Encode") != .orderedSame
        }
        let fixedByRepackaging = { (reason: String) in
            repackagingReasons.contains(reason) || (reason == "SubtitleCodecNotSupported" && subtitleIsAdded == true)
        }
        guard !reasons.isEmpty, reasons.allSatisfy(fixedByRepackaging) else { return false }
        let streams = source.mediaStreams ?? []
        if let codec = streams.first(where: { $0.type == .video })?.codec,
            !list("VideoCodec", in: query).contains(where: { $0.caseInsensitiveCompare(codec) == .orderedSame })
        {
            return false
        }
        let audioIndex =
            audioStreamIndex ?? value("AudioStreamIndex", in: query).flatMap { Int($0) }
            ?? source.defaultAudioStreamIndex
        if let codec = streams.first(where: { $0.type == .audio && $0.index == audioIndex })?.codec,
            !list("AudioCodec", in: query).contains(where: { $0.caseInsensitiveCompare(codec) == .orderedSame })
        {
            return false
        }
        return true
    }

    /// The value of the query item `name`, matched in any case, as the server writes names either way.
    private static func value(_ name: String, in query: [URLQueryItem]) -> String? {
        query.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The comma-separated values of the query item `name`.
    private static func list(_ name: String, in query: [URLQueryItem]) -> [String] {
        (value(name, in: query) ?? "").split(separator: ",").map(String.init)
    }

    /// What the server said about streaming a version: its container and codecs, and the reasons it gave for not
    /// playing the original, such as "ContainerNotSupported". Codec names only, nothing that identifies the item.
    static func describe(_ source: MediaSourceInfo) -> String {
        let streams = source.mediaStreams ?? []
        let video = streams.first { $0.type == .video }
        let audio =
            streams.first { $0.type == .audio && $0.index == source.defaultAudioStreamIndex }
            ?? streams.first { $0.type == .audio }
        let query = source.transcodingURL.flatMap(URLComponents.init(string:))?.queryItems ?? []
        let reasons = value("TranscodeReasons", in: query)
        let parts = [
            "container \(source.container ?? "?")",
            "video \(video?.codec ?? "?") \(video?.codecTag ?? "-") \(video?.videoRangeType?.rawValue ?? "-")",
            "audio \(audio?.codec ?? "?")",
            "reasons \(reasons ?? "none given")",
        ]
        return parts.joined(separator: ", ")
    }

    /// The address of the original file, with the token AVPlayer can't send as a header.
    private static func staticURL(for source: MediaSourceInfo, itemID: String, client: JellyfinClient) -> URL? {
        var parameters = Paths.GetVideoStreamParameters()
        parameters.isStatic = true
        parameters.mediaSourceID = source.id
        parameters.deviceID = client.configuration.deviceID
        parameters.tag = source.eTag
        return client.url(with: Paths.getVideoStream(itemID: itemID, parameters: parameters), queryAPIKey: true)
    }
}
