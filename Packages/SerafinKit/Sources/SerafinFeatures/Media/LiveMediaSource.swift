import JellyfinAPI
import SerafinCore
import SerafinDesign

/// The signed-in user's library on their server.
struct LiveMediaSource: MediaSource {
    /// The most cast and crew a detail screen lists.
    static let castLimit = 24

    let library: LibraryRepository

    func home() async throws -> HomeContent {
        async let resume = library.resume()
        async let nextUp = library.nextUp()
        let libraries = try await libraries()
        // One library's row failing leaves the others; the whole screen fails only if Home's own rows do.
        let latest = await withTaskGroup(of: (Int, [MediaItem]).self) { group in
            for (index, mediaLibrary) in libraries.enumerated() {
                group.addTask {
                    (index, MediaItem.latest((try? await library.latest(in: mediaLibrary.id)) ?? []))
                }
            }
            var rows = [[MediaItem]](repeating: [], count: libraries.count)
            for await (index, items) in group {
                rows[index] = items
            }
            return rows
        }
        return HomeContent(
            continueWatching: MediaItem.from(try await resume),
            nextUp: MediaItem.from(try await nextUp),
            latest: zip(libraries, latest).map { HomeContent.LatestRow(library: $0, items: $1) }
        )
    }

    func nextToWatch() async throws -> [MediaItem] {
        async let resume = library.resume()
        async let nextUp = library.nextUp()
        return MediaItem.from(try await resume + nextUp)
    }

    func item(_ id: String) async throws -> MediaItem {
        guard let item = MediaItem(try await library.item(id: id)) else { throw SerafinError.notFound }
        return item
    }

    func libraries() async throws -> [MediaLibrary] {
        try await library.userViews().compactMap(MediaLibrary.init(view:))
    }

    func page(of scope: GridScope, options: GridOptions, start: Int, limit: Int) async throws -> MediaPage {
        let page = try await library.items(Self.query(for: scope, options: options), start: start, limit: limit)
        return MediaPage(items: page.items.map(MediaItem.init), total: page.total)
    }

    func filters(in scope: GridScope) async throws -> LibraryFilters {
        guard case .library(let mediaLibrary) = scope else { return LibraryFilters(genres: [], years: []) }
        return try await library.filters(in: mediaLibrary.id, types: mediaLibrary.kind.itemTypes)
    }

    func count(in scope: GridScope, options: GridOptions, before name: String) async throws -> Int {
        try await library.count(Self.query(for: scope, options: options), before: name)
    }

    func genres() async throws -> [Genre] {
        try await library.genres().compactMap(Genre.init)
    }

    func hasCollections() async throws -> Bool {
        try await library.items(LibraryQuery(parentID: nil, types: [.boxSet]), limit: 0).total > 0
    }

    /// What the server lists for a grid.
    static func query(for scope: GridScope, options: GridOptions) -> LibraryQuery {
        var query = LibraryQuery(
            parentID: nil,
            types: [.movie, .series],
            sort: options.sort,
            ascending: options.ascending,
            unplayedOnly: options.unplayedOnly,
            favouritesOnly: options.favouritesOnly,
            genres: options.genre.map { [$0] } ?? [],
            years: options.year.map { [$0] } ?? []
        )
        switch scope {
        case .library(let mediaLibrary):
            query.parentID = mediaLibrary.id
            query.types = mediaLibrary.kind.itemTypes
        case .genre(let genre):
            query.genres = [genre.name]
        case .collections:
            query.types = [.boxSet]
        case .collection(let id, _):
            query.parentID = id
        }
        return query
    }

    func details(of id: String) async throws -> ItemDetails {
        let source = try await library.item(id: id)
        guard let item = MediaItem(source) else { throw SerafinError.notFound }
        var details = ItemDetails(item: item, cast: cast(of: source), playable: item)
        details.information = ItemInformation.columns(for: source, card: item.card)
        switch item.card.kind {
        case .series:
            async let seasons = library.seasons(series: id)
            async let similar = library.similar(to: id)
            async let next = library.nextUp(limit: 1, series: id)
            details.seasons = MediaItem.from(try await seasons)
            details.similar = MediaItem.from((try? await similar) ?? [])
            details.playable = MediaItem.from((try? await next) ?? []).first
            if details.playable == nil, let first = details.seasons.first {
                // Nothing is next once a show is watched through, so Play starts it again from the first episode.
                let episodes = (try? await library.episodes(series: id, season: first.id)) ?? []
                details.playable = MediaItem.from(episodes).first
            }
        case .episode:
            if let seriesID = source.seriesID, let seasonID = source.seasonID {
                let episodes = (try? await library.episodes(series: seriesID, season: seasonID)) ?? []
                details.seasonEpisodes = MediaItem.from(episodes).filter { $0.id != id }
            }
        case .movie, .season:
            details.similar = MediaItem.from((try? await library.similar(to: id)) ?? [])
        case .collection:
            break
        }
        return details
    }

    func season(_ id: String, of seriesID: String) async throws -> SeasonContent {
        async let season = library.item(id: id)
        async let episodes = library.episodes(series: seriesID, season: id)
        let item = try await season
        return SeasonContent(
            title: item.name ?? "",
            seriesTitle: item.seriesName ?? "",
            episodes: MediaItem.from(try await episodes)
        )
    }

    func search(_ term: String) async throws -> MediaSearchResults {
        let results = try await library.search(term: term)
        return MediaSearchResults(
            movies: MediaItem.from(results.movies),
            shows: MediaItem.from(results.series),
            episodes: MediaItem.from(results.episodes)
        )
    }

    func setPlayed(_ isPlayed: Bool, for item: MediaItem) async throws {
        if isPlayed {
            try await library.markPlayed(id: item.id)
        } else {
            try await library.markUnplayed(id: item.id)
        }
    }

    func setFavourite(_ isFavourite: Bool, for item: MediaItem) async throws {
        try await library.setFavourite(id: item.id, on: isFavourite)
    }

    func refresh() async {
        await library.clearCache()
    }

    private func cast(of item: BaseItemDto) -> [CastMember] {
        (item.people ?? []).prefix(Self.castLimit).enumerated().compactMap { index, person in
            guard let name = person.name, !name.isEmpty else { return nil }
            let role = person.role.flatMap { $0.isEmpty ? nil : $0 } ?? person.type.flatMap(Self.job)
            return CastMember(id: "\(index)-\(person.id ?? name)", name: name, role: role, source: person)
        }
    }

    /// The name of a crew member's job, for crew without a role of their own.
    private static func job(_ kind: PersonKind) -> String? {
        switch kind {
        case .director:
            String(localized: "Director", bundle: .module, comment: "A crew member's job on a detail screen.")
        case .writer:
            String(localized: "Writer", bundle: .module, comment: "A crew member's job on a detail screen.")
        case .producer:
            String(localized: "Producer", bundle: .module, comment: "A crew member's job on a detail screen.")
        case .composer:
            String(localized: "Composer", bundle: .module, comment: "A crew member's job on a detail screen.")
        default:
            nil
        }
    }
}
