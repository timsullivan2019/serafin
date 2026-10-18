import Foundation

/// The query of an address Jellyfin offers for a version it repackages or converts, which says what the server will
/// do: the reasons it gives for not playing the original, the codecs it may copy or make, the streams it picks and the
/// bitrates it aims for.
struct TranscodingQuery {
    /// The reasons Jellyfin gives that repackaging fixes, by copying the video and audio into a new container: the
    /// container itself, and HEVC's codec tag, which the copy rewrites as `hvc1`.
    static let repackagingReasons: Set<String> = ["ContainerNotSupported", "VideoCodecTagNotSupported"]

    /// The reasons Jellyfin gives that mean converting the video, as its `StreamBuilder` groups them, and the
    /// container's bitrate, which a video over the bitrate asked for is converted to meet.
    static let videoReasons: Set<String> = [
        "VideoCodecNotSupported", "VideoResolutionNotSupported", "AnamorphicVideoNotSupported",
        "InterlacedVideoNotSupported", "VideoBitDepthNotSupported", "VideoBitrateNotSupported",
        "VideoFramerateNotSupported", "VideoLevelNotSupported", "RefFramesNotSupported", "VideoRangeTypeNotSupported",
        "VideoProfileNotSupported", "VideoRotationNotSupported", "UnknownVideoStreamInfo",
    ]

    /// The reasons Jellyfin gives that mean converting the audio, as its `StreamBuilder` groups them.
    static let audioReasons: Set<String> = [
        "AudioCodecNotSupported", "AudioBitrateNotSupported", "AudioChannelsNotSupported", "AudioProfileNotSupported",
        "AudioSampleRateNotSupported", "SecondaryAudioNotSupported", "AudioBitDepthNotSupported", "AudioIsExternal",
        "UnknownAudioStreamInfo",
    ]

    /// The reasons that come only from the bitrate asked for.
    static let bitrateReasons: Set<String> = ["VideoBitrateNotSupported", "ContainerBitrateExceedsLimit"]

    private let items: [URLQueryItem]

    /// Reads the query of `address`, such as a version's `TranscodingUrl`.
    init(_ address: String) {
        items = URLComponents(string: address)?.queryItems ?? []
    }

    /// The value of `name`, matched in any case, as the server writes names either way.
    func value(_ name: String) -> String? {
        items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// The comma-separated values of `name`, without the space .NET writes after each comma when it lists flags, as
    /// Jellyfin writes its reasons.
    func list(_ name: String) -> [String] {
        (value(name) ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The whole number `name` holds, or nil.
    func integer(_ name: String) -> Int? {
        value(name).flatMap { Int($0) }
    }

    /// The reasons the server gives for not playing the original, such as `ContainerNotSupported`.
    var reasons: [String] {
        list("TranscodeReasons")
    }

    /// Whether the server burns the subtitles it was asked for into the picture, which means converting the video.
    var burnsInSubtitles: Bool {
        value("SubtitleMethod")?.caseInsensitiveCompare("Encode") == .orderedSame
    }

    /// Whether the server adds the subtitles it was asked for to its stream as text, rather than burning them in.
    /// Nil when it doesn't say.
    var addsSubtitles: Bool? {
        value("SubtitleMethod").map { $0.caseInsensitiveCompare("Encode") != .orderedSame }
    }

    /// Whether `codec` is among the codecs `name` lists, such as the video codecs the server may copy or make.
    func lists(_ codec: String, in name: String) -> Bool {
        list(name).contains { $0.caseInsensitiveCompare(codec) == .orderedSame }
    }
}
