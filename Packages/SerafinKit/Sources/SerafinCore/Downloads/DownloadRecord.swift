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
        /// The file has arrived, and Serafin is writing the copy the player opens from it, as
        /// ``DownloadRecord/preparation`` says.
        case preparing
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
    /// The saved file's extension, such as `mp4`, so the player knows its container: `mov` for a copy Serafin
    /// writes, or the original's own when it's kept as it arrived because its copy couldn't be written.
    public var fileExtension: String
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
    /// How the saved file is written once the file arrives, for a download that isn't saved as it arrives, until it's
    /// written. Nil for a file saved as it arrives, and once the copy is saved.
    public var preparation: DownloadPreparation?

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
        playback: DownloadPlayback? = nil,
        preparation: DownloadPreparation? = nil
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
        self.preparation = preparation
    }

    /// The account the download belongs to.
    public var key: SessionKey {
        SessionKey(serverID: serverID, userID: userID)
    }

    /// The saved file's name: the ID and the extension.
    public var fileName: String {
        "\(id).\(fileExtension)"
    }

    /// The name the file arrives under: the saved file's, or until a copy is written from it, the ID, `-arrived` and
    /// the extension of what the server sends.
    public var transferName: String {
        guard let preparation else { return fileName }
        return "\(id)-arrived.\(preparation.arrivingExtension)"
    }

    /// The name of the WebVTT file of the subtitles with the server's stream `index`, kept until they're in the copy.
    func subtitlesName(_ index: Int) -> String {
        "\(id)-subtitles-\(index).vtt"
    }

    /// The name of the copy while it's written, which takes ``fileName`` once it's whole.
    var savingName: String {
        "\(id)-saving.mov"
    }

    /// The names of every file the download may have beside the index: the saved file, and until the copy is written,
    /// the file that arrived, its subtitles and the copy as far as it's got.
    var fileNames: Set<String> {
        var names: Set = [fileName]
        if let preparation {
            names.insert(transferName)
            names.insert(savingName)
            names.formUnion(preparation.subtitles.map { subtitlesName($0) })
        }
        return names
    }
}

/// How a download's saved file is written when it isn't saved as it arrives, as when the server converts the video
/// for the player while it's sent, or when subtitles in files of their own go with an original: Serafin copies the
/// file that arrives into a QuickTime movie the player opens, adding subtitles the server sent as WebVTT. Until the
/// copy is written, the file that arrived and the subtitles are kept beside the index, named by the download's ID
/// alone.
public struct DownloadPreparation: Codable, Hashable, Sendable {
    /// The extension of the file the server sends, such as `mp4`.
    public var arrivingExtension: String
    /// The subtitles added to the copy, by the server's stream index, in order. Each is among the download's
    /// ``DownloadRecord/tracks``, after the subtitles inside the file that arrives.
    public var subtitles: [Int]
    /// The Dolby Vision the copy signals, for Dolby Vision video the server copied into a file that doesn't say so,
    /// or nil.
    public var dolbyVision: DolbyVisionConfiguration?
    /// Whether the file that arrives plays as it is, as an original does, so it's kept without the added subtitles
    /// when its copy can't be written.
    public var playsAsItArrives: Bool

    /// Creates a preparation.
    public init(
        arrivingExtension: String,
        subtitles: [Int] = [],
        dolbyVision: DolbyVisionConfiguration? = nil,
        playsAsItArrives: Bool = false
    ) {
        self.arrivingExtension = arrivingExtension
        self.subtitles = subtitles
        self.dolbyVision = dolbyVision
        self.playsAsItArrives = playsAsItArrives
    }

    private enum CodingKeys: String, CodingKey {
        case arrivingExtension, subtitles, dolbyVision, playsAsItArrives
    }

    /// Reads a preparation from the index. One saved before a field was added reads as one without it: no
    /// subtitles to add, and a file that doesn't play as it arrives.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        arrivingExtension = try container.decode(String.self, forKey: .arrivingExtension)
        subtitles = try container.decodeIfPresent([Int].self, forKey: .subtitles) ?? []
        dolbyVision = try container.decodeIfPresent(DolbyVisionConfiguration.self, forKey: .dolbyVision)
        playsAsItArrives = try container.decodeIfPresent(Bool.self, forKey: .playsAsItArrives) ?? false
    }
}

/// How a video is coded in Dolby Vision, as the server reads it from the original's own configuration: what a copy
/// needs to say so the player shows the video as Dolby Vision.
public struct DolbyVisionConfiguration: Codable, Hashable, Sendable {
    /// The configuration's major version.
    public var versionMajor: Int
    /// The configuration's minor version.
    public var versionMinor: Int
    /// The Dolby Vision profile, such as 5 or 8.
    public var profile: Int
    /// The Dolby Vision level, such as 6.
    public var level: Int
    /// Whether the video carries Dolby Vision's metadata for each frame.
    public var hasRPU: Bool
    /// Whether the video carries an enhancement layer.
    public var hasEnhancementLayer: Bool
    /// Whether the video carries a base layer.
    public var hasBaseLayer: Bool
    /// What the base layer plays as without Dolby Vision, as Dolby numbers it: 0 for nothing a player shows as it
    /// is, as in profile 5, 1 for HDR10, 2 for SDR and 4 for HLG.
    public var baseLayerCompatibility: Int

    /// Creates a configuration.
    public init(
        versionMajor: Int = 1,
        versionMinor: Int = 0,
        profile: Int,
        level: Int,
        hasRPU: Bool = true,
        hasEnhancementLayer: Bool = false,
        hasBaseLayer: Bool = true,
        baseLayerCompatibility: Int
    ) {
        self.versionMajor = versionMajor
        self.versionMinor = versionMinor
        self.profile = profile
        self.level = level
        self.hasRPU = hasRPU
        self.hasEnhancementLayer = hasEnhancementLayer
        self.hasBaseLayer = hasBaseLayer
        self.baseLayerCompatibility = baseLayerCompatibility
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
    /// The file arrived, but Serafin couldn't write a copy the player opens from it.
    case preparationFailed
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
    /// The subtitle tracks the player can show from the file, in the file's order, or the subtitles burned into its
    /// picture.
    public var subtitles: [DownloadTrack]
    /// The audio the server chose for the account, by stream index, or nil to leave it to the file.
    public var defaultAudio: Int?
    /// The subtitles the server chose for the account, by stream index, or nil for none.
    public var defaultSubtitles: Int?
    /// The subtitles the server burned into the picture of a video it converted, by stream index, or nil when it
    /// burned in none. They're among ``subtitles``, but they aren't a track: they always show, and no other
    /// subtitles do.
    public var burnedIn: Int?

    /// Creates tracks.
    public init(
        audio: [DownloadTrack] = [],
        subtitles: [DownloadTrack] = [],
        defaultAudio: Int? = nil,
        defaultSubtitles: Int? = nil,
        burnedIn: Int? = nil
    ) {
        self.audio = audio
        self.subtitles = subtitles
        self.defaultAudio = defaultAudio
        self.defaultSubtitles = defaultSubtitles
        self.burnedIn = burnedIn
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

/// Where playback of a download last stopped, so it resumes there with no server to ask, and whether it's been
/// watched.
public struct DownloadPlayback: Codable, Hashable, Sendable {
    /// Where playback stopped on this device, or where the server says the item resumes.
    public var position: Duration
    /// When it stopped there, or when the server says the item was last played.
    public var changed: Date
    /// Whether the item has been watched: as the stop at ``position`` counted, as it was marked, or as the server says.
    /// Nil for a download saved before this was kept, whose stop decides.
    public var isPlayed: Bool?

    /// Creates a stop at `position`.
    ///
    /// - Parameter isPlayed: Whether the item has been watched, or nil for the stop to decide.
    public init(position: Duration, changed: Date = .now, isPlayed: Bool? = nil) {
        self.position = position
        self.changed = changed
        self.isPlayed = isPlayed
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

    /// Whether the item has been watched: as ``isPlayed`` says, or when it doesn't, whether stopping at ``position``
    /// in a video `runtime` long counts as watching it, as Jellyfin records a stop with its standard settings: a stop
    /// in the last 10%, or past the first 5% of a video under five minutes. With the runtime unknown, it doesn't.
    public func isPlayed(runtime: Duration?) -> Bool {
        if let isPlayed { return isPlayed }
        guard position > .zero, let runtime, runtime > .zero else { return false }
        let share = position / runtime
        return share > 0.9 || (share >= 0.05 && runtime < .seconds(300))
    }
}

/// A change to an item's playback made on this device with its download, which the server hasn't heard yet: where the
/// item resumes and whether it's been watched, as the server keeps them, and when it changed, which decides whether a
/// change made on the server meanwhile wins over it.
///
/// It names the account and the item, never a title, the server's address or the token, and it stays when its
/// download is deleted, so progress made offline still reaches the server.
public struct PlaybackChange: Codable, Hashable, Sendable {
    /// The server the item is on.
    public let serverID: String
    /// The user whose playback changed.
    public let userID: String
    /// The movie or episode.
    public let itemID: String
    /// Where the item resumes, as the server keeps it: from the start after a stop near either end, or once watched.
    public var position: Duration
    /// Whether the item has been watched.
    public var isPlayed: Bool
    /// When it changed on this device.
    public var changed: Date

    /// Creates a change to the account `key`'s playback of `itemID`.
    public init(key: SessionKey, itemID: String, position: Duration, isPlayed: Bool, changed: Date) {
        self.serverID = key.serverID
        self.userID = key.userID
        self.itemID = itemID
        self.position = position
        self.isPlayed = isPlayed
        self.changed = changed
    }

    /// The account whose playback changed.
    public var key: SessionKey {
        SessionKey(serverID: serverID, userID: userID)
    }

    /// Whether this changes the account `key`'s playback of `itemID`.
    func isFor(_ itemID: String, key: SessionKey) -> Bool {
        self.itemID == itemID && serverID == key.serverID && userID == key.userID
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
