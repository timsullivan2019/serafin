import Foundation
import SerafinCore
import SerafinDesign

@testable import SerafinFeatures

/// The samples, except where a test needs something else: a long grid of made-up titles that pages and counts the way
/// the server does, a server that refuses every change, Home saved on the device and a server that can't be reached,
/// or libraries with pictures of their own.
struct TestMediaSource: MediaSource {
    /// Titles every grid lists instead of the samples, or nil for the samples' grids.
    var titles: [String]?
    /// Whether marking played or favourite fails.
    var refusesChanges = false
    /// What Continue Watching and Next Up hold instead of the samples, or nil for the samples.
    var watching: [MediaCard]?
    /// Home as saved on the device.
    var saved: HomeContent?
    /// Why Home fails to load, or nil when it loads the samples.
    var homeFailure: SerafinError?
    /// The libraries that have a picture of their own on the server.
    var covers: Set<String> = []
    private let samples = SampleMediaSource()

    func home() async throws -> HomeContent {
        if let homeFailure { throw homeFailure }
        return try await samples.home()
    }

    func savedHome() async -> HomeContent? { saved }

    func nextToWatch() async throws -> [MediaItem] {
        guard let watching else { return try await samples.nextToWatch() }
        return watching.map { MediaItem(card: $0, source: nil) }
    }

    func playable(ofSeries id: String) async throws -> MediaItem? { try await samples.playable(ofSeries: id) }

    func item(_ id: String) async throws -> MediaItem { try await samples.item(id) }

    func libraries() async throws -> [MediaLibrary] { try await samples.libraries() }

    func cover(of library: MediaLibrary) async -> MediaItem? {
        guard covers.contains(library.id) else { return await samples.cover(of: library) }
        return MediaItem(card: MediaCard(id: library.id, kind: .collection, title: library.name), source: nil)
    }

    func canRefreshMetadata() async -> Bool { false }

    func refreshMetadata(of item: MediaItem) async throws {}

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
    func suggestions() async throws -> [MediaItem] { try await samples.suggestions() }

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
