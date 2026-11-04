import Foundation
import JellyfinAPI
import SerafinCore
import os

/// Asks the server how to play an item, given Serafin's ``JellyfinAPI/DeviceProfile/serafin(maxBitrate:video:)``,
/// and turns the answer into a ``PlaybackPlan``.
public struct PlaybackNegotiator: Sendable {
    private static let logger = Logger(serafinCategory: "negotiation")

    private let client: JellyfinClient
    private let userID: String
    private let video: VideoSupport?

    /// Creates a negotiator.
    ///
    /// - Parameters:
    ///   - client: The signed-in account's client.
    ///   - userID: The account's user ID.
    ///   - video: The AV1 and Dolby Vision the device plays, or nil to read it from the device, away from the main
    ///     thread. The reading starts now, in the background, so the first plan needn't wait for it.
    public init(client: JellyfinClient, userID: String, video: VideoSupport? = nil) {
        self.client = client
        self.userID = userID
        self.video = video
        if video == nil {
            VideoSupport.prepare()
        }
    }

    /// The plan for playing `itemID` with `options`: the version they name, or else the one ``VersionRanking`` prefers.
    ///
    /// A version the server no longer has, as one picked before its file was renamed, gives way to the one the ranking
    /// prefers, with that version's own audio and subtitles.
    ///
    /// - Throws: A ``PlaybackError`` when the server can't offer a playable version, or SerafinCore's
    ///   `SerafinError` when it can't be reached or no longer accepts the sign-in.
    public func plan(for itemID: String, options: PlaybackOptions) async throws -> PlaybackPlan {
        var options = options
        var response = try await playbackInfo(for: itemID, options: options)
        if options.mediaSourceID != nil, Self.lacksNamedVersion(response) {
            Self.logger.debug("The version asked for has gone, asking for the preferred one")
            options.mediaSourceID = nil
            options.audioStreamIndex = nil
            options.subtitleStreamIndex = nil
            response = try await playbackInfo(for: itemID, options: options)
        }
        return try Self.plan(from: response, itemID: itemID, options: options, client: client)
    }

    /// Whether the server's answer to a request naming a version says it has no such version: Jellyfin answers with no
    /// versions and `NoCompatibleStream`, which it gives for nothing else (`MediaInfoHelper.GetPlaybackInfo` in 10.11
    /// and 12.x).
    static func lacksNamedVersion(_ response: PlaybackInfoResponse) -> Bool {
        response.errorCode == .noCompatibleStream && (response.mediaSources ?? []).isEmpty
    }

    /// Every version of `itemID`, in the server's order, with how the server would send each to this device with
    /// `options`, whatever version they name: what ``plan(for:options:)`` chooses from when they name none.
    ///
    /// - Throws: A ``PlaybackError`` when the server refuses, or SerafinCore's `SerafinError` when it can't be reached
    ///   or no longer accepts the sign-in.
    public func offers(for itemID: String, options: PlaybackOptions) async throws -> [VersionOffer] {
        var options = options
        options.mediaSourceID = nil
        let response = try await playbackInfo(for: itemID, options: options)
        if let code = response.errorCode {
            throw PlaybackError(code)
        }
        return Self.offers(in: response, options: options)
    }

    /// The server's answer for playing `itemID` with `options`.
    private func playbackInfo(for itemID: String, options: PlaybackOptions) async throws -> PlaybackInfoResponse {
        let body = PlaybackInfoDto(
            allowAudioStreamCopy: true,
            allowVideoStreamCopy: true,
            audioStreamIndex: options.audioStreamIndex,
            deviceProfile: .serafin(maxBitrate: options.maxBitrate, video: video ?? .current),
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
        do {
            return try await client.send(Paths.getPostedPlaybackInfo(itemID: itemID, body)).value
        } catch {
            throw SerafinError.translating(error, statuses: [401: .notSignedIn, 404: .notFound])
        }
    }

    /// Chooses a version and a delivery from the server's answer: the version `options` name, or else the one
    /// ``VersionRanking`` prefers, as the original file when the server allows it, otherwise the HLS stream the server
    /// prepared, which repackages or converts.
    static func plan(
        from response: PlaybackInfoResponse,
        itemID: String,
        options: PlaybackOptions,
        client: JellyfinClient
    ) throws -> PlaybackPlan {
        if let code = response.errorCode {
            throw PlaybackError(code)
        }
        let offers = Self.offers(in: response, options: options)
        let named = options.mediaSourceID.flatMap { id in offers.first { $0.id == id } }
        guard
            let offer = named ?? VersionRanking.preferred(among: offers),
            let delivery = offer.delivery
        else {
            throw PlaybackError.notPlayable
        }
        let source = offer.source
        let method = delivery.method
        let url =
            method == .directPlay
            ? staticURL(for: source, itemID: itemID, client: client)
            : source.transcodingURL.flatMap { client.url(path: $0) }
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
        let query = TranscodingQuery(transcodingURL)
        let reasons = query.reasons
        let repackaging = TranscodingQuery.repackagingReasons
        let subtitleAdded = query.addsSubtitles == true
        let fixedByRepackaging = { (reason: String) in
            repackaging.contains(reason) || (reason == "SubtitleCodecNotSupported" && subtitleAdded)
        }
        guard !reasons.isEmpty, reasons.allSatisfy(fixedByRepackaging) else { return false }
        let streams = source.mediaStreams ?? []
        if let codec = streams.first(where: { $0.type == .video })?.codec, !query.lists(codec, in: "VideoCodec") {
            return false
        }
        let audioIndex = audioStreamIndex ?? query.integer("AudioStreamIndex") ?? source.defaultAudioStreamIndex
        if let codec = streams.first(where: { $0.type == .audio && $0.index == audioIndex })?.codec,
            !query.lists(codec, in: "AudioCodec")
        {
            return false
        }
        return true
    }

    /// The versions in the server's answer, in its order, with how the server would send each.
    static func offers(in response: PlaybackInfoResponse, options: PlaybackOptions) -> [VersionOffer] {
        (response.mediaSources ?? []).map { VersionOffer(source: $0, delivery: delivery(of: $0, options: options)) }
    }

    /// How the server would send `source` with `options`, as its answer says: the original file when it allows that,
    /// otherwise its HLS stream, which repackages or converts, or nil when it offers neither.
    static func delivery(of source: MediaSourceInfo, options: PlaybackOptions) -> VersionOffer.Delivery? {
        if options.allowsDirectPlay, source.isSupportsDirectPlay == true {
            return .original
        }
        guard let transcodingURL = source.transcodingURL else { return nil }
        if source.isSupportsDirectStream == true
            || copiesVideoAndAudio(transcodingURL, from: source, audioStreamIndex: options.audioStreamIndex)
        {
            return .repackaged
        }
        return copiesVideo(transcodingURL, from: source) ? .audioConverted : .videoConverted
    }

    /// Whether the server's HLS stream copies the original video, whatever it does with the audio: every reason it
    /// gives must be one that leaves the picture alone, and the stream must accept the original video codec. Burning a
    /// subtitle into the picture means converting the video.
    static func copiesVideo(_ transcodingURL: String, from source: MediaSourceInfo) -> Bool {
        let query = TranscodingQuery(transcodingURL)
        let reasons = query.reasons
        let subtitleAdded = query.addsSubtitles == true
        let keepsVideo = { (reason: String) in
            TranscodingQuery.repackagingReasons.contains(reason) || TranscodingQuery.audioReasons.contains(reason)
                || (reason == "SubtitleCodecNotSupported" && subtitleAdded)
        }
        guard !reasons.isEmpty, reasons.allSatisfy(keepsVideo) else { return false }
        if let codec = source.mediaStreams?.first(where: { $0.type == .video })?.codec,
            !query.lists(codec, in: "VideoCodec")
        {
            return false
        }
        return true
    }

    /// What the server said about streaming a version: its container and codecs, and the reasons it gave for not
    /// playing the original, such as "ContainerNotSupported". Codec names only, nothing that identifies the item.
    static func describe(_ source: MediaSourceInfo) -> String {
        let streams = source.mediaStreams ?? []
        let video = streams.first { $0.type == .video }
        let audio =
            streams.first { $0.type == .audio && $0.index == source.defaultAudioStreamIndex }
            ?? streams.first { $0.type == .audio }
        let reasons = source.transcodingURL.flatMap { TranscodingQuery($0).value("TranscodeReasons") }
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
