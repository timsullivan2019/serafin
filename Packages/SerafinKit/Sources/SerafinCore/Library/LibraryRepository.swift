import Foundation
import JellyfinAPI

/// One signed-in user's library on one server: everything Home, Library, Search and the detail screens show.
///
/// Each call is one request, except ``home()``. Reads are answered from a short-lived cache when the same request was
/// made recently, so going back to a screen is instant. Marking an item played or favourite empties the cache, since
/// it changes what Home shows.
///
/// Lists ask only for the fields cards need. ``item(id:)`` returns everything a detail screen shows.
///
/// The last Home the server sent is also kept on the device, so Home can show it when the server can't be reached.
public actor LibraryRepository {
    /// How long a read is answered from the cache before the server is asked again.
    public static let defaultCacheLifetime: Duration = .seconds(60)

    /// The fields lists ask for beyond Jellyfin's defaults.
    static let cardFields: [ItemFields] = [.primaryImageAspectRatio, .overview]
    /// The image types lists ask for, one of each.
    static let cardImages: [ImageType] = [.primary, .backdrop, .thumb, .logo]
    /// The kinds of library Serafin shows. A library without a kind holds a mix of movies and shows.
    static let supportedCollections: Set<CollectionType?> = [.movies, .tvshows, nil]

    /// The user the library belongs to.
    public nonisolated let userID: String

    private let client: JellyfinClient
    private let errors: ServerErrors
    private var cache: ResponseCache
    /// Where this account's last Home is kept, or nil to keep none.
    private let homeSnapshots: HomeSnapshotStore.Slot?

    init(
        client: JellyfinClient,
        userID: String,
        errors: ServerErrors,
        cacheLifetime: Duration = LibraryRepository.defaultCacheLifetime,
        homeSnapshots: HomeSnapshotStore.Slot? = nil
    ) {
        self.client = client
        self.userID = userID
        self.errors = errors
        self.cache = ResponseCache(lifetime: cacheLifetime)
        self.homeSnapshots = homeSnapshots
    }

    // MARK: - Home

    /// Everything Home shows, asked of the server now, and kept on the device for ``savedHome()``.
    ///
    /// One library's newest items failing to load leaves that library's row empty. The whole call fails only when the
    /// libraries, Continue Watching or Next Up do, and then the Home kept before stays.
    public func home() async throws -> HomeSnapshot {
        async let resume = resume()
        async let nextUp = nextUp()
        let libraries = try await userViews()
        let latest = await withTaskGroup(of: (String, [BaseItemDto]).self) { group in
            for id in libraries.compactMap(\.id) {
                group.addTask { (id, (try? await self.latest(in: id)) ?? []) }
            }
            var rows: [String: [BaseItemDto]] = [:]
            for await (id, items) in group {
                rows[id] = items
            }
            return rows
        }
        let snapshot = HomeSnapshot(
            date: .now, libraries: libraries, resume: try await resume, nextUp: try await nextUp, latest: latest)
        // A cancelled load may have lost rows on the way, so it doesn't replace the Home kept before.
        try Task.checkCancellation()
        await homeSnapshots?.save(snapshot)
        return snapshot
    }

    /// The last Home the server sent this account, kept on the device, or nil when there's none.
    public func savedHome() async -> HomeSnapshot? {
        await homeSnapshots?.load()
    }

    /// The user's movie and TV libraries, in the server's order. Music, books, photos and other kinds of library are
    /// left out.
    public func userViews() async throws -> [BaseItemDto] {
        let request = Paths.getUserViews(parameters: Paths.GetUserViewsParameters(userID: userID))
        let result = try await cached(request.url, request.query) { try await client.send(request).value }
        return (result.items ?? []).filter { Self.supportedCollections.contains($0.collectionType) }
    }

    /// Movies and episodes the user has started and not finished, most recent first.
    public func resume(limit: Int = 20) async throws -> [BaseItemDto] {
        var parameters = Paths.GetResumeItemsParameters(userID: userID, limit: limit)
        parameters.fields = Self.cardFields
        parameters.mediaTypes = [.video]
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = Self.cardImages
        let request = Paths.getResumeItems(parameters: parameters)
        return try await cached(request.url, request.query) { try await client.send(request).value }.items ?? []
    }

    /// The next episode to watch in each show the user is part way through. Episodes already started are in
    /// ``resume(limit:)`` instead.
    ///
    /// - Parameters:
    ///   - limit: The most episodes to return.
    ///   - seriesID: One show to ask about, for its Play button. The answer then includes an episode the user has
    ///     started, since Play resumes it.
    public func nextUp(limit: Int = 20, series seriesID: String? = nil) async throws -> [BaseItemDto] {
        var parameters = Paths.GetNextUpParameters(userID: userID, limit: limit)
        parameters.seriesID = seriesID
        parameters.fields = Self.cardFields
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = Self.cardImages
        parameters.enableUserData = true
        parameters.enableResumable = seriesID != nil
        let request = Paths.getNextUp(parameters: parameters)
        return try await cached(request.url, request.query) { try await client.send(request).value }.items ?? []
    }

    /// The newest additions to a library, with new episodes grouped under their show.
    ///
    /// - Parameters:
    ///   - viewID: The library, from ``userViews()``.
    ///   - limit: The most items to return.
    public func latest(in viewID: String, limit: Int = 16) async throws -> [BaseItemDto] {
        var parameters = Paths.GetLatestMediaParameters(userID: userID, parentID: viewID)
        parameters.fields = Self.cardFields
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = Self.cardImages
        parameters.enableUserData = true
        parameters.limit = limit
        parameters.isGroupItems = true
        let request = Paths.getLatestMedia(parameters: parameters)
        return try await cached(request.url, request.query) { try await client.send(request).value }
    }

    // MARK: - Browsing

    /// One page of a library grid.
    ///
    /// - Parameters:
    ///   - query: What to list, in what order, with which filters.
    ///   - start: The position of the first item to return.
    ///   - limit: The most items to return.
    public func items(_ query: LibraryQuery, start: Int = 0, limit: Int = 60) async throws -> ItemPage {
        var parameters = Self.parameters(for: query, userID: userID)
        parameters.startIndex = start
        parameters.limit = limit
        parameters.fields = Self.cardFields
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = Self.cardImages
        let request = Paths.getItems(parameters: parameters)
        let result = try await cached(request.url, request.query) { try await client.send(request).value }
        let items = result.items ?? []
        return ItemPage(items: items, start: result.startIndex ?? start, total: result.totalRecordCount ?? items.count)
    }

    /// How many items of a grid sort before `name`, which is where a grid sorted by name reaches it. The server
    /// compares sort names, which are lowercase and drop leading articles, so "The General" counts under G.
    ///
    /// - Parameters:
    ///   - query: The grid, with its filters.
    ///   - name: The name to count up to, such as "m".
    public func count(_ query: LibraryQuery, before name: String) async throws -> Int {
        var parameters = Self.parameters(for: query, userID: userID)
        parameters.nameLessThan = name
        parameters.limit = 0
        let request = Paths.getItems(parameters: parameters)
        let result = try await cached(request.url, request.query) { try await client.send(request).value }
        return result.totalRecordCount ?? 0
    }

    /// The genres of the user's movies and shows, in alphabetical order, with how many of each there are.
    ///
    /// - Parameter types: The kinds of item whose genres to list.
    public func genres(of types: [BaseItemKind] = [.movie, .series]) async throws -> [BaseItemDto] {
        var parameters = Paths.GetGenresParameters()
        parameters.userID = userID
        parameters.includeItemTypes = types
        parameters.fields = [.itemCounts]
        parameters.sortBy = [.sortName]
        parameters.sortOrder = [.ascending]
        parameters.enableTotalRecordCount = false
        let request = Paths.getGenres(parameters: parameters)
        return try await cached(request.url, request.query) { try await client.send(request).value }.items ?? []
    }

    /// The genres and years of a library's items, for the grid's filter menus.
    ///
    /// - Parameters:
    ///   - viewID: The library, from ``userViews()``.
    ///   - types: The kinds of item the grid lists.
    public func filters(in viewID: String, types: [BaseItemKind]) async throws -> LibraryFilters {
        var parameters = Paths.GetQueryFiltersLegacyParameters(userID: userID, parentID: viewID)
        parameters.includeItemTypes = types
        let request = Paths.getQueryFiltersLegacy(parameters: parameters)
        let result = try await cached(request.url, request.query) { try await client.send(request).value }
        let genres = Set(result.genres ?? []).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return LibraryFilters(genres: genres, years: Set(result.years ?? []).sorted(by: >))
    }

    /// Everything about one item, for its detail screen.
    ///
    /// - Throws: ``SerafinError/notFound`` when the item is no longer on the server, or when `id` isn't an ID
    ///   Jellyfin would issue, as from a doctored shortcut.
    public func item(id: String) async throws -> BaseItemDto {
        guard ItemID.isPlain(id) else { throw SerafinError.notFound }
        let request = Paths.getItem(itemID: id, userID: userID)
        return try await cached(request.url, request.query, statuses: [404: .notFound]) {
            try await client.send(request).value
        }
    }

    /// A show's seasons, in order.
    public func seasons(series seriesID: String) async throws -> [BaseItemDto] {
        var parameters = Paths.GetSeasonsParameters(userID: userID)
        parameters.fields = Self.cardFields
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = Self.cardImages
        parameters.enableUserData = true
        let request = Paths.getSeasons(seriesID: seriesID, parameters: parameters)
        return try await cached(request.url, request.query, statuses: [404: .notFound]) {
            try await client.send(request).value
        }.items ?? []
    }

    /// The episodes of one season of a show, in order.
    public func episodes(series seriesID: String, season seasonID: String) async throws -> [BaseItemDto] {
        var parameters = Paths.GetEpisodesParameters(userID: userID)
        parameters.seasonID = seasonID
        parameters.fields = Self.cardFields
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = Self.cardImages
        parameters.enableUserData = true
        let request = Paths.getEpisodes(seriesID: seriesID, parameters: parameters)
        return try await cached(request.url, request.query, statuses: [404: .notFound]) {
            try await client.send(request).value
        }.items ?? []
    }

    /// Titles like the item, for the row at the bottom of its detail screen.
    public func similar(to itemID: String, limit: Int = 12) async throws -> [BaseItemDto] {
        var parameters = Paths.GetSimilarItemsParameters(userID: userID, limit: limit)
        parameters.fields = Self.cardFields
        let request = Paths.getSimilarItems(itemID: itemID, parameters: parameters)
        return try await cached(request.url, request.query) { try await client.send(request).value }.items ?? []
    }

    /// Movies, shows and episodes whose names match `term`, grouped by kind, closest titles first. An empty term finds
    /// nothing without asking the server.
    ///
    /// - Parameters:
    ///   - term: What the user typed.
    ///   - limit: The most results of each kind.
    public func search(term: String, limit: Int = 24) async throws -> SearchResults {
        let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return .none }
        async let movies = search(term, kind: .movie, limit: limit)
        async let series = search(term, kind: .series, limit: limit)
        async let episodes = search(term, kind: .episode, limit: limit)
        return try await SearchResults(movies: movies, series: series, episodes: episodes)
    }

    // MARK: - Played and favourites

    /// Marks an item played, and returns the user's data for it as the server now has it.
    @discardableResult
    public func markPlayed(id: String) async throws -> UserItemDataDto {
        let request = Paths.markPlayedItem(itemID: id, userID: userID)
        return try await changing { try await client.send(request).value }
    }

    /// Marks an item not played, and returns the user's data for it as the server now has it.
    @discardableResult
    public func markUnplayed(id: String) async throws -> UserItemDataDto {
        let request = Paths.markUnplayedItem(itemID: id, userID: userID)
        return try await changing { try await client.send(request).value }
    }

    /// Adds an item to the user's favourites or takes it out, and returns the user's data for it as the server now
    /// has it.
    @discardableResult
    public func setFavourite(id: String, on isFavourite: Bool) async throws -> UserItemDataDto {
        let request =
            isFavourite
            ? Paths.markFavoriteItem(itemID: id, userID: userID)
            : Paths.unmarkFavoriteItem(itemID: id, userID: userID)
        return try await changing { try await client.send(request).value }
    }

    /// Forgets every cached answer, so the next reads ask the server. Pull to refresh calls this first.
    public func clearCache() {
        cache.removeAll()
    }

    // MARK: - Language preferences

    /// The user's audio and subtitle language preferences, as saved on the server. Always asks the server, since
    /// another Jellyfin app may have changed them.
    public func languagePreferences() async throws -> LanguagePreferences {
        LanguagePreferences(configuration: try await userConfiguration())
    }

    /// Saves the user's audio and subtitle language preferences on the server.
    ///
    /// The server replaces a user's settings as a whole, so the rest of them go back exactly as the server sent them,
    /// including any this version of Serafin doesn't know about.
    public func setLanguagePreferences(_ preferences: LanguagePreferences) async throws {
        let configuration = preferences.applied(to: try await userConfiguration())
        let body = try JSONEncoder().encode(AnyJSON.object(configuration))
        // The SDK's typed settings would drop the ones it doesn't know, so the request carries the server's own.
        let request = Paths.updateUserConfiguration(userID: userID, UserConfiguration())
        try await sending(statuses: [:]) {
            _ = try await client.send(request) { $0.httpBody = body }
        }
    }

    /// The languages the server knows, for choosing preferences.
    public func languages() async throws -> [Language] {
        let request = Paths.getCultures
        let cultures = try await cached(request.url, request.query) { try await client.send(request).value }
        var seen: Set<String> = []
        return cultures.compactMap(Language.init).filter { seen.insert($0.code).inserted }
    }

    /// The signed-in user's settings exactly as the server sends them.
    private func userConfiguration() async throws -> [String: AnyJSON] {
        let data = try await sending(statuses: [:]) { try await client.data(for: Paths.getCurrentUser).value }
        guard
            case .object(let user)? = try? JSONDecoder().decode(AnyJSON.self, from: data),
            case .object(let configuration)? = user["Configuration"]
        else { throw SerafinError.unexpectedResponse(status: nil) }
        return configuration
    }

    // MARK: - Helpers

    /// The parts of an items request that say which items a grid lists and in what order.
    private static func parameters(for query: LibraryQuery, userID: String) -> Paths.GetItemsParameters {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.parentID = query.parentID
        parameters.includeItemTypes = query.types.isEmpty ? nil : query.types
        parameters.isRecursive = true
        parameters.sortBy = query.sort.fields
        parameters.sortOrder = [query.ascending ? .ascending : .descending]
        var filters: [ItemFilter] = []
        if query.unplayedOnly { filters.append(.isUnplayed) }
        if query.favouritesOnly { filters.append(.isFavorite) }
        parameters.filters = filters.isEmpty ? nil : filters
        parameters.genres = query.genres.isEmpty ? nil : query.genres
        parameters.years = query.years.isEmpty ? nil : query.years
        parameters.enableTotalRecordCount = true
        return parameters
    }

    private func search(_ term: String, kind: BaseItemKind, limit: Int) async throws -> [BaseItemDto] {
        var parameters = Paths.GetItemsParameters(userID: userID)
        parameters.searchTerm = term
        parameters.includeItemTypes = [kind]
        parameters.isRecursive = true
        parameters.limit = limit
        parameters.fields = Self.cardFields + [.sortName]
        parameters.enableUserData = true
        parameters.imageTypeLimit = 1
        parameters.enableImageTypes = Self.cardImages
        let request = Paths.getItems(parameters: parameters)
        let items = try await cached(request.url, request.query) { try await client.send(request).value }.items ?? []
        return SearchRanking.ranked(items, for: term)
    }

    /// Answers a read from the cache, or sends it and caches the answer.
    ///
    /// - Parameters:
    ///   - url: The request's path, part of its cache key.
    ///   - query: The request's query, the rest of its cache key.
    ///   - statuses: What particular HTTP statuses mean for this request, beyond a 401 meaning the user's sign-in
    ///     is no longer accepted.
    ///   - load: Sends the request.
    private func cached<Value: Sendable>(
        _ url: URL?,
        _ query: [(String, String?)]?,
        statuses: [Int: SerafinError] = [:],
        _ load: () async throws -> Value
    ) async throws -> Value {
        let key = ResponseCache.key(url, query)
        if let value: Value = cache.value(for: key) {
            return value
        }
        let value = try await sending(statuses: statuses, load)
        cache.store(value, for: key)
        return value
    }

    /// Sends a change and empties the cache, since a change shows up in many lists.
    private func changing<Value: Sendable>(_ send: () async throws -> Value) async throws -> Value {
        let value = try await sending(statuses: [404: .notFound], send)
        cache.removeAll()
        return value
    }

    private func sending<Value>(statuses: [Int: SerafinError], _ send: () async throws -> Value) async throws -> Value {
        do {
            return try await send()
        } catch {
            let statuses = statuses.merging([401: .notSignedIn]) { mine, _ in mine }
            throw errors.translate(error, from: client.configuration.url, statuses: statuses)
        }
    }
}
