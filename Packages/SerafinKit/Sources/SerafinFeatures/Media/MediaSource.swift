import JellyfinAPI
import SerafinCore
import SerafinDesign
import SwiftUI

/// What the home screen shows.
struct HomeContent: Sendable {
    /// The newest items of one library, shown as a row of posters.
    struct LatestRow: Identifiable, Sendable {
        let library: MediaLibrary
        let items: [MediaItem]
        var id: String { library.id }
    }

    /// Started movies and episodes, most recent first.
    var continueWatching: [MediaItem]
    /// The next episode of each show the user is part way through.
    var nextUp: [MediaItem]
    /// The newest items in each library.
    var latest: [LatestRow]
    /// When the server sent these rows.
    var date = Date.now

    /// Whether every row is empty, which shows the empty state.
    var isEmpty: Bool {
        continueWatching.isEmpty && nextUp.isEmpty && latest.allSatisfy(\.items.isEmpty)
    }
}

/// How a library grid is sorted and filtered.
struct GridOptions: Hashable, Sendable {
    /// The order.
    var sort = LibraryQuery.Sort.name
    /// Whether the order runs A to Z, oldest first or lowest first.
    var ascending = true
    /// Whether to show only items the user hasn't watched.
    var unplayedOnly = false
    /// Whether to show only favourites.
    var favouritesOnly = false
    /// The one genre to show, or nil for all.
    var genre: String?
    /// The one year to show, or nil for all.
    var year: Int?

    /// Whether any filter is on, which changes what the empty state says.
    var isFiltered: Bool {
        unplayedOnly || favouritesOnly || genre != nil || year != nil
    }
}

/// One page of a grid.
struct MediaPage: Sendable {
    /// The page's items, in order. An item Serafin can't show leaves a gap, so every later position stays true.
    let items: [MediaItem?]
    /// How many items the whole grid has.
    let total: Int
}

/// A genre of the user's movies and shows.
struct Genre: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// How many movies and shows have the genre, when the server says.
    let count: Int?
}

/// What a grid lists.
enum GridScope: Hashable, Sendable {
    /// One library's movies or shows.
    case library(MediaLibrary)
    /// The movies and shows in one genre, from every library.
    case genre(Genre)
    /// Every collection on the server.
    case collections
    /// The movies and shows in one collection.
    case collection(id: String, title: String)
    /// Every movie and show, filtered or sorted one way, from the Library tab's Browse list.
    case shortcut(LibraryShortcut)

    /// The grid's title.
    var title: String {
        switch self {
        case .library(let library): library.name
        case .genre(let genre): genre.name
        case .collections:
            String(localized: "Collections", bundle: .module, comment: "Collections, as a heading or a label.")
        case .collection(_, let title): title
        case .shortcut(let shortcut): shortcut.title
        }
    }

    /// Whether the grid offers the filter and sort chips. A collection's own order is the point of it, and the
    /// list of collections is browsed by name.
    var offersChips: Bool {
        switch self {
        case .library, .genre, .shortcut: true
        case .collections, .collection: false
        }
    }

    /// The order the grid starts in: a collection in release order, a shortcut its own way, everything else by
    /// name.
    var initialOptions: GridOptions {
        switch self {
        case .collection: GridOptions(sort: .premiereDate, ascending: true)
        case .shortcut(let shortcut): shortcut.options
        case .library, .genre, .collections: GridOptions()
        }
    }
}

/// A way into every movie and show at once, from the Library tab's Browse list.
enum LibraryShortcut: String, CaseIterable, Hashable, Sendable {
    /// Favourites, by name.
    case favourites
    /// Newest additions first.
    case recentlyAdded
    /// Everything not yet watched, by name.
    case unwatched

    /// The grid's title and the Browse row's name.
    var title: String {
        switch self {
        case .favourites:
            String(
                localized: "Favourites", bundle: .module,
                comment: "Favourites: the library filter chip, and the Library tab's Browse row and grid.")
        case .recentlyAdded:
            String(
                localized: "Recently Added", bundle: .module,
                comment: "Library Browse row and grid of the newest additions.")
        case .unwatched:
            String(
                localized: "Unwatched", bundle: .module,
                comment: "Library Browse row and grid of everything not yet watched.")
        }
    }

    /// The Browse row's symbol.
    var systemImage: String {
        switch self {
        case .favourites: "heart.fill"
        case .recentlyAdded: "clock.fill"
        case .unwatched: "circle.dashed"
        }
    }

    /// The grid's starting sort and filters.
    var options: GridOptions {
        switch self {
        case .favourites: GridOptions(favouritesOnly: true)
        case .recentlyAdded: GridOptions(sort: .dateAdded, ascending: false)
        case .unwatched: GridOptions(unplayedOnly: true)
        }
    }
}

/// A cast or crew member on a detail screen.
struct CastMember: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let role: String?
    /// The server's person, for their photo. Nil for the samples.
    let source: BaseItemPerson?
}

/// Everything a detail screen shows about a movie, show or episode.
struct ItemDetails: Sendable {
    /// The item itself.
    var item: MediaItem
    /// Its cast and crew, in the server's order.
    var cast: [CastMember] = []
    /// A show's seasons.
    var seasons: [MediaItem] = []
    /// The other episodes of an episode's season.
    var seasonEpisodes: [MediaItem] = []
    /// Titles like this one.
    var similar: [MediaItem] = []
    /// What Play starts: the item itself, or for a show, the episode to watch next.
    var playable: MediaItem?
    /// The facts listed under Information.
    var information: [InformationColumns.Column] = []
    /// The media badges under the hero's details, such as 4K and Dolby Atmos.
    var badges: [String] = []
    /// Trailers, stored with the item or linked on the web.
    var trailers: [Trailer] = []
    /// A movie's or an episode's chapters.
    var chapters: [Chapter] = []
}

/// A season's episodes, with the titles its screen shows.
struct SeasonContent: Sendable {
    /// The season's name, such as "Season 1".
    let title: String
    /// The show's name.
    let seriesTitle: String
    /// The episodes, in order.
    let episodes: [MediaItem]
}

/// Search matches, grouped the way the results screen shows them.
struct MediaSearchResults: Sendable {
    var movies: [MediaItem] = []
    var shows: [MediaItem] = []
    var episodes: [MediaItem] = []

    var isEmpty: Bool { movies.isEmpty && shows.isEmpty && episodes.isEmpty }
}

/// Where the screens get their media: the signed-in library in the app, the built-in samples in previews.
protocol MediaSource: Sendable {
    /// Continue Watching, Next Up and the newest items in each library.
    func home() async throws -> HomeContent
    /// The rows ``home()`` last returned, kept on the device for when the server can't be reached, or nil when there
    /// are none.
    func savedHome() async -> HomeContent?
    /// What to watch next, as Home lists it: started movies and episodes, most recent first, then the next episode of
    /// each show in progress.
    func nextToWatch() async throws -> [MediaItem]
    /// Every movie and episode the user has started and not finished, most recent first, for Continue Watching's
    /// own screen.
    func continueWatching() async throws -> [MediaItem]
    /// The next episode of every show the user is part way through, for Next Up's own screen.
    func nextUp() async throws -> [MediaItem]
    /// The episode a show's Play button starts: the one in progress or next, or the first when the show hasn't been
    /// started or has been watched through. Nil for a show with no episodes.
    func playable(ofSeries id: String) async throws -> MediaItem?
    /// One movie, show or episode.
    func item(_ id: String) async throws -> MediaItem
    /// The user's movie and TV libraries.
    func libraries() async throws -> [MediaLibrary]
    /// A library's own picture, when the server has one, for its tile on the Library tab.
    func cover(of library: MediaLibrary) async -> MediaItem?
    /// One page of a grid.
    func page(of scope: GridScope, options: GridOptions, start: Int, limit: Int) async throws -> MediaPage
    /// The genres and years in a grid, for its filter menus. Only a library's grid has them.
    func filters(in scope: GridScope) async throws -> LibraryFilters
    /// How many items in a grid sort before `name`, for the letter index. Names compare as the server's lowercase
    /// sort names, which drop leading articles.
    func count(in scope: GridScope, options: GridOptions, before name: String) async throws -> Int
    /// The genres of the user's movies and shows, in alphabetical order.
    func genres() async throws -> [Genre]
    /// Whether the server has any collections.
    func hasCollections() async throws -> Bool
    /// Everything a detail screen shows about an item.
    func details(of id: String) async throws -> ItemDetails
    /// A season's episodes.
    func season(_ id: String, of seriesID: String) async throws -> SeasonContent
    /// Movies, shows and episodes matching `term`.
    func search(_ term: String) async throws -> MediaSearchResults
    /// Whether the signed-in user may ask the server to refresh an item's metadata, which administrators can.
    func canRefreshMetadata() async -> Bool
    /// Asks the server to look up an item's metadata again.
    func refreshMetadata(of item: MediaItem) async throws
    /// Marks an item played or not.
    func setPlayed(_ isPlayed: Bool, for item: MediaItem) async throws
    /// Adds an item to the favourites or takes it out.
    func setFavourite(_ isFavourite: Bool, for item: MediaItem) async throws
    /// Forgets cached answers, so the next loads are fresh. Pull to refresh calls this.
    func refresh() async
}

extension EnvironmentValues {
    /// Where screens get their media: the built-in samples, until the app passes the signed-in library.
    @Entry var media: any MediaSource = SampleMediaSource()
    /// Loads artwork from the server. Nil with the samples, which draw generated art.
    @Entry var artwork: Artwork? = nil
}

extension MediaLibrary {
    /// A library from the server's list, or nil for kinds Serafin doesn't show.
    init?(view: BaseItemDto) {
        guard let id = view.id else { return nil }
        let kind: Kind
        switch view.collectionType {
        case .movies: kind = .movies
        case .tvshows: kind = .shows
        case nil: kind = .mixed
        default: return nil
        }
        self.init(id: id, name: view.name ?? "", kind: kind, items: [])
    }
}

extension MediaLibrary.Kind {
    /// Where a library's Latest row goes on Home: movies first, then shows, then libraries of both.
    var homeOrder: Int {
        switch self {
        case .movies: 0
        case .shows: 1
        case .mixed: 2
        }
    }

    /// The kinds of item a grid of this library lists.
    var itemTypes: [BaseItemKind] {
        switch self {
        case .movies: [.movie]
        case .shows: [.series]
        case .mixed: [.movie, .series]
        }
    }

    /// The symbol for the library in lists.
    var systemImage: String {
        switch self {
        case .movies: "film"
        case .shows: "tv"
        case .mixed: "film.stack"
        }
    }
}
