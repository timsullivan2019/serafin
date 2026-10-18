import Foundation
import JellyfinAPI
import Observation
import SerafinCore
import SerafinDesign
import SerafinPlayback
import os

/// The signed-in account's downloads, for the detail screen's download item, the Downloads screen in Settings, the
/// player, which plays a downloaded copy rather than streaming, and the screens that show downloads with no server.
///
/// It reads the account's downloads again each time one starts, moves on, finishes, fails, is deleted, saves a picture
/// or keeps where playback stopped, and whether the server lets the account download at all. Each download keeps what
/// its card and page show, with its poster and backdrop, so they show with no server. Where playback of a download
/// stops, and a download marked watched with no server, reach the server once it answers.
@Observable @MainActor final class DownloadCenter {
    /// Where one movie's or episode's download is.
    enum ItemState: Equatable {
        /// Not downloaded.
        case notDownloaded
        /// On its way, with the share that has arrived when the size is known.
        case downloading(Double?)
        /// Arrived, while Serafin writes the copy the player opens from it.
        case preparing
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
    /// The finished downloads whose files are on the device, newest first, as screens show them with no server, from
    /// what was saved with them.
    private(set) var offlineItems: [MediaItem] = []
    /// The last download that couldn't start, shown as an alert.
    var failure: UserMessage?

    private static let logger = Logger(serafinCategory: "downloads")
    @ObservationIgnored private let downloads: Downloads
    @ObservationIgnored private let key: SessionKey
    @ObservationIgnored private let planner: DownloadPlanner
    @ObservationIgnored private let library: LibraryRepository
    @ObservationIgnored private let artwork: Artwork?
    @ObservationIgnored private let sync: PlaybackSync?
    @ObservationIgnored private let defaults: UserDefaults
    /// Whether the server has said if the account may download, which it can't while it's out of reach.
    @ObservationIgnored private var knowsPermission = false

    /// Creates the downloads of the account `key`, and starts following them.
    ///
    /// - Parameters:
    ///   - artwork: Loads the pictures each download saves, or nil to save none.
    ///   - sync: Sends the server the changes to playback made with the downloads, or nil to send none.
    init(
        downloads: Downloads,
        key: SessionKey,
        planner: DownloadPlanner,
        library: LibraryRepository,
        artwork: Artwork? = nil,
        sync: PlaybackSync? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.downloads = downloads
        self.key = key
        self.planner = planner
        self.library = library
        self.artwork = artwork
        self.sync = sync
        self.defaults = defaults
        Task { [weak self, downloads] in
            let changes = await downloads.changes()
            await self?.reload()
            for await _ in changes {
                guard let self else { return }
                await self.reload()
            }
        }
        // Apart from reading the downloads, which show at once even when the server takes long to answer.
        Task { [weak self] in await self?.checkPermission() }
    }

    /// Where the download of `itemID` is.
    func state(of itemID: String) -> ItemState {
        Self.state(of: records.first { $0.itemID == itemID }, progress: progress)
    }

    /// Whether `item` can be downloaded: a movie or an episode from the server, for an account allowed to download.
    func canDownload(_ item: MediaItem) -> Bool {
        isAllowed && item.source != nil && !item.isSaved && (item.card.kind == .movie || item.card.kind == .episode)
    }

    /// Downloads `item`, or tries a download that failed again, and saves its poster and backdrop with it.
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
                    playback: Self.serverPlayback(of: item),
                    allowsCellularAccess: defaults.bool(forKey: Self.cellularKey)
                )
                let record = try await downloads.start(request, for: key)
                await saveArtwork(of: item, for: record)
            case .needsConversion:
                failure = .needsConversion
            }
        } catch {
            failure = UserMessage(error)
        }
    }

    /// What the page of the downloaded item `itemID` shows with no server, from what was saved with it, or nil when
    /// it isn't downloaded or its file has gone. The downloads are read afresh, so it has where playback last stopped.
    func savedDetails(of itemID: String) async -> ItemDetails? {
        do {
            let records = try await downloads.records(for: key)
            return ItemDetails.saved(itemID, among: records.compactMap { offlineItem(of: $0) })
        } catch {
            Self.logger.error("Could not read the downloads: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }

    /// Saves the pictures missing from `item`'s download, as when they couldn't load when it started. Does nothing
    /// for an item that isn't downloaded, or one shown from what was saved with it, which has no server to ask.
    func saveMissingArtwork(of item: MediaItem) async {
        guard !item.isSaved, let record = records.first(where: { $0.itemID == item.id }),
            DownloadArtwork.allCases.contains(where: { downloads.artworkURL($0, for: record) == nil })
        else { return }
        await saveArtwork(of: item, for: record)
    }

    /// Asks the server whether the account may download, when it hasn't said yet, as when Serafin started with no
    /// connection.
    func checkPermissionIfUnknown() async {
        guard !knowsPermission else { return }
        await checkPermission()
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

    /// Writes the copies of the downloads that arrived while Serafin couldn't, as when iOS stopped it in the
    /// background first.
    func prepareArrived() async {
        await downloads.prepareArrived()
    }

    /// Sends the server the changes to playback made with the downloads that it hasn't heard yet, and has each
    /// download take on what the server has, or does nothing while the server can't be reached. Returns whether the
    /// server took any change, after which screens showing its progress should load again.
    @discardableResult
    func syncPlayback() async -> Bool {
        guard let sync, await sync.run() else { return false }
        // Answers from before would show the progress as it was.
        await library.clearCache()
        return true
    }

    /// Marks the downloaded `item` watched or not on the device, as when it shows with no server, and sends the mark
    /// once the server answers.
    func setPlayed(_ isPlayed: Bool, ofSaved item: MediaItem) async throws {
        try await downloads.setPlayed(isPlayed, ofItem: item.id, key: key)
        Task { await syncPlayback() }
    }

    /// Keeps `userData`, as the server has it after the account changed it there, with the download of `itemID`, in
    /// place of a change made with the download that the server hasn't heard yet, which it's newer than.
    func keepServerPlayback(_ userData: UserItemDataDto, of itemID: String) async {
        do {
            try await downloads.keepServerPlayback(
                DownloadPlayback(userData), forItem: itemID, key: key, replacingChanges: true)
        } catch {
            Self.logger.error("Could not keep a download's progress: \(error.localizedDescription, privacy: .private)")
        }
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

    /// Asks the server whether the account may download. When it can't answer, what was known stays.
    private func checkPermission() async {
        do {
            isAllowed = try await library.canDownload()
            knowsPermission = true
        } catch {
            Self.logger.error(
                "Could not ask whether the account may download: \(error.localizedDescription, privacy: .private)")
        }
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
            offlineItems = records.compactMap { offlineItem(of: $0) }
        } catch {
            Self.logger.error("Could not read the downloads: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// `record` as screens show it with no server, with the pictures saved with it, or nil when it isn't finished or
    /// its file has gone.
    private func offlineItem(of record: DownloadRecord) -> MediaItem? {
        guard downloads.fileURL(for: record) != nil else { return nil }
        let artwork = SavedArtwork(
            poster: downloads.artworkURL(.poster, for: record),
            backdrop: downloads.artworkURL(.backdrop, for: record)
        )
        return MediaItem(download: record, artwork: artwork)
    }

    /// Saves `item`'s poster and backdrop with its download `record`, as wide as this device's screen draws them,
    /// leaving any saved already. A picture that doesn't load is tried again when the item's page next opens.
    private func saveArtwork(of item: MediaItem, for record: DownloadRecord) async {
        guard let artwork, let source = item.source else { return }
        let sizes = DownloadArtworkSizes.current
        for kind in DownloadArtwork.allCases where downloads.artworkURL(kind, for: record) == nil {
            do {
                let data = try await artwork.data(
                    kind.role, of: source, width: sizes.width(of: kind), scale: sizes.scale)
                if let data {
                    try await downloads.saveArtwork(data, kind, of: record.id)
                }
            } catch {
                // Left before it loaded, as when the page asking for it closed.
                guard !Task.isCancelled else { return }
                Self.logger.error(
                    "Could not save a download's picture: \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// Where the server says playback of `item` last stopped, and whether it's been watched, for showing and resuming
    /// its download with no server, or nil when it hasn't been started. It's dated when the server says it was last
    /// played, so a later stop on this device wins.
    nonisolated static func serverPlayback(of item: MediaItem) -> DownloadPlayback? {
        item.source?.userData.flatMap { DownloadPlayback($0) }
    }

    /// Where `record` is, given the progress of the running downloads.
    nonisolated static func state(of record: DownloadRecord?, progress: [String: Downloads.Progress]) -> ItemState {
        guard let record else { return .notDownloaded }
        switch record.state {
        case .downloading: return .downloading(progress[record.id]?.fraction)
        case .preparing: return .preparing
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
            seriesID: card.episode?.seriesID,
            seriesName: card.episode?.seriesTitle,
            seasonNumber: card.episode?.seasonNumber,
            episodeNumber: card.episode?.episodeNumber,
            runtime: card.runtime,
            year: card.year,
            rating: card.rating,
            overview: card.overview
        )
    }
}
