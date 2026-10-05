import SerafinDesign
import SwiftUI

/// The first tab: Continue Watching, Next Up and the newest items in each library.
struct HomeView: View {
    @State private var model = HomeModel()
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions

    var body: some View {
        content
            .background(Color.background)
            .navigationTitle(String(localized: "Home", bundle: .module, comment: "Title of the home tab."))
            .task(id: actions.revision) { await model.load(from: media) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Skeleton(.rows)
        case .failed(let message):
            FailureState(message: message) { Task { await model.load(from: media) } }
        case .loaded(let home) where home.isEmpty:
            EmptyState(
                String(localized: "Nothing Here Yet", bundle: .module, comment: "Title when the home screen is empty."),
                message: String(
                    localized: "Movies and shows you add to your server appear here.",
                    bundle: .module,
                    comment: "Explanation when the home screen is empty."
                ),
                systemImage: "sparkles.tv"
            )
        case .loaded(let home):
            rows(home)
        }
    }

    private func rows(_ home: HomeContent) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xLarge) {
                if !home.continueWatching.isEmpty {
                    MediaRow(
                        String(
                            localized: "Continue Watching", bundle: .module,
                            comment:
                                "Started movies and episodes: the Home row, and the shortcut that plays the latest of them."
                        ),
                        style: .landscape,
                        items: home.continueWatching
                    ) { LandscapeLink(item: $0) }
                }
                if !home.nextUp.isEmpty {
                    MediaRow(
                        String(localized: "Next Up", bundle: .module, comment: "Home row of next episodes."),
                        style: .landscape,
                        items: home.nextUp
                    ) { LandscapeLink(item: $0) }
                }
                ForEach(home.latest.filter { !$0.items.isEmpty }) { row in
                    LatestRowView(row: row)
                }
            }
            .padding(.vertical, Spacing.medium)
        }
        .refreshable { await model.refresh(from: media) }
    }
}

/// "Latest in Movies": the newest posters of one library, with See All opening the library.
private struct LatestRowView: View {
    let row: HomeContent.LatestRow
    @Environment(\.navigate) private var navigate

    var body: some View {
        MediaRow(
            String(
                localized: "Latest in \(row.library.name)",
                bundle: .module,
                comment: "Home row of a library's newest items, such as Latest in Movies."
            ),
            style: .posters,
            items: row.items,
            seeAll: { navigate(.library(row.library)) }
        ) { PosterLink(item: $0) }
    }
}

#Preview("Light") {
    TabStack { HomeView() }
        .previewEnvironment()
}

#Preview("Dark") {
    TabStack { HomeView() }
        .previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TabStack { HomeView() }
        .previewEnvironment()
        .dynamicTypeSize(.accessibility5)
}
