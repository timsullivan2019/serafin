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

    func libraries() async throws -> [MediaLibrary] {
        MockLibrary.libraries
    }

    func page(of library: MediaLibrary, options: GridOptions, start: Int) async throws -> MediaPage {
        let all = MockLibrary.libraries.first { $0.id == library.id }?.items ?? []
        var items = all.filter { card in
            (!options.unplayedOnly || !card.isPlayed) && (!options.favouritesOnly || card.isFavourite)
                && (options.year == nil || card.year == options.year)
        }
        switch options.sort {
        case .name:
            items.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateAdded:
            // The samples are listed oldest addition first.
            items.reverse()
        case .premiereDate, .rating:
            items.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        }
        if options.ascending != (options.sort == .name) {
            items.reverse()
        }
        return MediaPage(items: items.map(Self.item), nextStart: nil)
    }

    func filters(in library: MediaLibrary) async throws -> LibraryFilters {
        let years = Set(MockLibrary.libraries.first { $0.id == library.id }?.items.compactMap(\.year) ?? [])
        return LibraryFilters(genres: [], years: years.sorted(by: >))
    }

    func details(of id: String) async throws -> ItemDetails {
        let all = MockMedia.movies + MockMedia.series + MockMedia.episodes
        guard let card = all.first(where: { $0.id == id }) else { throw SerafinError.notFound }
        var details = ItemDetails(item: Self.item(card), playable: Self.item(card))
        details.information = ItemInformation.columns(for: Self.sampleFile(of: card), card: card)
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
            episodes: MockMedia.episodes.filter(matches).map(Self.item)
        )
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
