import SerafinDesign
import SwiftUI

/// The search tab: results across movies, shows and episodes as the user types.
struct SearchView: View {
    @State private var model = SearchModel()
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions
    @Environment(\.searchFocusRequest) private var focusRequest
    @State private var answeredFocusRequest = 0
    @State private var isSearchPresented = false

    var body: some View {
        content
            .background(Color.background)
            .navigationTitle(String(localized: "Search", bundle: .module, comment: "Title of the search tab."))
            .searchable(
                text: $model.query,
                isPresented: $isSearchPresented,
                placement: Self.fieldPlacement,
                prompt: String(
                    localized: "Movies, shows and episodes",
                    bundle: .module,
                    comment: "Placeholder in the search field."
                )
            )
            // A task rather than onChange, so the Command-F that first opens this tab isn't missed.
            .task(id: focusRequest) {
                guard focusRequest != answeredFocusRequest else { return }
                answeredFocusRequest = focusRequest
                isSearchPresented = true
            }
            .task(id: SearchKey(term: model.term, revision: actions.revision)) { await model.search(in: media) }
    }

    /// Under the title at every width. On iPad the default folds the field into a toolbar button, which takes a
    /// second tap after choosing Search and which Command-F can't open.
    private static var fieldPlacement: SearchFieldPlacement {
        #if os(iOS)
            .navigationBarDrawer(displayMode: .always)
        #else
            .automatic
        #endif
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
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
        case .searching:
            LoadingState()
        case .failed(let message):
            FailureState(message: message) { Task { await model.search(in: media) } }
        case .results(let results) where results.isEmpty:
            ContentUnavailableView.search(text: model.term)
        case .results(let results):
            SearchResultsView(results: results)
        }
    }

    /// What starts a search: a new term, or a change to played marks or favourites shown in the results.
    private struct SearchKey: Hashable {
        let term: String
        let revision: Int
    }
}

/// Results grouped into movies, shows and episodes.
private struct SearchResultsView: View {
    let results: MediaSearchResults
    @ScaledMetric(relativeTo: .subheadline) private var posterWidth = 104.0
    @ScaledMetric(relativeTo: .subheadline) private var thumbnailWidth = 220.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                section(
                    String(localized: "Movies", bundle: .module, comment: "Search results section."),
                    results.movies,
                    width: posterWidth
                ) { PosterLink(item: $0) }
                section(
                    String(localized: "Shows", bundle: .module, comment: "Search results section."),
                    results.shows,
                    width: posterWidth
                ) { PosterLink(item: $0) }
                section(
                    String(localized: "Episodes", bundle: .module, comment: "Search results section."),
                    results.episodes,
                    width: thumbnailWidth
                ) { LandscapeLink(item: $0) }
            }
            .padding(Spacing.medium)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder private func section<Card: View>(
        _ title: String,
        _ items: [MediaItem],
        width: CGFloat,
        @ViewBuilder card: @escaping (MediaItem) -> Card
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(title)
                    .typography(.title)
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: width), spacing: Spacing.small, alignment: .top)],
                    spacing: Spacing.large
                ) {
                    ForEach(items) { card($0) }
                }
            }
        }
    }
}

#Preview("Light") {
    TabStack { SearchView() }
        .previewEnvironment()
}

#Preview("Dark") {
    TabStack { SearchView() }
        .previewEnvironment()
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TabStack { SearchView() }
        .previewEnvironment()
        .dynamicTypeSize(.accessibility5)
}
