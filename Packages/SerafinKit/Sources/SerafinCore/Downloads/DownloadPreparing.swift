import Foundation

/// Writes a download's saved file from the file that arrived and the subtitles saved with it, once its transfer is
/// over, as when the server converted the video for the player while it downloaded. SerafinPlayback provides the
/// app's, and ``Downloads`` calls it.
public protocol DownloadPreparing: Sendable {
    /// Writes `job`'s saved file, a QuickTime movie, at ``DownloadPreparationJob/output``.
    ///
    /// - Throws: ``DownloadPreparationError`` when the saved file can't be written, or `CancellationError` when the
    ///   calling task is cancelled, as when Serafin runs out of time in the background. A cancelled copy is written
    ///   again later.
    func prepare(_ job: DownloadPreparationJob) async throws
}

/// What preparing a download works from and where it writes.
public struct DownloadPreparationJob: Sendable {
    /// The file that arrived.
    public var arrived: URL
    /// The subtitles to add after the arrived file's own, in order.
    public var subtitles: [AddedSubtitles]
    /// Where to write the saved file. Anything there already is replaced.
    public var output: URL

    /// Creates a job.
    public init(arrived: URL, subtitles: [AddedSubtitles], output: URL) {
        self.arrived = arrived
        self.subtitles = subtitles
        self.output = output
    }
}

/// Subtitles saved as a WebVTT file, to add to a download's saved file as a track of their own.
public struct AddedSubtitles: Sendable, Equatable {
    /// The track they become: its language, and whether it's forced or for the deaf and hard of hearing.
    public var track: DownloadTrack
    /// The WebVTT file, as the server sent it.
    public var file: URL

    /// Creates subtitles to add.
    public init(track: DownloadTrack, file: URL) {
        self.track = track
        self.file = file
    }
}

/// Why a download's saved file couldn't be written.
public enum DownloadPreparationError: Error, Equatable, Sendable {
    /// The device ran out of space.
    case storageFull
    /// The file that arrived isn't a video the copy can be written from.
    case unreadable
}
