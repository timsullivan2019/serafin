import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign

/// The built-in sample titles, so every screen previews without a server.
struct SampleMediaSource: MediaSource {
    func home() async throws -> HomeContent {
        HomeContent(
            continueWatching: MockLibrary.continueWatching.map(Self.item),
            nextUp: MockLibrary.nextUp.map(Self.item),
            latest: MockLibrary.libraries.map { library in
                HomeContent.LatestRow(
                    library: library,
                    items: MockLibrary.latest.filter { library.items.contains($0) }.map(Self.item)
                )
            }
        )
    }

    func savedHome() async -> HomeContent? {
        nil
    }

    func nextToWatch() async throws -> [MediaItem] {
        (MockLibrary.continueWatching + MockLibrary.nextUp).map(Self.item)
    }

    func playable(ofSeries id: String) async throws -> MediaItem? {
        guard let series = MockMedia.series.first(where: { $0.id == id }) else { return nil }
        let episodes = MockMedia.seasons(of: series).flatMap(\.episodes)
        return (episodes.first(where: \.isInProgress) ?? episodes.first { !$0.isPlayed } ?? episodes.first)
            .map(Self.item)
    }

    func item(_ id: String) async throws -> MediaItem {
        let all = MockMedia.movies + MockMedia.series + MockMedia.episodes
        guard let card = all.first(where: { $0.id == id }) else { throw SerafinError.notFound }
        return Self.item(card)
    }

    func libraries() async throws -> [MediaLibrary] {
        MockLibrary.libraries
    }

    func canRefreshMetadata() async -> Bool {
        false
    }

    func refreshMetadata(of item: MediaItem) async throws {}

    func cover(of library: MediaLibrary) async -> MediaItem? {
        nil
    }

    func page(of scope: GridScope, options: GridOptions, start: Int, limit: Int) async throws -> MediaPage {
        let cards = Self.cards(in: scope, options: options)
        let page = cards.dropFirst(start).prefix(limit)
        return MediaPage(items: page.map(Self.item), total: cards.count)
    }

    func filters(in scope: GridScope) async throws -> LibraryFilters {
        guard case .library(let library) = scope else { return LibraryFilters(genres: [], years: []) }
        let years = Set(MockLibrary.libraries.first { $0.id == library.id }?.items.compactMap(\.year) ?? [])
        return LibraryFilters(genres: [], years: years.sorted(by: >))
    }

    func count(in scope: GridScope, options: GridOptions, before name: String) async throws -> Int {
        Self.cards(in: scope, options: options).count { Self.sortName($0.title) < name.lowercased() }
    }

    func genres() async throws -> [Genre] {
        let names = Set(Self.genres.values.flatMap { $0 })
        return names.sorted().map { name in
            Genre(id: "genre-\(name)", name: name, count: Self.genres.values.count { $0.contains(name) })
        }
    }

    func hasCollections() async throws -> Bool {
        !MockMedia.collections.isEmpty
    }

    /// A grid's samples, filtered and sorted.
    private static func cards(in scope: GridScope, options: GridOptions) -> [MediaCard] {
        let all: [MediaCard] =
            switch scope {
            case .library(let library): MockLibrary.libraries.first { $0.id == library.id }?.items ?? []
            case .genre(let genre):
                (MockMedia.movies + MockMedia.series).filter { genres[$0.id]?.contains(genre.name) == true }
            case .collections: MockMedia.collections
            case .collection(let id, _): MockMedia.collections.first { $0.id == id }.map(MockMedia.members) ?? []
            case .shortcut: MockMedia.movies + MockMedia.series
            // The samples don't say who is in what, so a person's page shows a few of the films.
            case .person: Array(MockMedia.movies.prefix(4))
            }
        var cards = all.filter { card in
            (!options.unplayedOnly || !card.isPlayed) && (!options.favouritesOnly || card.isFavourite)
                && (options.year == nil || card.year == options.year)
        }
        switch options.sort {
        case .name:
            cards.sort { sortName($0.title) < sortName($1.title) }
        case .dateAdded:
            // The samples are listed oldest addition first.
            cards.reverse()
        case .premiereDate, .rating:
            cards.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        }
        // Each sort above runs in its natural direction: names A to Z, everything else newest or highest first.
        if options.ascending != (options.sort == .name) {
            cards.reverse()
        }
        return cards
    }

    /// A title as the server sorts it: lowercase, without a leading article.
    static func sortName(_ title: String) -> String {
        let lower = title.lowercased()
        for article in ["the ", "a ", "an "] where lower.hasPrefix(article) {
            return String(lower.dropFirst(article.count))
        }
        return lower
    }

    /// The samples' genres, so browsing by genre has something to show.
    private static let genres: [String: [String]] = [
        "movie-big-buck-bunny": ["Animation", "Comedy"],
        "movie-sintel": ["Animation", "Fantasy"],
        "movie-tears-of-steel": ["Science Fiction"],
        "movie-elephants-dream": ["Animation", "Science Fiction"],
        "movie-cosmos-laundromat": ["Animation", "Fantasy"],
        "movie-spring": ["Animation", "Fantasy"],
        "movie-sprite-fright": ["Animation", "Comedy", "Horror"],
        "movie-night-of-the-living-dead": ["Horror"],
        "movie-the-general": ["Comedy"],
        "movie-nosferatu": ["Horror"],
        "movie-his-girl-friday": ["Comedy"],
        "movie-charade": ["Mystery"],
        "series-caminandes": ["Animation", "Comedy"],
        "series-sherlock-holmes": ["Mystery"],
        "series-alice": ["Fantasy"],
        "series-oz": ["Fantasy"],
    ]

    func details(of id: String) async throws -> ItemDetails {
        let all = MockMedia.movies + MockMedia.series + MockMedia.episodes
        guard let card = all.first(where: { $0.id == id }) else { throw SerafinError.notFound }
        var details = ItemDetails(item: Self.item(card), playable: Self.item(card))
        details.information = ItemInformation.columns(for: Self.sampleFile(of: card), card: card)
        details.badges = MediaBadges.badges(for: Self.sampleFile(of: card))
        if card.kind == .movie || card.kind == .episode {
            let names = ["Opening", "The Middle", "The End"]
            details.chapters = names.enumerated().map { index, name in
                Chapter(index: index, name: name, start: .seconds(index * 180), imageTag: nil)
            }
        }
        switch card.kind {
        case .series:
            let seasons = MockMedia.seasons(of: card)
            details.seasons = seasons.map { Self.item($0.card) }
            let episodes = seasons.flatMap(\.episodes)
            details.playable = (episodes.first { !$0.isPlayed } ?? episodes.first).map(Self.item)
            details.similar = MockMedia.series.filter { $0.id != id }.map(Self.item)
        case .episode:
            let season = MockMedia.series(of: card).flatMap { series in
                MockMedia.seasons(of: series).first { $0.number == card.episode?.seasonNumber }
            }
            details.seasonEpisodes = (season?.episodes ?? []).filter { $0.id != id }.map(Self.item)
        case .movie, .season:
            details.similar = MockMedia.movies.filter { $0.id != id }.map(Self.item)
            details.cast = Self.cast
        case .collection:
            break
        }
        return details
    }

    /// A made-up file for a sample, so previews show every Information column.
    private static func sampleFile(of card: MediaCard) -> BaseItemDto {
        let streams = [
            MediaStream(height: 1080, index: 0, type: .video, videoRangeType: .sdr, width: 1920),
            MediaStream(channelLayout: "stereo", codec: "aac", index: 1, language: "eng", type: .audio),
            MediaStream(codec: "subrip", index: 2, language: "eng", type: .subtitle),
        ]
        return BaseItemDto(
            genres: card.kind == .movie ? ["Drama"] : ["Animation"],
            mediaSources: card.kind == .series ? nil : [MediaSourceInfo(mediaStreams: streams)],
            officialRating: card.rating
        )
    }

    func season(_ id: String, of seriesID: String) async throws -> SeasonContent {
        guard
            let series = MockMedia.series.first(where: { $0.id == seriesID }),
            let season = MockMedia.seasons(of: series).first(where: { $0.id == id })
        else { throw SerafinError.notFound }
        return SeasonContent(title: season.title, seriesTitle: series.title, episodes: season.episodes.map(Self.item))
    }

    func search(_ term: String) async throws -> MediaSearchResults {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return MediaSearchResults() }
        func matches(_ card: MediaCard) -> Bool { card.title.localizedStandardContains(term) }
        return MediaSearchResults(
            movies: MockMedia.movies.filter(matches).map(Self.item),
            shows: MockMedia.series.filter(matches).map(Self.item),
            episodes: MockMedia.episodes.filter(matches).map(Self.item),
            people: Self.cast.filter { $0.name.localizedStandardContains(term) }.map {
                CastMember(id: $0.id, name: $0.name, role: nil, source: nil)
            },
            collections: MockMedia.collections.filter(matches).map(Self.item)
        )
    }

    func suggestions() async throws -> [MediaItem] {
        (MockMedia.movies + MockMedia.series).filter { !$0.isPlayed }.prefix(6).map(Self.item)
    }

    func setPlayed(_ isPlayed: Bool, for item: MediaItem) async throws {}

    func setFavourite(_ isFavourite: Bool, for item: MediaItem) async throws {}

    func refresh() async {}

    /// The sample show a sample season belongs to.
    static func seriesID(ofSeason id: String) -> String? {
        MockMedia.series.first { series in MockMedia.seasons(of: series).contains { $0.id == id } }?.id
    }

    private static func item(_ card: MediaCard) -> MediaItem {
        MediaItem(card: card, source: nil)
    }

    /// A sample cast, from the public-domain silent era.
    private static let cast = [
        CastMember(id: "keaton", name: "Buster Keaton", role: "Johnnie Gray", source: nil),
        CastMember(id: "mack", name: "Marion Mack", role: "Annabelle Lee", source: nil),
        CastMember(id: "bruckman", name: "Clyde Bruckman", role: "Director", source: nil),
        CastMember(id: "cavender", name: "Glen Cavender", role: "Captain Anderson", source: nil),
        CastMember(id: "farley", name: "Jim Farley", role: "Captain Thatcher", source: nil),
    ]
}
