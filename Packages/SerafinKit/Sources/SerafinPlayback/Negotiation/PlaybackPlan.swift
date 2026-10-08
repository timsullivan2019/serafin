import Foundation
import JellyfinAPI

/// What the player is asked to play for one item, and what the server needs to know about it.
public struct PlaybackPlan: Sendable {
    /// How the server delivers the item.
    public enum Method: Sendable, Equatable {
        /// The original file, untouched.
        case directPlay
        /// The original video and audio, repackaged into HLS.
        case directStream
        /// Video, audio or both converted by the server.
        case transcode

        /// The same method in the server's terms, for progress reports.
        var playMethod: PlayMethod {
            switch self {
            case .directPlay: .directPlay
            case .directStream: .directStream
            case .transcode: .transcode
            }
        }
    }

    /// The item being played.
    public let itemID: String
    /// The version of the item chosen, with its audio and subtitle streams.
    public let mediaSource: MediaSourceInfo
    /// What AVPlayer loads. It carries the access token, because AVPlayer can't add headers to HLS segment
    /// requests, so it is never logged.
    public let url: URL
    /// How the server delivers it.
    public let method: Method
    /// The server's ID for this playback, which progress reports repeat.
    public let playSessionID: String?
    /// Where playback starts.
    public let startPosition: Duration
    /// The audio stream asked for, if one was.
    public let audioStreamIndex: Int?
    /// The subtitle stream asked for, if one was.
    public let subtitleStreamIndex: Int?
    /// The subtitle stream the server made the stream for, when a switch in place has since changed
    /// ``subtitleStreamIndex``. Nil when they're the same.
    var negotiatedSubtitles: Int?

    /// The subtitle stream the server made the stream for, which decides the subtitles the stream carries as text.
    var streamSubtitleStreamIndex: Int? {
        negotiatedSubtitles ?? subtitleStreamIndex
    }

    /// The chosen version's ID.
    public var mediaSourceID: String {
        mediaSource.id ?? itemID
    }

    /// The streams of one kind in the chosen version, such as its audio tracks.
    public func streams(_ type: MediaStreamType) -> [MediaStream] {
        (mediaSource.mediaStreams ?? []).filter { $0.type == type }
    }

    /// The language of the audio playing, as the server names it, such as "eng", or nil when it's unknown.
    public var audioLanguage: String? {
        let index = audioStreamIndex ?? mediaSource.defaultAudioStreamIndex
        return streams(.audio).first { $0.index == index }?.language
    }
}

/// What to ask the server for when negotiating playback.
public struct PlaybackOptions: Sendable, Equatable {
    /// The most bits per second to stream, or nil for no cap.
    public var maxBitrate: Int?
    /// Where to start.
    public var startPosition: Duration
    /// The audio stream to play, or nil for the server's default.
    public var audioStreamIndex: Int?
    /// The subtitle stream to show, or nil for the server's default. Pass -1 to turn subtitles off.
    public var subtitleStreamIndex: Int?
    /// The version to play, or nil for the server's first.
    public var mediaSourceID: String?
    /// Whether the original file may be played as it is. Turned off when a subtitle can only be shown through HLS.
    public var allowsDirectPlay: Bool

    /// Creates options.
    public init(
        maxBitrate: Int? = nil,
        startPosition: Duration = .zero,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        mediaSourceID: String? = nil,
        allowsDirectPlay: Bool = true
    ) {
        self.maxBitrate = maxBitrate
        self.startPosition = startPosition
        self.audioStreamIndex = audioStreamIndex
        self.subtitleStreamIndex = subtitleStreamIndex
        self.mediaSourceID = mediaSourceID
        self.allowsDirectPlay = allowsDirectPlay
    }
}
