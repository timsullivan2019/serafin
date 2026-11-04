import SerafinDesign
import SwiftUI

/// The Library tab, laid out like the browse pages of the Apple TV and App Store apps: a row of each library's newest
/// titles under the library's own name, then rows of the newest collections and favourites, the best-rated unwatched
/// titles, then the genres. A row's title opens its full grid.
struct LibrariesView: View {
    @State private var model = LibrariesModel()
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions

    var body: some View {
        content
            .background(Color.background)
            .navigationTitle(String(localized: "Library", bundle: .module, comment: "Title of the library tab."))
            .profileToolbar()
            // Again when a favourite or a watched mark changes, which the Favorites and Unwatched rows follow.
            .task(id: actions.revision) { await model.load(from: media) }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Skeleton(.libraries)
        case .failed(let message):
            FailureState(message: message) { Task { await model.load(from: media) } }
        case .loaded where model.rows.isEmpty:
            EmptyState(
                String(localized: "No Libraries", bundle: .module, comment: "Title when the server has no libraries."),
                message: String(
                    localized: "Add a movie or TV library on your server and it appears here.",
                    bundle: .module,
                    comment: "Explanation when there are no movie or TV libraries."
                ),
                systemImage: "square.stack"
            )
        case .loaded where model.visibleRows.isEmpty:
            if model.isSettled {
                EmptyState(
                    String(
                        localized: "Nothing Here Yet", bundle: .module,
                        comment: "Title when Home or the Library tab is empty."),
                    message: String(
                        localized: "Movies and shows you add to your server appear here.",
                        bundle: .module,
                        comment: "Explanation when Home or the Library tab is empty."
                    ),
                    systemImage: "sparkles.tv"
                )
            } else {
                // Every library is empty, and the rows after them are still on their way.
                Skeleton(.libraries)
            }
        case .loaded:
            rows
        }
    }

    private var rows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.large) {
                ForEach(model.visibleRows) { row in
                    LibraryRowView(row: row, model: model)
                }
            }
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.medium)
        }
        // Rows scrolling up under the bar soften into it, as on Home.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable {
            await media.refresh()
            await model.load(from: media)
        }
    }
}

/// One row: its title, which opens the row's grid, over its newest posters, with placeholder cards until they
/// arrive; or the genre tiles.
private struct LibraryRowView: View {
    let row: LibrariesModel.Row
    let model: LibrariesModel
    @Environment(\.navigate) private var navigate

    var body: some View {
        if row == .genres {
            GenresRow(genres: model.genres ?? [], generation: model.generation) { navigate(row.route) }
        } else {
            MediaRow(
                row.title,
                style: .largePosters,
                items: RowSlot.slots(model.titles[row]),
                seeAll: { navigate(row.route) }
            ) { slot in
                switch slot {
                case .title(let item):
                    // A title can be in more than one row, so each row's cards zoom on their own.
                    PosterLink(item: item, zoomScope: row.id)
                case .placeholder(let index):
                    SkeletonCard(aspectRatio: 2 / 3)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            String(localized: "Loading", bundle: .module, comment: "Spoken while content loads.")
                        )
                        // One "Loading" for the row is enough.
                        .accessibilityHidden(index > 0)
                }
            }
        }
    }
}

/// A place in a row: one of its titles, or a placeholder card while they load.
private enum RowSlot: Identifiable {
    case title(MediaItem)
    case placeholder(Int)

    var id: String {
        switch self {
        case .title(let item): item.id
        case .placeholder(let index): "placeholder-\(index)"
        }
    }

    /// A row's places: its titles once they've loaded, until then enough placeholders to fill the widest window.
    static func slots(_ titles: [MediaItem]?) -> [RowSlot] {
        titles.map { $0.map(RowSlot.title) } ?? (0..<8).map(RowSlot.placeholder)
    }
}

/// The Genres row: a tile for each genre, which opens the genre's grid.
private struct GenresRow: View {
    let genres: [Genre]
    let generation: Int
    let seeAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            RowHeader(LibrariesModel.Row.genres.title, seeAll: seeAll)
                .padding(.horizontal, Spacing.medium)
            ScrollView(.horizontal) {
                // Lazy, so each tile asks for its posters as it comes on screen. The tiles are all one size, so the
                // row never needs the ones not yet made to know its height.
                LazyHStack(spacing: Spacing.small) {
                    ForEach(genres) { genre in
                        GenreLink(genre: genre, generation: generation)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Spacing.medium, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }
}

/// A genre's tile, which opens the genre's grid. It shows the posters of the genre's two newest titles, or the
/// backdrop of its only one.
private struct GenreLink: View {
    let genre: Genre
    /// The tab's load, so loading again brings the newest artwork.
    let generation: Int
    @State private var newest: [MediaItem] = []
    @Environment(\.media) private var media

    var body: some View {
        NavigationLink(value: Route.genre(genre)) {
            GenreTile(name: genre.name) {
                if newest.count >= 2 {
                    PosterPair { index in
                        ItemArtwork(newest[index], role: .poster) { CollagePoster(image: $0) }
                    }
                } else if let only = newest.first {
                    // A genre with one title fills the tile with its backdrop, rather than leave half of it bare.
                    ItemArtwork(only, role: .backdrop) { CollagePoster(image: $0) }
                } else {
                    CollagePoster(image: nil)
                }
            }
        }
        .buttonStyle(.card)
        .task(id: Load(genre: genre, generation: generation)) {
            // Without an answer, the tile keeps the artwork it has.
            let page = try? await media.page(
                of: .genre(genre), options: LibrariesModel.newestFirst, start: 0, limit: 2)
            if let page {
                newest = page.items.compactMap { $0 }
            }
        }
    }

    private struct Load: Hashable {
        let genre: Genre
        let generation: Int
    }
}

#if DEBUG
    #Preview("Light") {
        TabStack { LibrariesView() }
            .previewEnvironment()
    }

    #Preview("Dark") {
        TabStack { LibrariesView() }
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TabStack { LibrariesView() }
            .previewEnvironment()
            .dynamicTypeSize(.accessibility5)
    }

    #Preview("No favorites") {
        TabStack { LibrariesView() }
            .environment(\.media, SampleMediaSource(includesFavourites: false))
            .previewEnvironment()
    }

    #Preview("No collections") {
        TabStack { LibrariesView() }
            .environment(\.media, SampleMediaSource(includesCollections: false))
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }
#endif
