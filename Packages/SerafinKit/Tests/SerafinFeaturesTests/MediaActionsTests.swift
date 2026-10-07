import SerafinCore
import SerafinDesign
import SwiftUI
import Testing

@testable import SerafinFeatures

@MainActor @Suite struct MediaActionsTests {
    private let item = MediaItem(card: MockMedia.movies[0], source: nil)

    @Test func markingPlayedIsConfirmedWithSuccess() async throws {
        let actions = MediaActions()
        await actions.setPlayed(true, for: item, in: SampleMediaSource())
        let confirmation = try #require(actions.confirmation)
        #expect(confirmation.kind == .played)
        #expect(confirmation.feedback == .success)
        #expect(actions.revision == 1)
    }

    @Test func otherChangesAreConfirmedWithATick() async throws {
        let actions = MediaActions()
        await actions.setPlayed(false, for: item, in: SampleMediaSource())
        #expect(actions.confirmation?.kind == .unplayed)
        #expect(actions.confirmation?.feedback == .selection)
        await actions.setFavourite(true, for: item, in: SampleMediaSource())
        #expect(actions.confirmation?.kind == .favourite)
        await actions.setFavourite(false, for: item, in: SampleMediaSource())
        #expect(actions.confirmation?.kind == .notFavourite)
        #expect(actions.confirmation?.feedback == .selection)
    }

    @Test func theSameChangeTwiceIsConfirmedTwice() async {
        let actions = MediaActions()
        await actions.setPlayed(true, for: item, in: SampleMediaSource())
        let first = actions.confirmation
        await actions.setPlayed(true, for: item, in: SampleMediaSource())
        #expect(actions.confirmation != first)
    }

    @Test func playbackReloadsAndFailuresAreNotConfirmed() async {
        let actions = MediaActions()
        actions.reload()
        #expect(actions.confirmation == nil)
        await actions.setPlayed(true, for: item, in: RefusingMediaSource())
        #expect(actions.confirmation == nil)
        #expect(actions.failure != nil)
    }
}

/// The samples, except that the server refuses every change.
private struct RefusingMediaSource: MediaSource {
    private let samples = SampleMediaSource()

    func home() async throws -> HomeContent { try await samples.home() }
    func libraries() async throws -> [MediaLibrary] { try await samples.libraries() }
    func page(of library: MediaLibrary, options: GridOptions, start: Int) async throws -> MediaPage {
        try await samples.page(of: library, options: options, start: start)
    }
    func filters(in library: MediaLibrary) async throws -> LibraryFilters { try await samples.filters(in: library) }
    func details(of id: String) async throws -> ItemDetails { try await samples.details(of: id) }
    func season(_ id: String, of seriesID: String) async throws -> SeasonContent {
        try await samples.season(id, of: seriesID)
    }
    func search(_ term: String) async throws -> MediaSearchResults { try await samples.search(term) }
    func setPlayed(_ isPlayed: Bool, for item: MediaItem) async throws { throw URLError(.badServerResponse) }
    func setFavourite(_ isFavourite: Bool, for item: MediaItem) async throws { throw URLError(.badServerResponse) }
    func refresh() async {}
}
