import JellyfinAPI

/// What a library grid shows: which items, in what order, and which filters are on.
public struct LibraryQuery: Hashable, Sendable {
    /// How a library grid is ordered.
    public enum Sort: Hashable, Sendable, CaseIterable {
        /// By title, ignoring leading articles, as the server sorts names.
        case name
        /// By when the item was added to the server.
        case dateAdded
        /// By release date.
        case premiereDate
        /// By community rating.
        case rating

        /// What the server sorts by. Ties fall back to the title, so pages never shuffle.
        var fields: [ItemSortBy] {
            switch self {
            case .name: [.sortName]
            case .dateAdded: [.dateCreated, .sortName]
            case .premiereDate: [.premiereDate, .sortName]
            case .rating: [.communityRating, .sortName]
            }
        }
    }

    /// The library, or any folder, to list. Nil lists across every library.
    public var parentID: String?
    /// The kinds of item to list, such as movies or shows.
    public var types: [BaseItemKind]
    /// The order.
    public var sort: Sort
    /// Whether the order runs from A to Z, oldest to newest and lowest to highest.
    public var ascending: Bool
    /// Whether to list only items the user hasn't watched.
    public var unplayedOnly: Bool
    /// Whether to list only the user's favourites.
    public var favouritesOnly: Bool
    /// The genres an item must have one of, or empty for any.
    public var genres: [String]
    /// The years an item must come from one of, or empty for any.
    public var years: [Int]

    /// Creates a query.
    public init(
        parentID: String?,
        types: [BaseItemKind],
        sort: Sort = .name,
        ascending: Bool = true,
        unplayedOnly: Bool = false,
        favouritesOnly: Bool = false,
        genres: [String] = [],
        years: [Int] = []
    ) {
        self.parentID = parentID
        self.types = types
        self.sort = sort
        self.ascending = ascending
        self.unplayedOnly = unplayedOnly
        self.favouritesOnly = favouritesOnly
        self.genres = genres
        self.years = years
    }
}

/// One page of a library grid.
public struct ItemPage: Sendable {
    /// The items on this page.
    public let items: [BaseItemDto]
    /// The position of the first item in the whole list.
    public let start: Int
    /// How many items the whole list has.
    public let total: Int

    /// Whether there are items after this page.
    public var hasMore: Bool {
        start + items.count < total
    }
}

/// What a search found, grouped the way the search screen lists it.
public struct SearchResults: Sendable {
    /// Matching movies.
    public let movies: [BaseItemDto]
    /// Matching shows.
    public let series: [BaseItemDto]
    /// Matching episodes.
    public let episodes: [BaseItemDto]

    /// Whether nothing matched.
    public var isEmpty: Bool {
        movies.isEmpty && series.isEmpty && episodes.isEmpty
    }

    /// No results, for an empty search.
    public static let none = SearchResults(movies: [], series: [], episodes: [])
}

/// The genres and years a library's items have, for its filter menus.
public struct LibraryFilters: Hashable, Sendable {
    /// Genre names, in alphabetical order.
    public let genres: [String]
    /// Release years, newest first.
    public let years: [Int]

    /// Creates the filters.
    public init(genres: [String], years: [Int]) {
        self.genres = genres
        self.years = years
    }
}
