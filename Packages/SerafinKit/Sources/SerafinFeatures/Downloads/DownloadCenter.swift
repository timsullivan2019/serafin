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
        /// Waiting its turn while the server converts another download's video.
        case waiting
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
    /// The `UserDefaults` key of the download quality, the most bits per second a download's video may take.
    nonisolated static let qualityKey = "downloads.quality"

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
    /// The movies and episodes being asked of the server and started, which aren't among ``records`` yet, so asking
    /// again meanwhile doesn't start them twice.
    private var starting: Set<String> = []

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

    /// The mark an episode's card shows for the download of `itemID`, or nil when there's none to show.
    func mark(of itemID: String) -> DownloadMark? {
        Self.mark(for: state(of: itemID))
    }

    /// Whether `item` can be downloaded: a movie or an episode with a file on the server, for an account allowed to
    /// download. An episode the server knows only from its metadata, as one missing or yet to air, has none.
    func canDownload(_ item: MediaItem) -> Bool {
        guard isAllowed, let source = item.source, source.locationType != .virtual, !item.isSaved else { return false }
        return item.card.kind == .movie || item.card.kind == .episode
    }

    /// Whether a menu offers `item`'s download item: for one the account may download, and for one downloaded or on
    /// its way, which can be deleted even while the server, which says whether the account may download, is out of
    /// reach.
    func offersDownloadItem(for item: MediaItem) -> Bool {
        canDownload(item) || state(of: item.id) != .notDownloaded
    }

    /// Whether `item` can start downloading now: one the account may download that isn't downloaded or on its way, or
    /// that failed, and isn't being started already.
    func canStart(_ item: MediaItem) -> Bool {
        guard canDownload(item), !starting.contains(item.id) else { return false }
        switch state(of: item.id) {
        case .notDownloaded, .failed: return true
        case .waiting, .downloading, .preparing, .finished: return false
        }
    }

    /// Downloads `item`, or tries a download that failed again, and saves its poster and backdrop with it.
    ///
    /// It downloads at the download quality, as the original file when the player opens it, and otherwise as the copy
    /// the server makes, when the server's policy lets the account have it converted.
    func download(_ item: MediaItem) async {
        guard starting.insert(item.id).inserted else { return }
        defer { starting.remove(item.id) }
        do {
            let permissions = try await library.conversionPermissions()
            switch try await start(item, permissions: permissions) {
            case .started(let record):
                await saveArtwork(of: item, for: record)
            case .refused(let refusal):
                failure = .refused(refusal)
            }
        } catch {
            failure = UserMessage(error)
        }
    }

    /// Downloads the episodes of the season `seasonID` of the show `seriesID` that have a file on the server and
    /// aren't downloaded or on their way, in order.
    func downloadSeason(_ seasonID: String, of seriesID: String) async {
        do {
            let episodes = try await library.availableEpisodes(series: seriesID, season: seasonID)
            await download(MediaItem.from(episodes))
        } catch {
            failure = UserMessage(error)
        }
    }

    /// Downloads the next `count` episodes of the show `seriesID` not yet watched, leaving those downloaded or on
    /// their way as they are. They start at the episode Next Up names, where the show's Play starts, or when it names
    /// none, as when the last episode was watched before the others, at the first episode after the Specials.
    func downloadNextUnwatched(_ count: Int, of seriesID: String) async {
        do {
            let episodes: [BaseItemDto]
            if let next = try await library.nextUp(limit: 1, series: seriesID).first?.id {
                episodes = try await library.availableEpisodes(
                    series: seriesID, from: next, limit: count + Self.watchedAhead)
            } else {
                episodes = try await library.availableEpisodes(series: seriesID).filter { $0.parentIndexNumber != 0 }
            }
            await download(Self.unwatched(count, of: MediaItem.from(episodes)))
        } catch {
            failure = UserMessage(error)
        }
    }

    /// The first `count` of `episodes` not yet watched, in order. One part way through counts.
    nonisolated static func unwatched(_ count: Int, of episodes: [MediaItem]) -> [MediaItem] {
        Array(episodes.filter { !$0.card.isPlayed }.prefix(count))
    }

    /// How many of the episodes after the next one to look through for the next not yet watched, beyond how many are
    /// asked for, since some may have been watched out of order.
    private static let watchedAhead = 20

    /// Downloads each of `items` that can start, in order, then saves their pictures. When some can't, it says once
    /// why the first of them couldn't, and once the device is full, the rest aren't tried.
    private func download(_ items: [MediaItem]) async {
        let pending = items.filter { canStart($0) }
        guard !pending.isEmpty else { return }
        let ids = Set(pending.map(\.id))
        starting.formUnion(ids)
        defer { starting.subtract(ids) }
        var started: [(item: MediaItem, record: DownloadRecord)] = []
        var unstarted: UserMessage.UnstartedEpisodes?
        do {
            let permissions = try await library.conversionPermissions()
            episodes: for item in pending {
                do {
                    switch try await start(item, permissions: permissions) {
                    case .started(let record):
                        started.append((item, record))
                    case .refused(let refusal):
                        unstarted = unstarted ?? .refused(refusal)
                    }
                } catch DownloadError.notEnoughSpace {
                    unstarted = .notEnoughSpace
                    break episodes
                } catch {
                    unstarted = unstarted ?? .failed(error)
                }
            }
        } catch {
            unstarted = .failed(error)
        }
        for (item, record) in started {
            await saveArtwork(of: item, for: record)
        }
        if let unstarted {
            failure = .episodesNotStarted(unstarted, anyStarted: !started.isEmpty)
        }
    }

    /// What became of a movie or an episode asked to download.
    private enum Start {
        /// It's on its way, or waiting its turn.
        case started(DownloadRecord)
        /// The server can't offer a copy the account may have, and why.
        case refused(DownloadRefusal)
    }

    /// Asks the server how `item` downloads at the download quality, and starts it.
    ///
    /// - Throws: When the server can't be asked, or the download can't start.
    private func start(_ item: MediaItem, permissions: ConversionPermissions) async throws -> Start {
        let maxBitrate = Self.quality(in: defaults).bitsPerSecond
        switch try await planner.plan(for: item.id, maxBitrate: maxBitrate, permissions: permissions) {
        case .original(let planned), .converted(let planned):
            let request = Downloads.Request(
                itemID: item.id,
                mediaSourceID: planned.mediaSourceID,
                url: planned.url,
                fileExtension: planned.fileExtension,
                bytes: planned.bytes,
                metadata: DownloadMetadata(item.card),
                tracks: planned.tracks,
                playback: Self.serverPlayback(of: item),
                preparation: planned.preparation,
                allowsCellularAccess: defaults.bool(forKey: Self.cellularKey)
            )
            return .started(try await downloads.start(request, for: key))
        case .refused(let refusal):
            return .refused(refusal)
        }
    }

    /// The download quality picked in Settings, Maximum until the user picks another.
    nonisolated static func quality(in defaults: UserDefaults) -> PlaybackQuality {
        guard defaults.object(forKey: qualityKey) != nil else { return .maximum }
        return PlaybackQuality(rawValue: defaults.integer(forKey: qualityKey)) ?? .maximum
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
    /// copy keeps where playback stops in the download, and for an episode, names the next one downloaded, which plays
    /// next when the server can't say which does.
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
        let next = offlineItems.first { $0.id == itemID }?.nextEpisode(among: offlineItems)
        let copy = DownloadedCopy(
            file: file, mediaSourceID: record.mediaSourceID, tracks: record.tracks, nextEpisode: next?.source,
            keepPosition: keep)
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

    /// Deletes each of `records` and its file, as Delete Watched does.
    func delete(_ records: [DownloadRecord]) async {
        for record in records {
            await delete(record)
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

    /// The mark a card shows for a download in `state`: none before it's asked for or once it failed, which its menu
    /// says, a ring while it's on its way, and a filled arrow once it's saved.
    nonisolated static func mark(for state: ItemState) -> DownloadMark? {
        switch state {
        case .notDownloaded, .failed: nil
        case .waiting, .preparing: .downloading(nil)
        case .downloading(let fraction): .downloading(fraction)
        case .finished: .downloaded
        }
    }

    /// Where `record` is, given the progress of the running downloads.
    nonisolated static func state(of record: DownloadRecord?, progress: [String: Downloads.Progress]) -> ItemState {
        guard let record else { return .notDownloaded }
        switch record.state {
        case .waiting: return .waiting
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
