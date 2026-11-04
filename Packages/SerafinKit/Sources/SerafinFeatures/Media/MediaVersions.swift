import Foundation
import JellyfinAPI
import SerafinDesign

/// A movie's or an episode's versions, such as its 4K file and its 1080p one, as the detail screen's version list, the
/// player's Version section and the download menu show them: each with its name, its badges and its size.
enum MediaVersions {
    /// `versions` as the lists show them, in the server's order. A version without an ID can't be asked for, so it's
    /// left out.
    static func choices(for versions: [MediaSourceInfo]) -> [VersionChoice] {
        versions.enumerated().compactMap { offset, version in
            guard let id = version.id, !id.isEmpty else { return nil }
            return VersionChoice(
                id: id,
                title: title(of: version, number: offset + 1),
                badges: MediaBadges.badges(for: version),
                size: size(of: version)
            )
        }
    }

    /// A version's name: the server's, such as "4K Remux", which it takes from the file's name, or else its format,
    /// such as "4K · HEVC · Dolby Vision · Atmos", or else "Version 2", for the `number`th version.
    static func title(of version: MediaSourceInfo, number: Int) -> String {
        if let name = version.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        return format(of: version)
            ?? String(
                localized: "Version \(number)", bundle: .module,
                comment: "A video's version that has no name and no known format, such as Version 2.")
    }

    /// A version's format from its streams: its resolution, video codec, dynamic range and audio, such as
    /// "4K · HEVC · Dolby Vision · Atmos" or "1080p · H.264 · AAC", or nil when the server lists none of them.
    static func format(of version: MediaSourceInfo) -> String? {
        let streams = version.mediaStreams ?? []
        let video = streams.first { $0.type == .video }
        let audio =
            streams.first { $0.type == .audio && $0.index == version.defaultAudioStreamIndex }
            ?? streams.first { $0.type == .audio }
        let parts = [
            video.flatMap(ItemInformation.resolution(of:)),
            video?.codec.flatMap(videoCodecName),
            video?.videoRangeType.flatMap(ItemInformation.rangeName),
            audio.flatMap(audioName),
        ]
        .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// How big a version's file is, such as "4.2 GB", or nil when the server doesn't say.
    static func size(of version: MediaSourceInfo) -> String? {
        guard let bytes = version.size, bytes > 0 else { return nil }
        return DownloadRow.size(Int64(bytes))
    }

    /// The name people know a video codec by, such as "H.264" for h264, or nil when the server names none.
    static func videoCodecName(_ codec: String) -> String? {
        let names = [
            "h264": "H.264", "avc": "H.264", "hevc": "HEVC", "h265": "HEVC", "av1": "AV1", "vp9": "VP9", "vp8": "VP8",
            "mpeg2video": "MPEG-2", "mpeg4": "MPEG-4", "vc1": "VC-1",
        ]
        let codec = codec.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !codec.isEmpty else { return nil }
        return names[codec.lowercased()] ?? codec.uppercased()
    }

    /// The audio's name in a version's format: Atmos when the server names it in the track, as for TrueHD and E-AC-3
    /// with Atmos, otherwise its format, such as "Dolby Digital Plus", or nil when the server names none.
    static func audioName(_ audio: MediaStream) -> String? {
        if MediaBadges.audioBadges(of: audio).contains("Dolby Atmos") {
            return "Atmos"
        }
        guard let codec = audio.codec, !codec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return TrackChoices.formatName(codec)
    }
}
