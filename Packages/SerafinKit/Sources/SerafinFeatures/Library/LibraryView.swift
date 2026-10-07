import SerafinCore
import SerafinDesign
import SwiftUI

/// The Library tab: a tile for each library, then other ways in: genres, collections, favourites, the newest
/// additions and everything unwatched.
struct LibrariesView: View {
    @State private var model = LibrariesModel()
    @Environment(\.media) private var media

    var body: some View {
        content
            .navigationTitle(String(localized: "Library", bundle: .module, comment: "Title of the library tab."))
            .profileToolbar()
            .task { await model.load(from: media) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Skeleton(.libraries)
        case .failed(let message):
            FailureState(message: message) { Task { await model.load(from: media) } }
        case .loaded(let libraries) where libraries.isEmpty:
            EmptyState(
                String(localized: "No Libraries", bundle: .module, comment: "Title when the server has no libraries."),
                message: String(
                    localized: "Add a movie or TV library on your server and it appears here.",
                    bundle: .module,
                    comment: "Explanation when there are no movie or TV libraries."
                ),
                systemImage: "square.stack"
            )
        case .loaded(let libraries):
            List {
                Section {
                    LibraryTiles(libraries: libraries, overviews: model.overviews)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section(String(localized: "Browse", bundle: .module, comment: "Library tab section of other ways in."))
                {
                    BrowseRow(
                        String(localized: "Genres", bundle: .module, comment: "Genres, as a heading or a label."),
                        systemImage: "theatermasks.fill", route: .genres)
                    if model.hasCollections {
                        BrowseRow(
                            String(
                                localized: "Collections", bundle: .module,
                                comment: "Collections, as a heading or a label."),
                            systemImage: "rectangle.stack.fill", route: .collections)
                    }
                    ForEach(LibraryShortcut.allCases, id: \.self) { shortcut in
                        BrowseRow(shortcut.title, systemImage: shortcut.systemImage, route: .shortcut(shortcut))
                    }
                }
            }
            .refreshable {
                await media.refresh()
                await model.load(from: media)
            }
        }
    }
}

/// The libraries as 16:9 tiles, laid out by ``LibraryTilesLayout``.
private struct LibraryTiles: View {
    let libraries: [MediaLibrary]
    let overviews: [String: LibrariesModel.Overview]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.navigate) private var navigate

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Spacing.small, alignment: .top),
                count: LibraryTilesLayout.columns(libraries: libraries.count, isRegularWidth: sizeClass == .regular)),
            spacing: Spacing.small
        ) {
            ForEach(libraries) { library in
                // A button rather than a navigation link, which a list would mark with a chevron.
                Button {
                    navigate(.library(library))
                } label: {
                    LibraryTileArtwork(library: library, overview: overviews[library.id])
                }
                .buttonStyle(.card)
            }
        }
    }

}

/// How the Library tab lays out its tiles.
enum LibraryTilesLayout {
    /// How many tiles go in a row: three on iPad, or two when there are only two; two on iPhone, or one each when
    /// there are only one or two. Fewer, larger tiles fill the screen when a server has few libraries.
    static func columns(libraries: Int, isRegularWidth: Bool) -> Int {
        if isRegularWidth { return min(3, max(2, libraries)) }
        return libraries <= 2 ? 1 : 2
    }
}

/// One library's tile: its own picture, or a collage of its newest posters.
private struct LibraryTileArtwork: View {
    let library: MediaLibrary
    let overview: LibrariesModel.Overview?

    var body: some View {
        LibraryTile(
            name: library.name,
            caption: overview.map { LibrariesModel.caption(total: $0.total, kind: library.kind) }
        ) {
            if let cover = overview?.cover {
                ItemArtwork(cover, role: .poster) { CollagePoster(image: $0) }
            } else if let newest = overview?.newest, newest.count >= LibrariesModel.collageSize {
                LibraryCollage { index in
                    ItemArtwork(newest[index], role: .poster) { CollagePoster(image: $0) }
                }
            } else if let first = overview?.newest.first {
                // Too few posters for a collage: the newest title's backdrop fills the tile.
                ItemArtwork(first, role: .backdrop) { CollagePoster(image: $0) }
            } else {
                CollagePoster(image: nil)
            }
        }
    }
}

/// A Browse row: the accent icon, the name, and the screen it opens.
private struct BrowseRow: View {
    let title: String
    let systemImage: String
    let route: Route

    init(_ title: String, systemImage: String, route: Route) {
        self.title = title
        self.systemImage = systemImage
        self.route = route
    }

    var body: some View {
        NavigationLink(value: route) {
            Label {
                Text(title)
            } icon: {
                AccentIcon(systemImage: systemImage)
            }
        }
    }
}

/// What a shortcut's grid says when it holds nothing.
struct ShortcutEmptyState: View {
    let shortcut: LibraryShortcut

    var body: some View {
        switch shortcut {
        case .favourites:
            EmptyState(
                String(localized: "No Favourites", bundle: .module, comment: "Title when there are no favourites."),
                message: String(
                    localized: "Movies and shows you mark as favourites appear here.", bundle: .module,
                    comment: "Explanation when there are no favourites."),
                systemImage: "heart"
            )
        case .recentlyAdded:
            EmptyState(
                String(
                    localized: "Nothing Added Yet", bundle: .module,
                    comment: "Title when no movies or shows have been added."),
                message: String(
                    localized: "Movies and shows added to your server appear here, newest first.", bundle: .module,
                    comment: "Explanation when no movies or shows have been added."),
                systemImage: "clock"
            )
        case .unwatched:
            EmptyState(
                String(
                    localized: "All Caught Up", bundle: .module,
                    comment: "Title when every movie and show has been watched."),
                message: String(
                    localized: "Every movie and show here has been watched.", bundle: .module,
                    comment: "Explanation when every movie and show has been watched."),
                systemImage: "checkmark.circle"
            )
        }
    }
}

/// A poster grid of a library, a genre, the collections or one collection. A library or a genre has glass chips for
/// sorting and filtering floating over it, and a long grid sorted by name has a letter index along its edge.
struct LibraryView: View {
    @State private var model: LibraryModel
    @State private var position = ScrollPosition(idType: Int.self)
    @State private var jump: Task<Void, Never>?
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions
    @ScaledMetric(relativeTo: .subheadline) private var columnWidth = 104.0

    init(scope: GridScope) {
        _model = State(initialValue: LibraryModel(scope: scope))
    }

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.scope.offersChips {
                    LibraryChips(model: model)
                }
            }
            .background(Color.background)
            .navigationTitle(model.scope.title)
            .task(id: ReloadKey(options: model.options, revision: actions.revision)) {
                await model.reload(from: media)
            }
            .onChange(of: model.options) { position.scrollTo(edge: .top) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Skeleton(.posterGrid(columnMinimum: columnWidth))
        case .failed(let message):
            FailureState(message: message) { Task { await model.reload(from: media) } }
        case .loaded where model.total == 0:
            emptyState
        case .loaded:
            grid
        }
    }

    private var grid: some View {
        let letters = model.indexLetters
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                if case .person(let person) = model.scope {
                    PersonHeader(person: person, total: model.total)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: columnWidth), spacing: Spacing.small, alignment: .top)],
                    spacing: Spacing.large
                ) {
                    ForEach(0..<model.total, id: \.self) { index in
                        GridPlace(model: model, index: index)
                    }
                }
                .scrollTargetLayout()
            }
        }
        // Margins rather than padding, so jumping to the top or to a letter lines up with the margins. Padding sits
        // inside the scroll content, and the jump lined the grid itself up with the edge, leaving it shifted left.
        .contentMargins(.leading, Spacing.medium, for: .scrollContent)
        // Room for the letter index, so it never sits on a poster.
        .contentMargins(.trailing, letters.isEmpty ? Spacing.medium : Spacing.large, for: .scrollContent)
        .contentMargins(.vertical, Spacing.small, for: .scrollContent)
        .scrollPosition($position)
        .overlay(alignment: .trailing) {
            if !letters.isEmpty {
                LetterIndex(letters: letters, jump: jumpTo)
                    .padding(.vertical, Spacing.medium)
                    .padding(.trailing, Spacing.xxSmall)
            }
        }
        .refreshable { await model.refresh(from: media) }
    }

    /// Scrolls to the titles under `letter`. A newer letter cancels the jump to an older one, so dragging along the
    /// index lands where the finger stops.
    private func jumpTo(_ letter: String) {
        jump?.cancel()
        jump = Task {
            guard let index = await model.position(of: letter, from: media), !Task.isCancelled else { return }
            position.scrollTo(id: index, anchor: .top)
        }
    }

    @ViewBuilder private var emptyState: some View {
        // A shortcut such as Favourites starts filtered; only filters chosen on top of it are worth clearing.
        if model.options.isFiltered, model.options != model.scope.initialOptions {
            EmptyState(
                String(localized: "No Matches", bundle: .module, comment: "Title when filters hide everything."),
                message: String(
                    localized: "Nothing in this library matches these filters.",
                    bundle: .module,
                    comment: "Explanation when filters hide everything."
                ),
                systemImage: "line.3.horizontal.decrease.circle",
                action: StateAction(
                    String(localized: "Clear Filters", bundle: .module, comment: "Button that turns off all filters.")
                ) {
                    model.options.unplayedOnly = false
                    model.options.favouritesOnly = false
                    model.options.genre = nil
                    model.options.year = nil
                }
            )
        } else {
            switch model.scope {
            case .library(let library):
                EmptyState(
                    String(localized: "This Library Is Empty", bundle: .module, comment: "Title for an empty library."),
                    message: String(
                        localized: "Movies and shows you add to it on your server appear here.",
                        bundle: .module,
                        comment: "Explanation for an empty library or collection."
                    ),
                    systemImage: library.kind.systemImage
                )
            case .genre:
                EmptyState(
                    String(localized: "Nothing in This Genre", bundle: .module, comment: "Title for an empty genre."),
                    message: String(
                        localized: "Movies and shows your server matches to this genre appear here.",
                        bundle: .module,
                        comment: "Explanation for an empty genre."
                    ),
                    systemImage: "theatermasks"
                )
            case .collections:
                EmptyState(
                    String(
                        localized: "No Collections", bundle: .module, comment: "Title when there are no collections."),
                    message: String(
                        localized: "Collections you make on your server appear here.",
                        bundle: .module,
                        comment: "Explanation when there are no collections."
                    ),
                    systemImage: "rectangle.stack"
                )
            case .collection:
                EmptyState(
                    String(
                        localized: "This Collection Is Empty", bundle: .module,
                        comment: "Title for an empty collection."),
                    message: String(
                        localized: "Movies and shows you add to it on your server appear here.",
                        bundle: .module,
                        comment: "Explanation for an empty library or collection."
                    ),
                    systemImage: "rectangle.stack"
                )
            case .shortcut(let shortcut):
                ShortcutEmptyState(shortcut: shortcut)
            case .person(let person):
                EmptyState(
                    String(
                        localized: "Nothing to Watch", bundle: .module,
                        comment: "Title on a person's page when nothing on the server features them."),
                    message: String(
                        localized: "Movies and shows with \(person.name) appear here once they're on your server.",
                        bundle: .module,
                        comment: "Explanation on a person's page when nothing on the server features them."
                    ),
                    systemImage: "person.crop.circle"
                )
            }
        }
    }

    /// What reloads the grid: new options, or a change to played marks or favourites.
    private struct ReloadKey: Hashable {
        let options: GridOptions
        let revision: Int
    }
}

/// The top of a person's page: their photo beside how many of their movies and shows are on the server.
private struct PersonHeader: View {
    let person: CastMember
    let total: Int
    @ScaledMetric(relativeTo: .title) private var size = 88.0

    var body: some View {
        HStack(spacing: Spacing.medium) {
            PersonPhoto(person: person) { photo in
                PersonPortrait(name: person.name, photo: photo)
            }
            .frame(width: size)
            Text(LibrariesModel.caption(total: total, kind: .mixed))
                .typography(.body)
                .foregroundStyle(.textSecondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One place in a grid: its poster once its page has loaded, a placeholder card until then. Coming on screen loads
/// its page, and the pages around it.
private struct GridPlace: View {
    let model: LibraryModel
    let index: Int
    @Environment(\.media) private var media

    var body: some View {
        Group {
            if let item = model.item(at: index) {
                PosterLink(item: item)
            } else {
                SkeletonCard(aspectRatio: 2 / 3)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(localized: "Loading", bundle: .module, comment: "Spoken while content loads.")
                    )
            }
        }
        .task(id: model.generation) { await model.load(around: index, from: media) }
    }
}

/// The filter and sort chips above a library grid: toggles for unplayed and favourites, menus for genre and year,
/// then the sorts, where tapping the current one flips its direction.
///
/// The toggles and the sorts are each a glass group, so their glass flows as selections change; the menus sit
/// between the groups, because a menu inside a glass group loses its own open and close morph.
private struct LibraryChips: View {
    @Bindable var model: LibraryModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.xSmall) {
                toggles
                menus
                sorts
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.xSmall)
        }
        .scrollIndicators(.hidden)
    }

    private var toggles: some View {
        GlassChipGroup {
            GlassChip(
                String(localized: "Unplayed", bundle: .module, comment: "Library filter: hide played items."),
                systemImage: "circle.dashed",
                isSelected: model.options.unplayedOnly
            ) { animate { model.options.unplayedOnly.toggle() } }
            GlassChip(
                String(
                    localized: "Favourites", bundle: .module,
                    comment: "Favourites: the library filter chip, and the Library tab's Browse row and grid."),
                systemImage: "heart",
                isSelected: model.options.favouritesOnly
            ) { animate { model.options.favouritesOnly.toggle() } }
        }
    }

    @ViewBuilder private var menus: some View {
        if !model.filters.genres.isEmpty {
            FilterMenu(
                title: String(localized: "Genre", bundle: .module, comment: "Library filter menu."),
                allTitle: String(localized: "All Genres", bundle: .module, comment: "Genre filter: no filter."),
                options: model.filters.genres,
                label: { $0 },
                selection: $model.options.genre
            )
        }
        if !model.filters.years.isEmpty {
            FilterMenu(
                title: String(localized: "Year", bundle: .module, comment: "Library filter menu."),
                allTitle: String(localized: "All Years", bundle: .module, comment: "Year filter: no filter."),
                options: model.filters.years,
                label: { String($0) },
                selection: $model.options.year
            )
        }
    }

    private var sorts: some View {
        GlassChipGroup {
            ForEach(LibraryQuery.Sort.allCases, id: \.self) { sort in
                GlassChip(
                    sort.title,
                    systemImage: model.options.sort == sort
                        ? (model.options.ascending ? "arrow.up" : "arrow.down") : nil,
                    isSelected: model.options.sort == sort
                ) { animate { model.select(sort) } }
                .accessibilityValue(model.options.sort == sort ? directionDescription : "")
            }
        }
    }

    /// Makes a selection change inside Serafin's spring, so the chips and their neighbours move together.
    private func animate(_ change: () -> Void) {
        withAnimation(Motion.animation(reduceMotion: reduceMotion), change)
    }

    private var directionDescription: String {
        model.options.ascending
            ? String(localized: "Ascending", bundle: .module, comment: "VoiceOver value of the current sort.")
            : String(localized: "Descending", bundle: .module, comment: "VoiceOver value of the current sort.")
    }
}

/// A glass menu chip for one filter, such as genre, that shows its choice once one is picked.
private struct FilterMenu<Option: Hashable>: View {
    let title: String
    let allTitle: String
    let options: [Option]
    let label: (Option) -> String
    @Binding var selection: Option?
    @Environment(\.accent) private var accent

    var body: some View {
        // Clear glass while off, tinted glass once a choice is made, like the toggle chips beside it.
        if selection == nil {
            // The glass style colours its label with the tint, so a plain label needs a plain tint.
            menu.buttonStyle(.glass).tint(.primary)
        } else {
            menu.buttonStyle(.glassProminent).tint(accent)
                .rebuiltForAccent()
        }
    }

    private var menu: some View {
        Menu {
            Picker(title, selection: $selection) {
                Text(allTitle).tag(Option?.none)
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(Option?.some(option))
                }
            }
        } label: {
            HStack(spacing: Spacing.xxSmall + 2) {
                Text(selection.map(label) ?? title)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
            }
            .typography(.cardTitle)
            .frame(minHeight: 32)
        }
    }
}

extension LibraryQuery.Sort {
    /// The sort's name on its chip.
    var title: String {
        switch self {
        case .name:
            String(localized: "Name", bundle: .module, comment: "Library sort option: alphabetical.")
        case .dateAdded:
            String(localized: "Date Added", bundle: .module, comment: "Library sort option: newest additions first.")
        case .premiereDate:
            String(localized: "Release Date", bundle: .module, comment: "Library sort option: newest releases first.")
        case .rating:
            String(localized: "Rating", bundle: .module, comment: "Library sort option: highest rated first.")
        }
    }
}

#if DEBUG
    #Preview("Libraries") {
        TabStack { LibrariesView() }
            .previewEnvironment()
    }

    #Preview("Light") {
        TabStack { LibraryView(scope: .library(MockLibrary.libraries[0])) }
            .previewEnvironment()
    }

    #Preview("Dark") {
        TabStack { LibraryView(scope: .library(MockLibrary.libraries[0])) }
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TabStack { LibraryView(scope: .library(MockLibrary.libraries[1])) }
            .previewEnvironment()
            .dynamicTypeSize(.accessibility5)
    }

    #Preview("Collection") {
        TabStack { LibraryView(scope: .collection(id: "collection-blender-open-movies", title: "Blender Open Movies")) }
            .previewEnvironment()
    }
#endif
