import Foundation
import Observation
import SerafinCore
import SerafinDesign
import SerafinPlayback
import os

/// The signed-in account's downloads, for the detail screen's download item, the Downloads screen in Settings and the
/// player, which plays a downloaded copy rather than streaming.
///
/// It reads the account's downloads again each time one starts, moves on, finishes, fails, is deleted or keeps where
/// playback stopped, and whether the server lets the account download at all.
@Observable @MainActor final class DownloadCenter {
    /// Where one movie's or episode's download is.
    enum ItemState: Equatable {
        /// Not downloaded.
        case notDownloaded
        /// On its way, with the share that has arrived when the size is known.
        case downloading(Double?)
        /// Saved on the device.
        case finished
        /// Stopped before the end, and why.
        case failed(DownloadFailure?)
    }

    /// A finished download whose file is on the device, ready to play.
    struct PlayableDownload: Sendable {
        /// The download, with where its playback last stopped on this device.
        let record: DownloadRecord
        /// The copy the player plays.
        let copy: DownloadedCopy
    }

    /// The `UserDefaults` key of whether downloads may use cellular data. Off unless the user turns it on.
    nonisolated static let cellularKey = "downloads.cellular"

    /// The account's downloads, newest first.
    private(set) var records: [DownloadRecord] = []
    /// How far each running download has got, by download ID.
    private(set) var progress: [String: Downloads.Progress] = [:]
    /// The bytes the finished downloads take up.
    private(set) var usedBytes: Int64 = 0
    /// Whether the server's policy lets the account download.
    private(set) var isAllowed = false
    /// The last download that couldn't start, shown as an alert.
    var failure: UserMessage?

    private static let logger = Logger(serafinCategory: "downloads")
    @ObservationIgnored private let downloads: Downloads
    @ObservationIgnored private let key: SessionKey
    @ObservationIgnored private let planner: DownloadPlanner
    @ObservationIgnored private let library: LibraryRepository
    @ObservationIgnored private let defaults: UserDefaults

    /// Creates the downloads of the account `key`, and starts following them.
    init(
        downloads: Downloads,
        key: SessionKey,
        planner: DownloadPlanner,
        library: LibraryRepository,
        defaults: UserDefaults = .standard
    ) {
        self.downloads = downloads
        self.key = key
        self.planner = planner
        self.library = library
        self.defaults = defaults
        Task { [weak self, downloads] in
            let changes = await downloads.changes()
            await self?.checkPermission()
            await self?.reload()
            for await _ in changes {
                guard let self else { return }
                await self.reload()
            }
        }
    }

    /// Where the download of `itemID` is.
    func state(of itemID: String) -> ItemState {
        Self.state(of: records.first { $0.itemID == itemID }, progress: progress)
    }

    /// Whether `item` can be downloaded: a movie or an episode from the server, for an account allowed to download.
    func canDownload(_ item: MediaItem) -> Bool {
        isAllowed && item.source != nil && (item.card.kind == .movie || item.card.kind == .episode)
    }

    /// Downloads `item`, or tries a download that failed again.
    func download(_ item: MediaItem) async {
        do {
            switch try await planner.plan(for: item.id) {
            case .original(let original):
                let request = Downloads.Request(
                    itemID: item.id,
                    mediaSourceID: original.mediaSourceID,
                    url: original.url,
                    fileExtension: original.fileExtension,
                    bytes: original.bytes,
                    metadata: DownloadMetadata(item.card),
                    tracks: original.tracks,
                    allowsCellularAccess: defaults.bool(forKey: Self.cellularKey)
                )
                try await downloads.start(request, for: key)
            case .needsConversion:
                failure = .needsConversion
            }
        } catch {
            failure = UserMessage(error)
        }
    }

    /// The finished download of `itemID` with its file on the device, ready to play, or nil when there's none. Its
    /// copy keeps where playback stops in the download.
    func playableDownload(of itemID: String) -> PlayableDownload? {
        guard let record = records.first(where: { $0.itemID == itemID && $0.state == .finished }),
            let file = downloads.fileURL(for: record)
        else { return nil }
        let logger = Self.logger
        let keep: @Sendable (Duration) async -> Void = { [downloads, id = record.id] position in
            do {
                try await downloads.savePosition(position, of: id)
            } catch {
                logger.error("Could not keep a download's position: \(error.localizedDescription, privacy: .private)")
            }
        }
        let copy = DownloadedCopy(
            file: file, mediaSourceID: record.mediaSourceID, tracks: record.tracks, keepPosition: keep)
        return PlayableDownload(record: record, copy: copy)
    }

    /// Deletes the download of `itemID`, stopping it if it's on its way.
    func delete(itemID: String) async {
        guard let record = records.first(where: { $0.itemID == itemID }) else { return }
        await delete(record)
    }

    /// Deletes `record` and its file.
    func delete(_ record: DownloadRecord) async {
        do {
            try await downloads.delete(record.id)
        } catch {
            failure = UserMessage(error)
        }
    }

    private func checkPermission() async {
        isAllowed = (try? await library.canDownload()) ?? false
    }

    private func reload() async {
        do {
            let records = try await downloads.records(for: key)
            var progress: [String: Downloads.Progress] = [:]
            for record in records where record.state == .downloading {
                progress[record.id] = await downloads.progress(of: record.id)
            }
            usedBytes = try await downloads.usedBytes(for: key)
            self.records = records
            self.progress = progress
        } catch {
            Self.logger.error("Could not read the downloads: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Where `record` is, given the progress of the running downloads.
    nonisolated static func state(of record: DownloadRecord?, progress: [String: Downloads.Progress]) -> ItemState {
        guard let record else { return .notDownloaded }
        switch record.state {
        case .downloading: return .downloading(progress[record.id]?.fraction)
        case .finished: return .finished
        case .failed: return .failed(record.failure)
        }
    }
}

extension DownloadMetadata {
    /// What a download keeps of `card`, for showing it with no server to ask.
    init(_ card: MediaCard) {
        self.init(
            title: card.title,
            kind: card.kind == .episode ? .episode : .movie,
            seriesName: card.episode?.seriesTitle,
            seasonNumber: card.episode?.seasonNumber,
            episodeNumber: card.episode?.episodeNumber,
            runtime: card.runtime,
            year: card.year
        )
    }
}
