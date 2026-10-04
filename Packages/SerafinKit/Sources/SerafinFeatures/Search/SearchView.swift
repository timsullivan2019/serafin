import SerafinDesign
import SwiftUI

/// The search tab: live results across movies, shows and episodes as the user types.
struct SearchView: View {
    @State private var model = SearchModel()

    var body: some View {
        content
            .background(Color.background)
            .navigationTitle(String(localized: "Search", bundle: .module, comment: "Title of the search tab."))
            .searchable(
                text: $model.query,
                prompt: String(
                    localized: "Movies, shows and episodes",
                    bundle: .module,
                    comment: "Placeholder in the search field."
                )
            )
    }

    @ViewBuilder private var content: some View {
        if !model.hasQuery {
            EmptyState(
                String(
                    localized: "Search Your Library", bundle: .module, comment: "Title before anything is searched."),
                message: String(
                    localized: "Find movies, shows and episodes by title.",
                    bundle: .module,
                    comment: "Explanation before anything is searched."
                ),
                systemImage: "magnifyingglass"
            )
        } else if model.results.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            SearchResultsView(results: model.results)
        }
    }
}

/// Results grouped into movies, shows and episodes.
private struct SearchResultsView: View {
    let results: SearchResults
    @ScaledMetric(relativeTo: .subheadline) private var posterWidth = 104.0
    @ScaledMetric(relativeTo: .subheadline) private var thumbnailWidth = 220.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                section(
                    String(localized: "Movies", bundle: .module, comment: "Search results section."),
                    results.movies,
                    width: posterWidth
                ) { PosterLink(card: $0) }
                section(
                    String(localized: "Shows", bundle: .module, comment: "Search results section."),
                    results.shows,
                    width: posterWidth
                ) { PosterLink(card: $0) }
                section(
                    String(localized: "Episodes", bundle: .module, comment: "Search results section."),
                    results.episodes,
                    width: thumbnailWidth
                ) { LandscapeLink(card: $0) }
            }
            .padding(Spacing.medium)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder private func section<Card: View>(
        _ title: String,
        _ cards: [MediaCard],
        width: CGFloat,
        @ViewBuilder card: @escaping (MediaCard) -> Card
    ) -> some View {
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(title)
                    .typography(.title)
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: width), spacing: Spacing.small, alignment: .top)],
                    spacing: Spacing.large
                ) {
                    ForEach(cards) { card($0) }
                }
            }
        }
    }
}

#Preview("Light") {
    TabStack { SearchView() }
        .environment(PlaybackCoordinator())
}

#Preview("Dark") {
    TabStack { SearchView() }
        .environment(PlaybackCoordinator())
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TabStack { SearchView() }
        .environment(PlaybackCoordinator())
        .dynamicTypeSize(.accessibility5)
}
