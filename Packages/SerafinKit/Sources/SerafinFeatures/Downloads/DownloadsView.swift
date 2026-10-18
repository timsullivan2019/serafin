import SerafinCore
import SerafinDesign
import SwiftUI

/// The account's downloads, from Settings: what's saved, what's on its way and what failed, with the space they take.
/// Each show's episodes are listed together, in order, under its name. Swipe a row to delete it, or delete the episodes
/// that have been watched all at once.
struct DownloadsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if let center = session.downloads {
                DownloadsList(
                    records: center.records,
                    progress: center.progress,
                    usedBytes: center.usedBytes,
                    delete: { records in Task { await center.delete(records) } }
                )
            } else {
                DownloadsList(records: [], progress: [:], usedBytes: 0, delete: { _ in })
            }
        }
        .navigationTitle(Self.title)
    }

    /// The screen's title, its row in Settings, and the heading over the downloads on Home when the server can't be
    /// reached.
    static var title: String {
        String(
            localized: "Downloads", bundle: .module,
            comment:
                "Title of the downloads screen, its row in Settings, and the heading over the downloads on Home when the server can't be reached."
        )
    }
}

/// The rows of ``DownloadsView``, from plain values so previews need no server.
struct DownloadsList: View {
    let records: [DownloadRecord]
    let progress: [String: Downloads.Progress]
    let usedBytes: Int64
    let delete: ([DownloadRecord]) -> Void

    var body: some View {
        if records.isEmpty {
            ContentUnavailableView {
                Label(
                    String(
                        localized: "No Downloads", bundle: .module,
                        comment: "Title on the downloads screen when nothing is downloaded."),
                    systemImage: "arrow.down.circle")
            } description: {
                Text(
                    String(
                        localized:
                            "Movies and episodes you download appear here. Download one from its page with the More menu.",
                        bundle: .module,
                        comment: "Explanation on the downloads screen when nothing is downloaded."))
            }
        } else {
            let groups = DownloadGroup.groups(of: records)
            let watched = DownloadGroup.watchedEpisodes(in: records)
            List {
                ForEach(groups) { group in
                    DownloadGroupSection(
                        group: group,
                        progress: progress,
                        usedBytes: group.id == groups.last?.id ? usedBytes : nil,
                        delete: delete
                    )
                }
            }
            .toolbar {
                if !watched.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        DeleteWatchedButton(watched: watched, delete: delete)
                    }
                }
            }
        }
    }
}

/// One group of ``DownloadsList``: a show's episodes under its name, or the movies, with a swipe to delete each.
private struct DownloadGroupSection: View {
    let group: DownloadGroup
    let progress: [String: Downloads.Progress]
    /// The space the downloads take up, said under the last group, or nil under the others.
    let usedBytes: Int64?
    let delete: ([DownloadRecord]) -> Void

    var body: some View {
        Section {
            ForEach(group.records) { record in
                DownloadRow(
                    record: record,
                    state: DownloadCenter.state(of: record, progress: progress),
                    isUnderItsShow: group.isShow
                )
                .swipeActions {
                    Button(role: .destructive) {
                        delete([record])
                    } label: {
                        Label(
                            String(
                                localized: "Delete", bundle: .module, comment: "Swipe action that deletes a download."),
                            systemImage: "trash")
                    }
                }
            }
        } header: {
            Text(group.title)
        } footer: {
            if let usedBytes {
                let size = DownloadRow.size(usedBytes)
                Text(
                    String(
                        localized: "Downloads use \(size) on this device.", bundle: .module,
                        comment: "Footer on the downloads screen. The value is a size, such as 4.2 GB."))
            }
        }
    }
}

/// Deletes the downloads of the episodes that have been watched, once the viewer says so.
private struct DeleteWatchedButton: View {
    let watched: [DownloadRecord]
    let delete: ([DownloadRecord]) -> Void
    @State private var confirms = false

    var body: some View {
        Button(
            String(
                localized: "Delete Watched", bundle: .module,
                comment: "Button on the downloads screen that deletes the downloads of watched episodes, after asking.")
        ) {
            confirms = true
        }
        .confirmationDialog(
            String(
                localized: "Delete Watched Episodes?", bundle: .module,
                comment: "Title of the question before deleting the downloads of the episodes that have been watched."),
            isPresented: $confirms,
            titleVisibility: .visible
        ) {
            Button(
                String(
                    localized: "Delete Episodes", bundle: .module,
                    comment: "Button that deletes the downloads of the episodes that have been watched."),
                role: .destructive
            ) {
                delete(watched)
            }
        } message: {
            let size = DownloadRow.size(watched.reduce(0) { $0 + ($1.bytes ?? 0) })
            Text(
                String(
                    localized:
                        "The episodes you've watched take up \(size) on this device. They stay on your server, so you can download them again.",
                    bundle: .module,
                    comment:
                        "Message before deleting the downloads of the episodes that have been watched. The value is a size, such as 2.4 GB."
                )
            )
        }
    }
}

/// Downloads listed together on the Downloads screen: the episodes of one show, in order under its name, or the
/// movies, newest first.
struct DownloadGroup: Identifiable, Equatable {
    /// The show's ID, or its name for episodes saved without the ID, or a fixed ID for the movies.
    let id: String
    /// The show's name, or "Movies".
    let title: String
    /// Whether these are the episodes of one show.
    let isShow: Bool
    /// The downloads, as they're listed.
    let records: [DownloadRecord]

    /// `records`, newest first, in groups: the group with the newest download first, each show's episodes by season
    /// and episode, with any missing either number after them, and the movies newest first.
    static func groups(of records: [DownloadRecord]) -> [DownloadGroup] {
        var order: [String] = []
        var members: [String: [DownloadRecord]] = [:]
        for record in records {
            let id = Self.id(of: record)
            if members[id] == nil {
                order.append(id)
            }
            members[id, default: []].append(record)
        }
        return order.map { id in
            let records = members[id] ?? []
            guard id != Self.moviesID else {
                return DownloadGroup(id: id, title: Self.movies, isShow: false, records: records)
            }
            let name = records.lazy.compactMap { $0.metadata.seriesName }.first { !$0.isEmpty }
            return DownloadGroup(id: id, title: name ?? Self.episodes, isShow: true, records: Self.inOrder(records))
        }
    }

    /// The finished downloads of episodes that have been watched, which Delete Watched deletes.
    static func watchedEpisodes(in records: [DownloadRecord]) -> [DownloadRecord] {
        records.filter { $0.metadata.kind == .episode && $0.state == .finished && $0.isWatched }
    }

    /// The group of the movies.
    private static let moviesID = "movies"

    /// The group `record` is listed in.
    private static func id(of record: DownloadRecord) -> String {
        let metadata = record.metadata
        guard metadata.kind == .episode else { return moviesID }
        if let seriesID = metadata.seriesID, !seriesID.isEmpty {
            return "show-\(seriesID)"
        }
        return "show-name-\(metadata.seriesName ?? "")"
    }

    /// A show's episodes by season and episode, then those missing either number, newest first.
    private static func inOrder(_ episodes: [DownloadRecord]) -> [DownloadRecord] {
        let listed = episodes.enumerated().sorted { lhs, rhs in
            switch (place(of: lhs.element), place(of: rhs.element)) {
            case (let left?, let right?): left == right ? lhs.offset < rhs.offset : left < right
            case (.some, nil): true
            case (nil, .some): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }
        return listed.map { $0.element }
    }

    /// An episode's season and episode number, or nil when it's missing either.
    private static func place(of record: DownloadRecord) -> (Int, Int)? {
        guard let season = record.metadata.seasonNumber, let episode = record.metadata.episodeNumber else { return nil }
        return (season, episode)
    }

    /// The heading over the movies.
    private static var movies: String {
        String(localized: "Movies", bundle: .module, comment: "Heading over a list of movies.")
    }

    /// The heading over the episodes of a show saved without its name.
    private static var episodes: String {
        String(localized: "Episodes", bundle: .module, comment: "Heading over a list of episodes.")
    }
}

extension DownloadRecord {
    /// Whether the movie or episode has been watched, as this device last knew.
    var isWatched: Bool {
        playback?.isPlayed(runtime: metadata.runtime) ?? false
    }
}

/// One download: its title, what it is, and how far it's got.
struct DownloadRow: View {
    let record: DownloadRecord
    let state: DownloadCenter.ItemState
    /// Whether the row is listed under its show's name, so an episode says only which one it is.
    var isUnderItsShow = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(title)
                .font(.body)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if case .downloading(let fraction) = state {
                ProgressView(value: fraction ?? 0)
                    .progressViewStyle(.linear)
                    .accessibilityHidden(true)
            }
            Text(status)
                .font(.footnote)
                .foregroundStyle(isFailed ? AnyShapeStyle(Color.red) : AnyShapeStyle(HierarchicalShapeStyle.secondary))
        }
        .padding(.vertical, Spacing.xxSmall)
        .accessibilityElement(children: .combine)
    }

    private var metadata: DownloadMetadata { record.metadata }

    /// The movie's title, or the episode's.
    private var title: String { metadata.title }

    /// The series and episode code for an episode, such as "Sherlock Holmes · S1 E3", or under its show's name, the
    /// code alone; the year for a movie.
    private var subtitle: String? {
        switch metadata.kind {
        case .episode:
            let series = metadata.seriesName.flatMap { $0.isEmpty ? nil : $0 }
            guard let season = metadata.seasonNumber, let number = metadata.episodeNumber else {
                return isUnderItsShow ? nil : series
            }
            let episode = MediaCard.EpisodeInfo(
                seriesID: metadata.seriesID ?? "", seriesTitle: series ?? "", seasonNumber: season,
                episodeNumber: number)
            let card = MediaCard(id: record.itemID, kind: .episode, title: metadata.title, episode: episode)
            return isUnderItsShow || series == nil ? card.episodeCode : card.eyebrowText
        case .movie:
            return metadata.year.map { String($0) }
        }
    }

    private var isFailed: Bool {
        if case .failed = state { true } else { false }
    }

    private var status: String {
        Self.status(of: record, state: state)
    }

    /// What a row says of where `record` is, in `state`: its size once it's saved, and whether it's been watched, that
    /// it's waiting its turn, the share that has arrived while it's on its way, that it's being prepared, or why it
    /// failed.
    static func status(of record: DownloadRecord, state: DownloadCenter.ItemState) -> String {
        switch state {
        case .notDownloaded, .finished:
            let size = Self.size(record.bytes ?? 0)
            guard record.isWatched else { return size }
            return String(
                localized: "Watched · \(size)", bundle: .module,
                comment: "A saved download's status once it's been watched. The value is its size, such as 640 MB.")
        case .waiting:
            return Self.waiting
        case .preparing:
            return Self.preparing
        case .downloading(let fraction):
            guard let fraction else {
                return String(
                    localized: "Downloading…", bundle: .module,
                    comment: "A download's status when its size isn't known.")
            }
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
            return String(
                localized: "Downloading, \(percent)", bundle: .module,
                comment: "A download's status while it's on its way. The value is a percentage, such as 42%.")
        case .failed(let failure):
            return Self.reason(failure)
        }
    }

    /// A download's status while it waits for the server to convert another download's video first.
    static var waiting: String {
        String(
            localized: "Waiting…", bundle: .module,
            comment: "A download's status while it waits for the server to finish converting another download first.")
    }

    /// A download's status while Serafin writes the copy the player opens from the file that arrived.
    static var preparing: String {
        String(
            localized: "Preparing…", bundle: .module,
            comment: "A download's status once its file has arrived, while Serafin makes it ready to play offline.")
    }

    /// `bytes` as a size, such as "4.2 GB".
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// Why a download stopped, in a few words.
    static func reason(_ failure: DownloadFailure?) -> String {
        switch failure {
        case .notAllowed:
            String(
                localized: "Your server doesn't allow downloads", bundle: .module,
                comment: "A failed download's status.")
        case .notFound:
            String(
                localized: "No longer on your server", bundle: .module, comment: "A failed download's status.")
        case .storageFull:
            String(localized: "Not enough space", bundle: .module, comment: "A failed download's status.")
        case .interrupted:
            String(
                localized: "Stopped when Serafin was closed", bundle: .module, comment: "A failed download's status.")
        case .preparationFailed:
            String(
                localized: "Couldn't prepare the video", bundle: .module,
                comment: "A failed download's status: its file arrived, but Serafin couldn't make it ready to play.")
        case .network, .serverError, nil:
            String(localized: "Couldn't finish downloading", bundle: .module, comment: "A failed download's status.")
        }
    }
}

#if DEBUG
    private enum DownloadsPreview {
        static let key = SessionKey(serverID: "server", userID: "user")

        static let records = [
            DownloadRecord(
                id: "a", key: key, itemID: "movie-sintel", mediaSourceID: "movie-sintel", fileExtension: "mp4",
                state: .downloading, bytes: 1_200_000_000,
                metadata: DownloadMetadata(title: "Sintel", kind: .movie, year: 2010)),
            episode("b", 3, "A Case of Identity"),
            episode("f", 1, "A Scandal in Bohemia", isWatched: true),
            episode("g", 2, "The Red-Headed League", isWatched: true),
            DownloadRecord(
                id: "c", key: key, itemID: "movie-spring", mediaSourceID: "movie-spring", fileExtension: "mp4",
                state: .failed, failure: .interrupted,
                metadata: DownloadMetadata(title: "Spring", kind: .movie, year: 2019)),
            DownloadRecord(
                id: "d", key: key, itemID: "movie-nosferatu", mediaSourceID: "movie-nosferatu", fileExtension: "mov",
                state: .preparing, bytes: 2_100_000_000,
                metadata: DownloadMetadata(title: "Nosferatu", kind: .movie, year: 1922),
                preparation: DownloadPreparation(arrivingExtension: "mp4")),
            DownloadRecord(
                id: "e", key: key, itemID: "movie-the-general", mediaSourceID: "movie-the-general",
                fileExtension: "mov", state: .waiting, bytes: 1_800_000_000,
                metadata: DownloadMetadata(title: "The General", kind: .movie, year: 1926),
                preparation: DownloadPreparation(arrivingExtension: "mp4", convertsVideo: true),
                waiting: DownloadWaiting(path: "/Videos/movie-the-general/stream.mp4", allowsCellularAccess: false)),
        ]

        static let progress = ["a": Downloads.Progress(received: 504_000_000, expected: 1_200_000_000)]

        /// A saved episode of Sherlock Holmes's first season.
        static func episode(_ id: String, _ number: Int, _ title: String, isWatched: Bool = false) -> DownloadRecord {
            DownloadRecord(
                id: id, key: key, itemID: "episode-\(number)", mediaSourceID: "episode-\(number)", fileExtension: "mp4",
                state: .finished, bytes: 640_000_000,
                metadata: DownloadMetadata(
                    title: title, kind: .episode, seriesID: "series-sherlock", seriesName: "Sherlock Holmes",
                    seasonNumber: 1, episodeNumber: number, runtime: .seconds(3000)),
                playback: isWatched ? DownloadPlayback(position: .zero, isPlayed: true) : nil)
        }

        @MainActor static func list() -> some View {
            NavigationStack {
                DownloadsList(records: records, progress: progress, usedBytes: 1_920_000_000, delete: { _ in })
                    .navigationTitle(DownloadsView.title)
            }
        }
    }

    #Preview("Downloads") {
        DownloadsPreview.list()
    }

    #Preview("Downloads, dark") {
        DownloadsPreview.list()
            .preferredColorScheme(.dark)
    }

    #Preview("Downloads, largest text") {
        DownloadsPreview.list()
            .dynamicTypeSize(.accessibility5)
    }

    #Preview("No downloads") {
        NavigationStack {
            DownloadsList(records: [], progress: [:], usedBytes: 0, delete: { _ in })
                .navigationTitle(DownloadsView.title)
        }
    }
#endif
