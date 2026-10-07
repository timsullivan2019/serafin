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

/// One page of a library grid.
struct MediaPage: Sendable {
    /// The items on the page.
    let items: [MediaItem]
    /// Where the next page starts, or nil when this is the last.
    let nextStart: Int?
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
    /// Its genres, for the line under the overview.
    var genres: [String] = []
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
    /// The user's movie and TV libraries.
    func libraries() async throws -> [MediaLibrary]
    /// One page of a library grid.
    func page(of library: MediaLibrary, options: GridOptions, start: Int) async throws -> MediaPage
    /// The genres and years in a library, for its filter menus.
    func filters(in library: MediaLibrary) async throws -> LibraryFilters
    /// Everything a detail screen shows about an item.
    func details(of id: String) async throws -> ItemDetails
    /// A season's episodes.
    func season(_ id: String, of seriesID: String) async throws -> SeasonContent
    /// Movies, shows and episodes matching `term`.
    func search(_ term: String) async throws -> MediaSearchResults
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
