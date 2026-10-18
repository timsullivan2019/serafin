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
        metadata: DownloadMetadata
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

/// What the Downloads screen and the player show for a download while there may be no server to ask.
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

    /// Creates metadata.
    public init(
        title: String,
        kind: Kind,
        seriesName: String? = nil,
        seasonNumber: Int? = nil,
        episodeNumber: Int? = nil,
        runtime: Duration? = nil,
        year: Int? = nil
    ) {
        self.title = title
        self.kind = kind
        self.seriesName = seriesName
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.runtime = runtime
        self.year = year
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
