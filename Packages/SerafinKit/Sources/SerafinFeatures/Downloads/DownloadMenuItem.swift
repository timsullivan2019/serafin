import SerafinCore
import SwiftUI

/// The item for downloading a movie or an episode in its page's More menu and its card's menu: Download, Cancel
/// Download while it waits, is on its way or is being prepared, Delete Download once it's saved, or Try Downloading
/// Again after it failed, with how far it got or why.
struct DownloadMenuItem: View {
    let item: MediaItem
    let downloads: DownloadCenter

    var body: some View {
        switch downloads.state(of: item.id) {
        case .notDownloaded:
            Button {
                Task { await downloads.download(item) }
            } label: {
                Label(
                    String(localized: "Download", bundle: .module, comment: "Menu item that downloads a video."),
                    systemImage: "arrow.down.circle")
            }
        case .downloading(let fraction):
            cancel(
                detail: fraction.map { fraction in
                    let percent = fraction.formatted(.percent.precision(.fractionLength(0)))
                    return String(
                        localized: "\(percent) downloaded", bundle: .module,
                        comment: "Under Cancel Download: how much has arrived, such as 42% downloaded.")
                })
        case .waiting:
            cancel(detail: DownloadRow.waiting)
        case .preparing:
            cancel(detail: DownloadRow.preparing)
        case .finished:
            Button(role: .destructive) {
                Task { await downloads.delete(itemID: item.id) }
            } label: {
                Label(
                    String(
                        localized: "Delete Download", bundle: .module,
                        comment: "Menu item that deletes a downloaded video from the device."),
                    systemImage: "trash")
            }
        case .failed(let failure):
            Button {
                Task { await downloads.download(item) }
            } label: {
                Label(
                    String(
                        localized: "Try Downloading Again", bundle: .module,
                        comment: "Menu item that tries a failed download again."),
                    systemImage: "arrow.clockwise.circle")
                Text(DownloadRow.reason(failure))
            }
        }
    }

    /// Cancel Download, with `detail` under it, such as how much has arrived.
    private func cancel(detail: String?) -> some View {
        Button {
            Task { await downloads.delete(itemID: item.id) }
        } label: {
            Label(
                String(
                    localized: "Cancel Download", bundle: .module,
                    comment: "Menu item that stops a download on its way."),
                systemImage: "xmark.circle")
            if let detail {
                Text(detail)
            }
        }
    }
}

/// A show page's More menu items for downloading its episodes: Download Season for the season the page lists, while
/// any of its episodes can start, and Download Next Unwatched, with a choice of how many, until the show is watched.
struct ShowDownloadMenuItems: View {
    let show: MediaItem
    /// The season the page lists.
    let season: ShowSeason?
    /// The season's episodes, once they've loaded.
    let seasonEpisodes: [MediaItem]?
    let downloads: DownloadCenter

    /// How many of the next episodes not yet watched Download Next Unwatched offers.
    static let unwatchedCounts = [3, 5, 10]

    var body: some View {
        if let season, seasonEpisodes?.contains(where: { downloads.canStart($0) }) ?? true {
            Button {
                Task { await downloads.downloadSeason(season.id, of: show.id) }
            } label: {
                Label(
                    String(
                        localized: "Download \(season.title)", bundle: .module,
                        comment:
                            "Menu item on a show's page that downloads the episodes of the season it lists. The value is the season's name, such as Season 2 or Specials."
                    ),
                    systemImage: "arrow.down.circle")
            }
        }
        if !show.card.isPlayed {
            Menu {
                ForEach(Self.unwatchedCounts, id: \.self) { count in
                    Button {
                        Task { await downloads.downloadNextUnwatched(count, of: show.id) }
                    } label: {
                        Text(Self.episodes(count))
                    }
                }
            } label: {
                Label(
                    String(
                        localized: "Download Next Unwatched", bundle: .module,
                        comment:
                            "Menu on a show's page that downloads the next episodes not yet watched, with a choice of how many."
                    ),
                    systemImage: "arrow.down.to.line.circle")
            }
        }
    }

    /// A choice under Download Next Unwatched, such as "5 Episodes".
    static func episodes(_ count: Int) -> String {
        String(
            localized: "\(count) Episodes", bundle: .module,
            comment: "Choice under Download Next Unwatched: how many episodes, such as 5 Episodes.")
    }
}
