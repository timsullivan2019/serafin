import SerafinCore
import SwiftUI

/// The detail screen's More menu item for downloading a movie or an episode: Download, Cancel Download while it's on
/// its way or being prepared, Delete Download once it's saved, or Try Downloading Again after it failed, with how far
/// it got or why.
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
