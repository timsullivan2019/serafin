import SerafinCore
import SerafinDesign
import SwiftUI

/// The search tab: recent searches and suggested titles before anything is typed, then results across shows,
/// movies, episodes, people and collections as the user types.
struct SearchView: View {
    @State private var model = SearchModel()
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.searchRequest) private var request
    @State private var answeredRequest = 0
    @State private var isSearchPresented = false

    var body: some View {
        content
            .background(Color.background)
            .navigationTitle(String(localized: "Search", bundle: .module, comment: "Title of the search tab."))
            .profileToolbar()
            .searchable(
                text: $model.query,
                isPresented: $isSearchPresented,
                placement: Self.fieldPlacement,
                prompt: String(
                    localized: "Movies, shows and people",
                    bundle: .module,
                    comment: "Placeholder in the search field."
                )
            )
            .onSubmit(of: .search) { model.remember() }
            // A task rather than onChange, so the request that first opens this tab isn't missed.
            .task(id: request) {
                guard request.number != answeredRequest else { return }
                answeredRequest = request.number
                if let term = request.term {
                    // Siri's results show without the keyboard covering them.
                    model.query = term
                    isSearchPresented = false
                } else {
                    isSearchPresented = true
                }
            }
            .task(id: SearchKey(term: model.term, revision: actions.revision)) { await model.search(in: media) }
            .task(id: SuggestionsKey(account: session?.account?.key, revision: actions.revision)) {
                model.showRecents(of: session?.account?.key)
                await model.loadSuggestions(from: media)
            }
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
        case .idle where !model.recents.isEmpty || !model.suggestions.isEmpty:
            SearchStart(model: model)
        case .idle where !model.hasLoadedSuggestions:
            // A moment's blank while the suggestions load, rather than an explanation that vanishes.
            Color.clear
        case .idle:
            EmptyState(
                String(
                    localized: "Search Your Library", bundle: .module, comment: "Title before anything is searched."),
                message: String(
                    localized: "Find movies, shows, episodes, people and collections by name.",
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
                // Opening a result covers the results, which is when a search has found what it was for.
                .onDisappear {
                    if model.isShowingResults { model.remember() }
                }
        }
    }

    /// What starts a search: a new term, or a change to played marks or favourites shown in the results.
    private struct SearchKey: Hashable {
        let term: String
        let revision: Int
    }

    /// What reloads the recent searches and suggestions: another account, or a change to played marks.
    private struct SuggestionsKey: Hashable {
        let account: SessionKey?
        let revision: Int
    }
}

/// Before anything is typed: recent searches to run again, and a few suggested titles.
private struct SearchStart: View {
    let model: SearchModel
    @ScaledMetric(relativeTo: .subheadline) private var posterWidth = 104.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                if !model.recents.isEmpty {
                    RecentSearchesList(model: model)
                }
                SearchSection(
                    String(
                        localized: "Suggested", bundle: .module,
                        comment:
                            "Heading over titles the user hasn't watched, on the search tab before anything is typed."
                    ),
                    model.suggestions,
                    width: posterWidth
                ) { PosterLink(item: $0) }
            }
            .padding(Spacing.medium)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

/// The recent searches, newest first, each running again when tapped, with a button that clears them.
private struct RecentSearchesList: View {
    let model: SearchModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "Recent", bundle: .module, comment: "Heading over recent searches."))
                    .typography(.title)
                    .foregroundStyle(.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(String(localized: "Clear", bundle: .module, comment: "Button that forgets recent searches.")) {
                    model.clearRecents()
                }
                .accessibilityLabel(
                    String(
                        localized: "Clear Recent Searches", bundle: .module,
                        comment: "Spoken label of the button that forgets recent searches.")
                )
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.recents, id: \.self) { recent in
                    Button {
                        model.searchAgain(recent)
                    } label: {
                        Label {
                            Text(recent)
                                .foregroundStyle(.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } icon: {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.textSecondary)
                        }
                        .padding(.vertical, Spacing.small)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        String(
                            localized: "Searches for this again", bundle: .module,
                            comment: "Hint on a recent search.")
                    )
                    if recent != model.recents.last {
                        Divider()
                    }
                }
            }
        }
    }
}

/// Results grouped into shows, movies, episodes, people and collections, in that order.
private struct SearchResultsView: View {
    let results: MediaSearchResults
    @ScaledMetric(relativeTo: .subheadline) private var posterWidth = 104.0
    @ScaledMetric(relativeTo: .subheadline) private var thumbnailWidth = 220.0
    @ScaledMetric(relativeTo: .subheadline) private var personWidth = 96.0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                SearchSection(
                    String(localized: "Shows", bundle: .module, comment: "Search results section."),
                    results.shows,
                    width: posterWidth
                ) { PosterLink(item: $0) }
                SearchSection(
                    String(localized: "Movies", bundle: .module, comment: "Search results section."),
                    results.movies,
                    width: posterWidth
                ) { PosterLink(item: $0) }
                SearchSection(
                    String(localized: "Episodes", bundle: .module, comment: "Search results section."),
                    results.episodes,
                    width: thumbnailWidth
                ) { LandscapeLink(item: $0) }
                SearchSection(
                    String(localized: "People", bundle: .module, comment: "Search results section."),
                    results.people,
                    width: personWidth
                ) { PersonLink(person: $0) }
                SearchSection(
                    String(
                        localized: "Collections", bundle: .module, comment: "Collections, as a heading or a label."),
                    results.collections,
                    width: posterWidth
                ) { PosterLink(item: $0) }
            }
            .padding(Spacing.medium)
        }
        .scrollDismissesKeyboard(.immediately)
    }
}

/// A heading over a grid of cards, or nothing when there are no cards.
private struct SearchSection<Item: Identifiable, Card: View>: View {
    let title: String
    let items: [Item]
    let width: CGFloat
    @ViewBuilder let card: (Item) -> Card

    init(_ title: String, _ items: [Item], width: CGFloat, @ViewBuilder card: @escaping (Item) -> Card) {
        self.title = title
        self.items = items
        self.width = width
        self.card = card
    }

    var body: some View {
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

#if DEBUG
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
#endif
