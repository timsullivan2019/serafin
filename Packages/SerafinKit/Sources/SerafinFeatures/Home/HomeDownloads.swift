import SerafinCore
import SerafinDesign
import SwiftUI

/// Home while the server can't be reached: a banner saying why, with Try Again, then the downloads, which play
/// without the server. Each opens its page, drawn from what was saved with it.
struct HomeDownloads: View {
    /// Why the server can't be reached.
    let reason: UserMessage
    /// The downloads, newest first.
    let items: [MediaItem]
    /// Whether Home is asking the server again, which shows on the banner's button.
    let isRetrying: Bool
    let retry: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var posterWidth = 104.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                HomeNoticeBanner(message: reason, detail: Self.detail, isRetrying: isRetrying, retry: retry)
                VStack(alignment: .leading, spacing: Spacing.small) {
                    RowHeader(DownloadsView.title)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: posterWidth), spacing: Spacing.small, alignment: .top)],
                        spacing: Spacing.large
                    ) {
                        ForEach(items) { PosterLink(item: $0) }
                    }
                }
            }
            .padding(Spacing.medium)
        }
    }

    /// The line under the banner's title.
    static var detail: String {
        String(
            localized: "Your downloads still play.", bundle: .module,
            comment: "Under the banner on Home when the server can't be reached, such as under You're Offline.")
    }
}

#if DEBUG
    private enum HomeDownloadsPreview {
        static let items = (MockMedia.movies.prefix(4) + MockMedia.episodes.prefix(3)).map {
            MediaItem(card: $0, source: nil)
        }

        @MainActor static func screen() -> some View {
            TabStack {
                HomeDownloads(reason: UserMessage(SerafinError.offline), items: items, isRetrying: false) {}
                    .navigationTitle(String(localized: "Home", bundle: .module, comment: "Title of the home tab."))
                    .toolbarTitleDisplayMode(.inline)
            }
            .previewEnvironment()
        }
    }

    #Preview("Offline") {
        HomeDownloadsPreview.screen()
    }

    #Preview("Offline, dark") {
        HomeDownloadsPreview.screen()
            .preferredColorScheme(.dark)
    }

    #Preview("Offline, largest text") {
        HomeDownloadsPreview.screen()
            .dynamicTypeSize(.accessibility5)
    }
#endif
