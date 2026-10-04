import SerafinDesign
import SwiftUI

/// The first tab: Continue Watching, Next Up and the newest items in each library.
struct HomeView: View {
    @State private var model = HomeModel()

    var body: some View {
        content
            .navigationTitle(String(localized: "Home", bundle: .module, comment: "Title of the home tab."))
            .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        if !model.hasLoaded {
            LoadingState()
        } else if model.isEmpty {
            EmptyState(
                String(localized: "Nothing Here Yet", bundle: .module, comment: "Title when the home screen is empty."),
                message: String(
                    localized: "Movies and shows you add to your server appear here.",
                    bundle: .module,
                    comment: "Explanation when the home screen is empty."
                ),
                systemImage: "sparkles.tv"
            )
        } else {
            rows
        }
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xLarge) {
                if !model.continueWatching.isEmpty {
                    MediaRow(
                        String(localized: "Continue Watching", bundle: .module, comment: "Home row of started items."),
                        style: .landscape,
                        items: model.continueWatching
                    ) { LandscapeLink(card: $0) }
                }
                if !model.nextUp.isEmpty {
                    MediaRow(
                        String(localized: "Next Up", bundle: .module, comment: "Home row of next episodes."),
                        style: .landscape,
                        items: model.nextUp
                    ) { LandscapeLink(card: $0) }
                }
                ForEach(model.latest.filter { !$0.items.isEmpty }) { row in
                    LatestRowView(row: row)
                }
            }
            .padding(.vertical, Spacing.medium)
        }
        .background(Color.background)
    }
}

/// "Latest in Movies": the newest posters of one library, with See All opening the library.
private struct LatestRowView: View {
    let row: HomeModel.LatestRow
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
            seeAll: { navigate(.library(id: row.library.id)) }
        ) { PosterLink(card: $0) }
    }
}

#Preview("Light") {
    TabStack { HomeView() }
        .environment(PlaybackCoordinator())
}

#Preview("Dark") {
    TabStack { HomeView() }
        .environment(PlaybackCoordinator())
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TabStack { HomeView() }
        .environment(PlaybackCoordinator())
        .dynamicTypeSize(.accessibility5)
}
