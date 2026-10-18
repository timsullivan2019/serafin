import Foundation
import JellyfinAPI
import SerafinCore

/// A movie or episode saved on this device, which ``PlayerEngine`` plays with no server: the saved file, the tracks
/// inside it, where to keep how far playback got, and for an episode, the one downloaded after it.
public struct DownloadedCopy: Sendable {
    /// The saved file.
    public var file: URL
    /// The server's ID for the version saved.
    public var mediaSourceID: String
    /// The audio and subtitle tracks inside the file, or nil when they weren't saved with it.
    public var tracks: DownloadTracks?
    /// For an episode, the episode after it in its show that's downloaded too, which plays next when the server can't
    /// say which does, as with no connection. Nil for a movie, or when none after it is downloaded.
    public var nextEpisode: BaseItemDto?
    /// Keeps where playback stopped, on this device.
    public var keepPosition: @Sendable (Duration) async -> Void

    /// Creates a copy.
    ///
    /// - Parameters:
    ///   - file: The saved file.
    ///   - mediaSourceID: The server's ID for the version saved.
    ///   - tracks: The audio and subtitle tracks inside the file, or nil when they weren't saved with it.
    ///   - nextEpisode: For an episode, the episode after it in its show that's downloaded too, or nil.
    ///   - keepPosition: Keeps where playback stopped, on this device.
    public init(
        file: URL,
        mediaSourceID: String,
        tracks: DownloadTracks?,
        nextEpisode: BaseItemDto? = nil,
        keepPosition: @escaping @Sendable (Duration) async -> Void
    ) {
        self.file = file
        self.mediaSourceID = mediaSourceID
        self.tracks = tracks
        self.nextEpisode = nextEpisode
        self.keepPosition = keepPosition
    }
}

extension PlaybackPlan {
    /// The plan for playing a downloaded copy: the saved file, played as the original file is, with the tracks inside
    /// it. The audio and subtitles in `options` stand, or else the ones the server chose when the copy was saved.
    /// Subtitles burned into the copy's picture always show, whatever `options` ask for.
    init(itemID: String, copy: DownloadedCopy, options: PlaybackOptions) {
        let tracks = copy.tracks ?? DownloadTracks()
        self.init(
            itemID: itemID,
            mediaSource: tracks.mediaSource(id: copy.mediaSourceID),
            url: copy.file,
            method: .directPlay,
            playSessionID: nil,
            startPosition: options.startPosition,
            audioStreamIndex: options.audioStreamIndex ?? tracks.defaultAudio,
            subtitleStreamIndex: tracks.burnedIn ?? options.subtitleStreamIndex ?? tracks.defaultSubtitles
        )
    }

    /// Whether the plan plays a downloaded copy on this device rather than a stream from the server.
    public var isDownloaded: Bool {
        url.isFileURL
    }
}

extension DownloadTracks {
    /// The tracks inside `source`'s file that the player reads, as it plays an original file: the file's own audio,
    /// and its own subtitles the player draws as text. Subtitles in separate files aren't in the saved file, and the
    /// ones the server burns into the picture can't show from it.
    init(_ source: MediaSourceInfo) {
        let streams = source.mediaStreams ?? []
        let audio = streams.filter { $0.type == .audio && $0.isExternal != true }
        let subtitles = streams.filter {
            $0.type == .subtitle && $0.isExternal != true && $0.deliveryMethod != .encode
        }
        let saved = subtitles.compactMap { DownloadTrack($0) }
        let savedIndexes = Set(saved.map(\.index))
        self.init(
            audio: audio.compactMap { DownloadTrack($0) },
            subtitles: saved,
            defaultAudio: source.defaultAudioStreamIndex,
            defaultSubtitles: source.defaultSubtitleStreamIndex.flatMap { savedIndexes.contains($0) ? $0 : nil }
        )
    }

    /// The version the tracks belong to, as the engine plays it: the saved tracks as the file's streams, and the
    /// subtitles burned into the picture as the server describes subtitles it burns in.
    func mediaSource(id: String) -> MediaSourceInfo {
        let subtitleStreams = subtitles.map { track in
            var stream = track.stream(of: .subtitle)
            if track.index == burnedIn {
                stream.deliveryMethod = .encode
            }
            return stream
        }
        return MediaSourceInfo(
            defaultAudioStreamIndex: defaultAudio,
            defaultSubtitleStreamIndex: defaultSubtitles,
            id: id,
            mediaStreams: audio.map { $0.stream(of: .audio) } + subtitleStreams
        )
    }
}

extension DownloadTrack {
    /// What a download keeps of `stream`, or nil for a stream without an index.
    init?(_ stream: MediaStream) {
        guard let index = stream.index else { return nil }
        self.init(
            index: index,
            codec: stream.codec,
            language: stream.language,
            title: stream.title,
            displayTitle: stream.displayTitle,
            channelLayout: stream.channelLayout,
            isDefault: stream.isDefault == true,
            isForced: stream.isForced == true,
            isHearingImpaired: stream.isHearingImpaired == true,
            isText: stream.isTextSubtitleStream
        )
    }

    /// The track as a stream of `type` inside the saved file.
    func stream(of type: MediaStreamType) -> MediaStream {
        MediaStream(
            channelLayout: channelLayout,
            codec: codec,
            deliveryMethod: type == .subtitle ? .embed : nil,
            displayTitle: displayTitle,
            index: index,
            isDefault: isDefault,
            isExternal: false,
            isForced: isForced,
            isHearingImpaired: isHearingImpaired,
            isTextSubtitleStream: isText,
            language: language,
            title: title,
            type: type
        )
    }
}
