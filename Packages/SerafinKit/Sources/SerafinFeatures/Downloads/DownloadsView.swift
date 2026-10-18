import SerafinCore
import SerafinDesign
import SwiftUI

/// The account's downloads, from Settings: what's saved, what's on its way and what failed, with the space they take.
/// Swipe a row to delete it.
struct DownloadsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            if let center = session.downloads {
                DownloadsList(
                    records: center.records,
                    progress: center.progress,
                    usedBytes: center.usedBytes,
                    delete: { record in Task { await center.delete(record) } }
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
    let delete: (DownloadRecord) -> Void

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
            List {
                Section {
                    ForEach(records) { record in
                        DownloadRow(record: record, state: DownloadCenter.state(of: record, progress: progress))
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(record)
                                } label: {
                                    Label(
                                        String(
                                            localized: "Delete", bundle: .module,
                                            comment: "Swipe action that deletes a download."),
                                        systemImage: "trash")
                                }
                            }
                    }
                } footer: {
                    let size = DownloadRow.size(usedBytes)
                    Text(
                        String(
                            localized: "Downloads use \(size) on this device.", bundle: .module,
                            comment: "Footer on the downloads screen. The value is a size, such as 4.2 GB."))
                }
            }
        }
    }
}

/// One download: its title, what it is, and how far it's got.
struct DownloadRow: View {
    let record: DownloadRecord
    let state: DownloadCenter.ItemState

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

    /// The series and episode code for an episode, such as "Sherlock Holmes · S1 E3", or the year for a movie.
    private var subtitle: String? {
        switch metadata.kind {
        case .episode:
            guard let series = metadata.seriesName else { return nil }
            guard let season = metadata.seasonNumber, let episode = metadata.episodeNumber else { return series }
            return String(
                localized: "\(series) · S\(season) E\(episode)", bundle: .module,
                comment: "A downloaded episode's series, season and episode, such as Sherlock Holmes · S1 E3."
            )
        case .movie:
            return metadata.year.map { String($0) }
        }
    }

    private var isFailed: Bool {
        if case .failed = state { true } else { false }
    }

    /// The size when it's saved, the share that has arrived while it's on its way, or why it failed.
    private var status: String {
        switch state {
        case .notDownloaded, .finished:
            return Self.size(record.bytes ?? 0)
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
            DownloadRecord(
                id: "b", key: key, itemID: "episode", mediaSourceID: "episode", fileExtension: "mp4",
                state: .finished, bytes: 640_000_000,
                metadata: DownloadMetadata(
                    title: "A Case of Identity", kind: .episode, seriesName: "Sherlock Holmes", seasonNumber: 1,
                    episodeNumber: 3)),
            DownloadRecord(
                id: "c", key: key, itemID: "movie-spring", mediaSourceID: "movie-spring", fileExtension: "mp4",
                state: .failed, failure: .interrupted,
                metadata: DownloadMetadata(title: "Spring", kind: .movie, year: 2019)),
        ]

        static let progress = ["a": Downloads.Progress(received: 504_000_000, expected: 1_200_000_000)]

        @MainActor static func list() -> some View {
            NavigationStack {
                DownloadsList(records: records, progress: progress, usedBytes: 640_000_000, delete: { _ in })
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
