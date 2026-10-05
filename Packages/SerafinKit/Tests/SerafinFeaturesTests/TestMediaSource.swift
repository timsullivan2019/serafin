import Foundation
import SerafinCore
import SerafinDesign

@testable import SerafinFeatures

/// The samples, except where a test needs something else: a long grid of made-up titles that pages and counts the way
/// the server does, or a server that refuses every change.
struct TestMediaSource: MediaSource {
    /// Titles every grid lists instead of the samples, or nil for the samples' grids.
    var titles: [String]?
    /// Whether marking played or favourite fails.
    var refusesChanges = false
    private let samples = SampleMediaSource()

    func home() async throws -> HomeContent { try await samples.home() }

    func libraries() async throws -> [MediaLibrary] { try await samples.libraries() }

    func page(of scope: GridScope, options: GridOptions, start: Int, limit: Int) async throws -> MediaPage {
        guard let cards = cards(options) else {
            return try await samples.page(of: scope, options: options, start: start, limit: limit)
        }
        let page = cards.dropFirst(start).prefix(limit).map { MediaItem(card: $0, source: nil) }
        return MediaPage(items: page, total: cards.count)
    }

    func filters(in scope: GridScope) async throws -> LibraryFilters { try await samples.filters(in: scope) }

    func count(in scope: GridScope, options: GridOptions, before name: String) async throws -> Int {
        guard let cards = cards(options) else {
            return try await samples.count(in: scope, options: options, before: name)
        }
        return cards.count { SampleMediaSource.sortName($0.title) < name }
    }

    func genres() async throws -> [Genre] { try await samples.genres() }

    func hasCollections() async throws -> Bool { try await samples.hasCollections() }

    func details(of id: String) async throws -> ItemDetails { try await samples.details(of: id) }

    func season(_ id: String, of seriesID: String) async throws -> SeasonContent {
        try await samples.season(id, of: seriesID)
    }

    func search(_ term: String) async throws -> MediaSearchResults { try await samples.search(term) }

    func setPlayed(_ isPlayed: Bool, for item: MediaItem) async throws {
        if refusesChanges { throw URLError(.badServerResponse) }
    }

    func setFavourite(_ isFavourite: Bool, for item: MediaItem) async throws {
        if refusesChanges { throw URLError(.badServerResponse) }
    }

    func refresh() async {}

    /// The made-up titles as movie cards, sorted by name as `options` asks.
    private func cards(_ options: GridOptions) -> [MediaCard]? {
        guard let titles else { return nil }
        let sorted = titles.sorted { SampleMediaSource.sortName($0) < SampleMediaSource.sortName($1) }
        return (options.ascending ? sorted : sorted.reversed()).map {
            MediaCard(id: "test-\($0)", kind: .movie, title: $0)
        }
    }
}
