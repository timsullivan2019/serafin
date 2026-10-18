import Foundation

/// One movie or episode saved on this device for one account, as ``DownloadStore`` keeps it.
///
/// The record names the item and the server's version of it, never the server's address or the token. Its ``id`` is
/// a UUID generated on this device, which also names the saved file, so nothing identifying ends up in a file name.
public struct DownloadRecord: Codable, Hashable, Sendable, Identifiable {
    /// Where the download is.
    public enum State: String, Codable, Sendable {
        /// The file is on its way.
        case downloading
        /// The whole file is saved and plays offline.
        case finished
        /// The transfer stopped before the end; ``DownloadRecord/failure`` says why. It can be tried again.
        case failed
    }

    /// The download's ID, generated on this device.
    public let id: String
    /// The server the item is on.
    public let serverID: String
    /// The user it was downloaded for.
    public let userID: String
    /// The item, a movie or an episode.
    public let itemID: String
    /// The server's ID for the version saved.
    public let mediaSourceID: String
    /// The saved file's extension, such as `mp4`, so the player knows its container.
    public let fileExtension: String
    /// When the download was asked for.
    public let created: Date
    /// Where the download is.
    public var state: State
    /// Why it failed, when ``state`` is ``State/failed``.
    public var failure: DownloadFailure?
    /// The file's size in bytes: what the server said before the transfer, then the saved size once it's finished.
    public var bytes: Int64?
    /// What the Downloads screen shows for it.
    public var metadata: DownloadMetadata
    /// The audio and subtitle tracks inside the saved file, for the player with no server to ask, or nil when they
    /// weren't saved with it.
    public var tracks: DownloadTracks?
    /// Where playback of the download last stopped: on this device, or else where the server said it had when the
    /// download started. Nil when it hasn't been started.
    public var playback: DownloadPlayback?

    /// Creates a record.
    public init(
        id: String = UUID().uuidString,
        key: SessionKey,
        itemID: String,
        mediaSourceID: String,
        fileExtension: String,
        created: Date = .now,
        state: State = .downloading,
        failure: DownloadFailure? = nil,
        bytes: Int64? = nil,
        metadata: DownloadMetadata,
        tracks: DownloadTracks? = nil,
        playback: DownloadPlayback? = nil
    ) {
        self.id = id
        self.serverID = key.serverID
        self.userID = key.userID
        self.itemID = itemID
        self.mediaSourceID = mediaSourceID
        self.fileExtension = fileExtension
        self.created = created
        self.state = state
        self.failure = failure
        self.bytes = bytes
        self.metadata = metadata
        self.tracks = tracks
        self.playback = playback
    }

    /// The account the download belongs to.
    public var key: SessionKey {
        SessionKey(serverID: serverID, userID: userID)
    }

    /// The saved file's name: the ID and the extension.
    public var fileName: String {
        "\(id).\(fileExtension)"
    }
}

/// Why a download stopped.
public enum DownloadFailure: String, Codable, Sendable {
    /// The server's policy for the user doesn't allow downloading.
    case notAllowed
    /// The item is no longer on the server.
    case notFound
    /// The server answered with an error.
    case serverError
    /// The connection dropped or the server couldn't be reached.
    case network
    /// The device ran out of space.
    case storageFull
    /// The transfer stopped while Serafin wasn't running, as when it's closed from the app switcher.
    case interrupted
}

/// What the Downloads screen, the player, and a download's card and detail screen show for it while there may be no
/// server to ask.
public struct DownloadMetadata: Codable, Hashable, Sendable {
    /// The item's kind.
    public enum Kind: String, Codable, Sendable {
        /// A movie.
        case movie
        /// An episode of a series.
        case episode
    }

    /// The movie's or episode's title.
    public var title: String
    /// Movie or episode.
    public var kind: Kind
    /// The server's ID for the series an episode belongs to.
    public var seriesID: String?
    /// The series an episode belongs to.
    public var seriesName: String?
    /// The season number of an episode.
    public var seasonNumber: Int?
    /// The episode number within its season.
    public var episodeNumber: Int?
    /// The running time.
    public var runtime: Duration?
    /// The year the movie came out or the episode aired.
    public var year: Int?
    /// The age rating, such as "PG-13".
    public var rating: String?
    /// What the movie or episode is about, as plain text.
    public var overview: String?

    /// Creates metadata.
    public init(
        title: String,
        kind: Kind,
        seriesID: String? = nil,
        seriesName: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        runtime: Duration? = nil,
        year: Int? = nil,
        rating: String? = nil,
        overview: String? = nil
    ) {
        self.title = title
        self.kind = kind
        self.seriesID = seriesID
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.runtime = runtime
        self.year = year
        self.rating = rating
        self.overview = overview
    }
}

/// A picture saved with a download, so its card and detail screen show it with no server.
public enum DownloadArtwork: String, CaseIterable, Sendable {
    /// The 2:3 poster cards show: a movie's own, or an episode's show's.
    case poster
    /// The full-bleed picture behind the detail screen: the item's own, or an episode's show's.
    case backdrop
}

/// The audio and subtitle tracks inside a downloaded file, as the server described them when it was downloaded, so the
/// player lists and picks them with no server to ask. A track keeps only what the player shows and matches it by,
/// nothing that holds an address or the token.
public struct DownloadTracks: Codable, Hashable, Sendable {
    /// The audio tracks, in the file's order.
    public var audio: [DownloadTrack]
    /// The subtitle tracks the player can show from the file, in the file's order.
    public var subtitles: [DownloadTrack]
    /// The audio the server chose for the account, by stream index, or nil to leave it to the file.
    public var defaultAudio: Int?
    /// The subtitles the server chose for the account, by stream index, or nil for none.
    public var defaultSubtitles: Int?

    /// Creates tracks.
    public init(
        audio: [DownloadTrack] = [],
        subtitles: [DownloadTrack] = [],
        defaultAudio: Int? = nil,
        defaultSubtitles: Int? = nil
    ) {
        self.audio = audio
        self.subtitles = subtitles
        self.defaultAudio = defaultAudio
        self.defaultSubtitles = defaultSubtitles
    }
}

/// One audio or subtitle track inside a downloaded file.
public struct DownloadTrack: Codable, Hashable, Sendable {
    /// The server's index for the stream, which the player matches tracks by.
    public var index: Int
    /// The codec, such as `aac` or `mov_text`.
    public var codec: String?
    /// The language, as the server names it, such as `eng`.
    public var language: String?
    /// The track's own name in the file, if it has one.
    public var title: String?
    /// The server's description of the track, such as "English - AAC - Stereo".
    public var displayTitle: String?
    /// An audio track's channel layout, such as `5.1`.
    public var channelLayout: String?
    /// Whether the file marks the track as its default.
    public var isDefault: Bool
    /// Whether subtitles are only for foreign speech.
    public var isForced: Bool
    /// Whether subtitles are for the deaf and hard of hearing.
    public var isHearingImpaired: Bool
    /// Whether subtitles are text rather than pictures, when the server said.
    public var isText: Bool?

    /// Creates a track.
    public init(
        index: Int,
        codec: String? = nil,
        language: String? = nil,
        title: String? = nil,
        displayTitle: String? = nil,
        channelLayout: String? = nil,
        isDefault: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isText: Bool? = nil
    ) {
        self.index = index
        self.codec = codec
        self.language = language
        self.title = title
        self.displayTitle = displayTitle
        self.channelLayout = channelLayout
        self.isDefault = isDefault
        self.isForced = isForced
        self.isHearingImpaired = isHearingImpaired
        self.isText = isText
    }
}

/// Where playback of a download last stopped on this device, so it resumes there with no server to ask.
public struct DownloadPlayback: Codable, Hashable, Sendable {
    /// Where playback stopped.
    public var position: Duration
    /// When it stopped there.
    public var changed: Date

    /// Creates a stop at `position`.
    public init(position: Duration, changed: Date = .now) {
        self.position = position
        self.changed = changed
    }

    /// Where the download resumes after stopping at ``position`` in a video `runtime` long, as Jellyfin records a stop
    /// with its standard settings: from the start after a stop in the first 5% or the last 10%, or anywhere in a video
    /// under five minutes, which count as not started or as watched; otherwise where it stopped. With the runtime
    /// unknown, where it stopped.
    public func resumePosition(runtime: Duration?) -> Duration {
        guard position > .zero else { return .zero }
        guard let runtime, runtime > .zero else { return position }
        let share = position / runtime
        return share < 0.05 || share > 0.9 || runtime < .seconds(300) ? .zero : position
    }

    /// Whether stopping at ``position`` in a video `runtime` long counts as watching it, as Jellyfin records a stop
    /// with its standard settings: a stop in the last 10%, or past the first 5% of a video under five minutes. With
    /// the runtime unknown, it doesn't.
    public func isPlayed(runtime: Duration?) -> Bool {
        guard position > .zero, let runtime, runtime > .zero else { return false }
        let share = position / runtime
        return share > 0.9 || (share >= 0.05 && runtime < .seconds(300))
    }
}

/// Failures from downloading that aren't the server's or the network's. SerafinFeatures maps each to a message for
/// the user.
public enum DownloadError: Error, Equatable, Sendable {
    /// The list of downloads couldn't be read or saved.
    case storeUnavailable
    /// The server's policy for the user doesn't allow downloading.
    case notAllowed
    /// The device doesn't have room for the file.
    case notEnoughSpace
}
