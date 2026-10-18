import Foundation
import JellyfinAPI
import SerafinCore
import os

/// How an item can be downloaded, as the server answers for Serafin's download profile.
public enum DownloadPlan: Sendable, Equatable {
    /// The original file plays on this device as it is, so it's saved as it is, with any subtitles kept in files of
    /// their own added once it arrives.
    case original(PlannedDownload)
    /// The server makes an MP4 the player opens as it sends it, copying the video and audio where the player plays
    /// them and converting them otherwise, and Serafin writes the saved copy from it once it arrives.
    case converted(PlannedDownload)
    /// The item can't be downloaded, and why.
    case refused(DownloadRefusal)
}

/// A file to download, and how it's saved.
public struct PlannedDownload: Sendable, Equatable {
    /// The server's ID for the version downloaded.
    public let mediaSourceID: String
    /// The file's address, without the token, which goes in the `Authorization` header.
    public let url: URL
    /// The extension of the file the server sends, one the player opens.
    public let fileExtension: String
    /// The file's size in bytes when the server said, an estimate of it for a file the server makes as it sends it,
    /// or nil.
    public let bytes: Int64?
    /// The audio and subtitle tracks of the saved file, for playing it with no server to ask.
    public let tracks: DownloadTracks
    /// How the saved file is written once the file arrives, or nil to save it as it arrives.
    public let preparation: Downloads.Preparation?
}

/// Why an item can't be downloaded.
public enum DownloadRefusal: Sendable, Equatable {
    /// The player can't open the video as it is, and the server's policy doesn't let the account have it converted.
    case notAllowed
    /// The video is above the download quality picked, and the server's policy doesn't let the account have it
    /// converted to fit.
    case overQuality
    /// The server offers nothing the player opens, as when it can't convert.
    case unavailable
}

/// Asks the server how an item downloads, and where from.
///
/// It asks for the item's playback info as the player does, but with Serafin's download profile,
/// ``JellyfinAPI/DeviceProfile/serafinDownload(maxBitrate:video:)``, at the download quality's bitrate. When the server
/// says the original direct plays, it's downloaded from `GET /Items/{id}/Download`, which applies the server's
/// download permission and supports ranges, so a stopped transfer can carry on. Otherwise it's downloaded from the MP4
/// address the server offers, which makes the file as it sends it, so a stopped transfer starts again. Either way the
/// token goes in the `Authorization` header, never in the address.
///
/// Before it takes a conversion, it reads the account's policy as the server will apply it. Jellyfin converts the
/// video, burning subtitles in included, only for an account allowed to convert video, and the audio only for one
/// allowed to convert audio; otherwise it copies them, whether or not the player plays them. Copying both into a new
/// container takes the permission to repackage.
///
/// Text subtitles the server sends as WebVTT, from files of their own or from inside a file the player can't open, are
/// fetched as the download starts and added to the saved copy once the file arrives. Subtitles the player shows only
/// burned into the picture are burned in when they're the account's choice and the account may convert video; the
/// copy then shows them and no others.
public struct DownloadPlanner: Sendable {
    /// The bitrate a download asks for at the Maximum quality: 1 Gbps, so no file is turned away for its bitrate.
    static let bitrate = 1_000_000_000
    /// The most subtitle streams added to a download.
    static let maximumAddedSubtitles = 64
    /// The most bytes of one WebVTT file kept: far more than any film's dialogue.
    static let maximumSubtitleBytes = 10 << 20
    /// The most bytes of WebVTT kept for one download, all files together.
    static let maximumSubtitlesBytes = 32 << 20

    private static let logger = Logger(serafinCategory: "downloads")

    private let client: JellyfinClient
    private let userID: String
    private let video: VideoSupport?

    /// Creates a planner.
    ///
    /// - Parameters:
    ///   - client: The signed-in account's client.
    ///   - userID: The account's user ID.
    ///   - video: The AV1 and Dolby Vision the device plays, or nil to read it from the device.
    public init(client: JellyfinClient, userID: String, video: VideoSupport? = nil) {
        self.client = client
        self.userID = userID
        self.video = video
        if video == nil {
            VideoSupport.prepare()
        }
    }

    /// How `itemID` downloads.
    ///
    /// The server judges a version with the subtitles it would show the account, and turns direct play down when
    /// they can't go with the file, as image subtitles in a file of their own can't. A version turned down with
    /// subtitles chosen is asked about again with subtitles off, and saved as it is without them when it then direct
    /// plays. Otherwise the server's conversion with the account's subtitles stands, unless burning them in isn't
    /// allowed, in which case it converts without them. The server takes a subtitle choice only for a version the
    /// request names.
    ///
    /// - Parameters:
    ///   - mediaSourceID: The version to download, or nil for the server's first.
    ///   - maxBitrate: The most bits per second the download may take, from the download quality, or nil for no cap.
    ///   - permissions: What the server's policy lets the account have converted.
    /// - Throws: A ``PlaybackError`` when the server refuses, or SerafinCore's `SerafinError` when it can't be reached
    ///   or no longer accepts the sign-in.
    public func plan(
        for itemID: String,
        mediaSourceID: String? = nil,
        maxBitrate: Int? = nil,
        permissions: ConversionPermissions = .all
    ) async throws -> DownloadPlan {
        let first = try await version(of: itemID, mediaSourceID: mediaSourceID, maxBitrate: maxBitrate)
        if let first, Self.directPlays(first) {
            return .original(try await original(first, itemID: itemID))
        }
        var withoutSubtitles: MediaSourceInfo?
        if let first, let version = Self.versionToAskAgain(first) {
            let again = try await self.version(
                of: itemID, mediaSourceID: version, maxBitrate: maxBitrate, subtitleStreamIndex: -1)
            if let again, Self.directPlays(again) {
                return .original(try await original(again, itemID: itemID))
            }
            withoutSubtitles = again
        }
        guard let first else { return .refused(.unavailable) }
        let capped = maxBitrate != nil
        switch Self.conversion(of: first, capped: capped, permissions: permissions) {
        case .converts(let conversion):
            return .converted(try await converted(conversion, of: first, itemID: itemID))
        case .refused(let refusal):
            return .refused(refusal)
        case .burnsInWithoutPermission:
            // The video is converted to burn the subtitles in, which the account may not have, so it goes without.
            let again: MediaSourceInfo?
            if let withoutSubtitles {
                again = withoutSubtitles
            } else {
                again = try await version(
                    of: itemID, mediaSourceID: first.id, maxBitrate: maxBitrate, subtitleStreamIndex: -1)
            }
            guard let again else { return .refused(.notAllowed) }
            if Self.directPlays(again) {
                return .original(try await original(again, itemID: itemID))
            }
            switch Self.conversion(of: again, capped: capped, permissions: permissions) {
            case .converts(let conversion):
                return .converted(try await converted(conversion, of: again, itemID: itemID))
            case .refused(let refusal):
                return .refused(refusal)
            case .burnsInWithoutPermission:
                return .refused(.notAllowed)
            }
        }
    }

    // MARK: - Asking the server

    /// The version of `itemID` the server's answer is about, as it would download for the account with subtitles
    /// `subtitleStreamIndex`, -1 for none, or nil for the account's: the one asked for, or else the first. Nil when
    /// the server has none to offer.
    private func version(
        of itemID: String,
        mediaSourceID: String?,
        maxBitrate: Int?,
        subtitleStreamIndex: Int? = nil
    ) async throws -> MediaSourceInfo? {
        let bitrate = maxBitrate ?? Self.bitrate
        let body = PlaybackInfoDto(
            allowAudioStreamCopy: true,
            allowVideoStreamCopy: true,
            deviceProfile: .serafinDownload(maxBitrate: bitrate, video: video ?? .current),
            enableDirectPlay: true,
            enableDirectStream: true,
            enableTranscoding: true,
            isAutoOpenLiveStream: false,
            maxStreamingBitrate: bitrate,
            mediaSourceID: mediaSourceID,
            subtitleStreamIndex: subtitleStreamIndex,
            userID: userID
        )
        let response: PlaybackInfoResponse
        do {
            response = try await client.send(Paths.getPostedPlaybackInfo(itemID: itemID, body)).value
        } catch {
            throw SerafinError.translating(error, statuses: [401: .notSignedIn, 404: .notFound])
        }
        switch response.errorCode {
        case nil, .noCompatibleStream:
            break
        case let code?:
            throw PlaybackError(code)
        }
        let sources = response.mediaSources ?? []
        return sources.first { $0.id == mediaSourceID } ?? sources.first
    }

    // MARK: - Originals

    /// Whether `source` is downloaded as it is: a file on the server that direct plays, in a container the player
    /// opens.
    static func directPlays(_ source: MediaSourceInfo) -> Bool {
        source.isSupportsDirectPlay == true && source.`protocol` == .file && source.isRemote != true
            && fileExtension(for: source) != nil
    }

    /// The version to ask about again with subtitles off: `source`, when it's a file the player could open but the
    /// server turned its direct play down with subtitles chosen. Nil otherwise.
    static func versionToAskAgain(_ source: MediaSourceInfo) -> String? {
        guard
            source.isSupportsDirectPlay != true,
            (source.defaultSubtitleStreamIndex ?? -1) >= 0,
            source.`protocol` == .file,
            source.isRemote != true,
            fileExtension(for: source) != nil
        else { return nil }
        return source.id
    }

    /// The download of `source`'s original file, with the subtitles the server sends as WebVTT from files of their
    /// own, which are added to the saved copy.
    private func original(_ source: MediaSourceInfo, itemID: String) async throws -> PlannedDownload {
        let id = source.id ?? itemID
        guard ItemID.isPlain(id), let url = client.url(with: Paths.getDownload(itemID: id)),
            let fileExtension = Self.fileExtension(for: source)
        else { throw PlaybackError.notPlayable }
        var tracks = DownloadTracks(source)
        let inFile = Set(tracks.subtitles.map(\.index))
        let separate = Self.addedSubtitles(of: source).filter { !inFile.contains($0.index ?? -1) }
        let added = try await subtitles(separate, itemID: itemID, mediaSourceID: id)
        tracks.subtitles += added.map(\.track)
        if tracks.defaultSubtitles == nil, let chosen = source.defaultSubtitleStreamIndex,
            added.contains(where: { $0.track.index == chosen })
        {
            tracks.defaultSubtitles = chosen
        }
        return PlannedDownload(
            mediaSourceID: id,
            url: url,
            fileExtension: fileExtension,
            bytes: source.size.map(Int64.init),
            tracks: tracks,
            preparation: added.isEmpty
                ? nil : Downloads.Preparation(subtitles: added.map(\.subtitles), playsAsItArrives: true)
        )
    }

    /// The extension to save `source` with: its file's own when the player opens that, otherwise the first container
    /// the server lists that the player opens. Jellyfin lists an MP4's container as `mov,mp4,m4a,3gp,3g2,mj2`.
    static func fileExtension(for source: MediaSourceInfo) -> String? {
        let playable = Downloads.playableExtensions
        if let path = source.path {
            let ext = URL(filePath: path).pathExtension.lowercased()
            if playable.contains(ext) { return ext }
        }
        let containers = (source.container ?? "").lowercased().split(separator: ",").map(String.init)
        if containers.contains("mp4") { return "mp4" }
        return containers.first { playable.contains($0) }
    }

    // MARK: - Conversions

    /// What the server makes of a version for a download, from the address of the MP4 it offers.
    struct Conversion: Equatable {
        /// The version's ID.
        let mediaSourceID: String
        /// The MP4's address, without the token.
        let address: String
        /// Whether the server copies the video rather than converting it.
        let copiesVideo: Bool
        /// Whether the server copies the audio rather than converting it.
        let copiesAudio: Bool
        /// The audio the MP4 carries, its only audio, by stream index.
        let audioStreamIndex: Int?
        /// The subtitles the server burns into the picture, by stream index, or nil.
        let burnedIn: Int?
        /// The bits per second the server aims for when it converts the video, and the audio.
        let videoBitrate: Int?
        let audioBitrate: Int?
    }

    /// Whether a download of a version can be converted.
    enum ConversionAnswer: Equatable {
        /// The server makes this MP4.
        case converts(Conversion)
        /// The server would burn the account's subtitles into the picture, which takes converting the video, which
        /// the account may not have.
        case burnsInWithoutPermission
        /// It can't be converted, and why.
        case refused(DownloadRefusal)
    }

    /// The reasons for not playing the original that mean converting the video when it's what the server sends, as
    /// Jellyfin's `EncodingHelper.CanStreamCopyVideo` checks the stream against the address: all but its bitrate,
    /// which the address's own bitrate settles.
    private static let videoReasons = TranscodingQuery.videoReasons.subtracting(TranscodingQuery.bitrateReasons)

    /// The reasons that mean converting the audio, as `CanStreamCopyAudio` checks it, apart from its codec and bitrate.
    private static let audioReasons: Set<String> = [
        "AudioChannelsNotSupported", "AudioSampleRateNotSupported", "AudioBitDepthNotSupported",
    ]

    /// Whether the server can convert `source` for a download, and how, as it decides when the transfer starts: it
    /// copies the video when its codec is among those the address lists, nothing else about it is turned down, it
    /// fits the address's size and bitrate, and no subtitles are burned in; and the audio when its codec is listed and
    /// it fits the bitrate. What the account's `permissions` don't allow it to convert, it copies.
    ///
    /// - Parameter capped: Whether the user picked a download quality below Maximum.
    static func conversion(
        of source: MediaSourceInfo,
        capped: Bool,
        permissions: ConversionPermissions
    ) -> ConversionAnswer {
        guard let transcodingURL = source.transcodingURL else {
            // Jellyfin offers no conversion to an account that may have none.
            return .refused(permissions.allowsAny ? .unavailable : .notAllowed)
        }
        guard let id = source.id, ItemID.isPlain(id), let address = addressWithoutToken(transcodingURL),
            URLComponents(string: address)?.path.lowercased().hasSuffix(".mp4") == true
        else { return .refused(.unavailable) }
        let query = TranscodingQuery(transcodingURL)
        let reasons = Set(query.reasons)
        let streams = source.mediaStreams ?? []
        let video = streams.first { $0.type == .video }
        let audioIndex = query.integer("AudioStreamIndex") ?? source.defaultAudioStreamIndex
        let audio = streams.first { $0.type == .audio && $0.index == audioIndex }
        let videoBitrate = query.integer("VideoBitrate")
        let audioBitrate = query.integer("AudioBitrate")

        var videoUnplayable = false
        var videoOverBitrate = false
        if let video {
            videoUnplayable =
                !(video.codec.map { query.lists($0, in: "VideoCodec") } ?? false)
                || !reasons.isDisjoint(with: videoReasons)
                || exceeds(video.width, query.integer("MaxWidth")) || exceeds(video.height, query.integer("MaxHeight"))
            // The server converts video whose bitrate it doesn't know.
            videoOverBitrate = exceeds(video.bitRate, videoBitrate)
        }
        let burnsIn = query.burnsInSubtitles
        if !permissions.videoTranscoding {
            if burnsIn { return .burnsInWithoutPermission }
            if videoUnplayable { return .refused(.notAllowed) }
            // At Maximum, only a video whose bitrate the server doesn't know is over it, and it's copied as it is.
            if videoOverBitrate && capped { return .refused(.overQuality) }
        }
        let copiesVideo = !permissions.videoTranscoding || !(burnsIn || videoUnplayable || videoOverBitrate)

        var audioUnplayable = false
        var audioOverBitrate = false
        if let audio {
            audioUnplayable =
                !(audio.codec.map { query.lists($0, in: "AudioCodec") } ?? false)
                || !reasons.isDisjoint(with: audioReasons)
            if let bitRate = audio.bitRate, let audioBitrate {
                audioOverBitrate = bitRate > audioBitrate
            }
        }
        if audioUnplayable && !permissions.audioTranscoding { return .refused(.notAllowed) }
        let copiesAudio = !permissions.audioTranscoding || !(audioUnplayable || audioOverBitrate)
        // Copying both into the MP4 is repackaging.
        if copiesVideo && copiesAudio && !permissions.remuxing { return .refused(.notAllowed) }

        return .converts(
            Conversion(
                mediaSourceID: id,
                address: address,
                copiesVideo: copiesVideo,
                copiesAudio: copiesAudio,
                audioStreamIndex: audio?.index,
                burnedIn: burnsIn ? query.integer("SubtitleStreamIndex") ?? source.defaultSubtitleStreamIndex : nil,
                videoBitrate: videoBitrate,
                audioBitrate: audioBitrate
            )
        )
    }

    /// Whether `value` is over `limit`, or unknown with a limit to meet, as the server judges whether a stream fits.
    private static func exceeds(_ value: Int?, _ limit: Int?) -> Bool {
        guard let limit else { return false }
        return (value ?? .max) > limit
    }

    /// `address` without the token Jellyfin puts in it, `api_key` or `ApiKey`, which a download sends in the
    /// `Authorization` header instead.
    static func addressWithoutToken(_ address: String) -> String? {
        guard var components = URLComponents(string: address) else { return nil }
        let kept = (components.percentEncodedQueryItems ?? []).filter { item in
            item.name.caseInsensitiveCompare("api_key") != .orderedSame
                && item.name.caseInsensitiveCompare("ApiKey") != .orderedSame
        }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string
    }

    /// The download of `conversion`, the MP4 the server makes of `source`, with the subtitles it sends as WebVTT, or
    /// the ones it burns in.
    private func converted(
        _ conversion: Conversion,
        of source: MediaSourceInfo,
        itemID: String
    ) async throws -> PlannedDownload {
        guard let url = client.url(path: conversion.address) else { throw PlaybackError.notPlayable }
        let streams = source.mediaStreams ?? []
        let audio = streams.first { $0.type == .audio && $0.index == conversion.audioStreamIndex }
            .flatMap { DownloadTrack($0) }
        var tracks = DownloadTracks(audio: audio.map { [$0] } ?? [], defaultAudio: audio?.index)
        var added: [AddedTrack] = []
        if let burnedIn = conversion.burnedIn {
            let burned = streams.first { $0.type == .subtitle && $0.index == burnedIn }.flatMap { DownloadTrack($0) }
            tracks.subtitles = burned.map { [$0] } ?? []
            tracks.defaultSubtitles = burnedIn
            tracks.burnedIn = burnedIn
        } else {
            added = try await subtitles(
                Self.addedSubtitles(of: source), itemID: itemID, mediaSourceID: conversion.mediaSourceID)
            tracks.subtitles = added.map(\.track)
            if let chosen = source.defaultSubtitleStreamIndex, added.contains(where: { $0.track.index == chosen }) {
                tracks.defaultSubtitles = chosen
            }
        }
        let dolbyVision = conversion.copiesVideo ? Self.dolbyVision(of: source, on: video ?? .current) : nil
        return PlannedDownload(
            mediaSourceID: conversion.mediaSourceID,
            url: url,
            fileExtension: "mp4",
            bytes: Self.estimatedBytes(of: source, conversion: conversion),
            tracks: tracks,
            preparation: Downloads.Preparation(
                subtitles: added.map(\.subtitles), dolbyVision: dolbyVision, convertsVideo: !conversion.copiesVideo)
        )
    }

    /// About how many bytes the MP4 of `conversion` takes: what it copies at the bitrate the server reports for it,
    /// and what it converts at the bitrate the server aims for, which is no higher than the original's. Nil when the
    /// bitrates or the running time aren't known.
    static func estimatedBytes(of source: MediaSourceInfo, conversion: Conversion) -> Int64? {
        guard let ticks = source.runTimeTicks, ticks > 0 else { return nil }
        let streams = source.mediaStreams ?? []
        var bitsPerSecond = 0
        if let video = streams.first(where: { $0.type == .video }) {
            // A video converted at more than streaming's own top bitrate, as at the Maximum quality, is aimed at the
            // original's bitrate, which the server must know for the estimate.
            let target = conversion.videoBitrate.flatMap { $0 <= DeviceProfile.uncappedBitrate ? $0 : nil }
            let candidates = conversion.copiesVideo ? [video.bitRate] : [video.bitRate, target]
            guard let rate = candidates.compactMap({ $0 }).min() else { return nil }
            bitsPerSecond += rate
        }
        if let audio = streams.first(where: { $0.type == .audio && $0.index == conversion.audioStreamIndex }) {
            let candidates = conversion.copiesAudio ? [audio.bitRate] : [audio.bitRate, conversion.audioBitrate]
            bitsPerSecond += candidates.compactMap { $0 }.min() ?? 0
        }
        let bytes = Double(ticks) / 10_000_000 * Double(bitsPerSecond) / 8
        return bytes < Double(Int64.max) ? Int64(bytes) : .max
    }

    /// The Dolby Vision of `source`'s video, as the server read it, for a copy to signal on a device that shows it:
    /// profile 5 or 8 in HEVC, or profile 10 in AV1. Nil for anything else, such as profile 7, which AVPlayer doesn't
    /// play.
    static func dolbyVision(of source: MediaSourceInfo, on device: VideoSupport) -> DolbyVisionConfiguration? {
        guard let stream = source.mediaStreams?.first(where: { $0.type == .video }),
            let profile = stream.dvProfile, let level = stream.dvLevel, stream.videoRangeType != .doviInvalid
        else { return nil }
        let reported = stream.dvBlSignalCompatibilityID ?? baseLayerCompatibility(of: stream.videoRangeType)
        let compatibility: Int?
        switch (stream.codec?.lowercased(), profile) {
        case ("hevc", 5) where device.dolbyVision:
            compatibility = 0
        case ("hevc", 8) where device.dolbyVision:
            // Profile 8 always has a base layer other screens show.
            compatibility = reported.flatMap { $0 > 0 ? $0 : nil }
        case ("av1", 10) where device.dolbyVisionInAV1:
            compatibility = reported
        default:
            return nil
        }
        guard let compatibility else { return nil }
        return DolbyVisionConfiguration(
            versionMajor: stream.dvVersionMajor ?? 1,
            versionMinor: stream.dvVersionMinor ?? 0,
            profile: profile,
            level: level,
            hasRPU: (stream.rpuPresentFlag ?? 1) != 0,
            hasEnhancementLayer: (stream.elPresentFlag ?? 0) != 0,
            hasBaseLayer: (stream.blPresentFlag ?? 1) != 0,
            baseLayerCompatibility: compatibility
        )
    }

    /// What a Dolby Vision video's base layer shows as without it, as Dolby numbers it, from the range the server
    /// reports, or nil when the range doesn't say.
    private static func baseLayerCompatibility(of range: VideoRangeType?) -> Int? {
        switch range {
        case .dovi: 0
        case .doviWithHDR10, .doviWithHDR10Plus: 1
        case .doviWithSDR: 2
        case .doviWithHLG: 4
        default: nil
        }
    }

    // MARK: - Subtitles

    /// Subtitles fetched to add to a download: the track they become, and the WebVTT file.
    private struct AddedTrack {
        let track: DownloadTrack
        let webVTT: Data

        var subtitles: Downloads.Subtitles {
            Downloads.Subtitles(index: track.index, webVTT: webVTT)
        }
    }

    /// The subtitle streams of `source` the server sends on their own as WebVTT, in order, up to
    /// ``maximumAddedSubtitles``.
    static func addedSubtitles(of source: MediaSourceInfo) -> [MediaStream] {
        let streams = (source.mediaStreams ?? []).filter {
            $0.type == .subtitle && $0.deliveryMethod == .external && $0.index != nil
        }
        return Array(streams.prefix(maximumAddedSubtitles))
    }

    /// The tracks of `streams` with their WebVTT files, as the server converts them from version `mediaSourceID` of
    /// `itemID`, leaving out subtitles the server can't send, or sends as something other than WebVTT, and any that
    /// would take the download past ``maximumSubtitlesBytes``.
    private func subtitles(
        _ streams: [MediaStream],
        itemID: String,
        mediaSourceID: String
    ) async throws -> [AddedTrack] {
        guard !streams.isEmpty, ItemID.isPlain(itemID), ItemID.isPlain(mediaSourceID) else { return [] }
        var added: [AddedTrack] = []
        var total = 0
        for stream in streams {
            guard let track = DownloadTrack(stream),
                let webVTT = try await webVTT(index: track.index, itemID: itemID, mediaSourceID: mediaSourceID),
                total + webVTT.count <= Self.maximumSubtitlesBytes
            else { continue }
            total += webVTT.count
            added.append(AddedTrack(track: track, webVTT: webVTT))
        }
        return added
    }

    /// The WebVTT file of the subtitles with stream `index`, or nil when the server can't send them, or sends
    /// something else or something too large. The file goes to disk first, so its size is known before it's read.
    private func webVTT(index: Int, itemID: String, mediaSourceID: String) async throws -> Data? {
        let request = Paths.getSubtitle(
            routeItemID: itemID, routeMediaSourceID: mediaSourceID, routeIndex: index, routeFormat: "vtt")
        let file: URL
        do {
            file = try await client.download(for: request).value
        } catch {
            let translated = SerafinError.translating(error, statuses: [401: .notSignedIn])
            if case SerafinError.unexpectedResponse = translated {
                Self.logger.error("The server couldn't send a download's subtitles")
                return nil
            }
            throw translated
        }
        defer { try? FileManager.default.removeItem(at: file) }
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            size <= Self.maximumSubtitleBytes,
            let data = try? Data(contentsOf: file),
            Self.isWebVTT(data)
        else { return nil }
        return data
    }

    /// Whether `data` is a WebVTT file: it starts with `WEBVTT`, after a byte order mark if it has one.
    static func isWebVTT(_ data: Data) -> Bool {
        var start = data.prefix(9)
        if start.starts(with: [0xEF, 0xBB, 0xBF]) {
            start = start.dropFirst(3)
        }
        return start.starts(with: Array("WEBVTT".utf8))
    }
}
