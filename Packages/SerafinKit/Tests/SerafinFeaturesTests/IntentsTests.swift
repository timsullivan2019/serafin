import CoreSpotlight
import Foundation
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

@MainActor
@Suite struct AppRequestsTests {
    @Test func aRequestWaitsUntilTheTabsTakeIt() {
        let requests = AppRequests()
        requests.send(.play(itemID: "movie-sintel"))
        #expect(requests.pending == .play(itemID: "movie-sintel"))
        #expect(requests.take() == .play(itemID: "movie-sintel"))
        #expect(requests.pending == nil)
        #expect(requests.take() == nil)
    }

    @Test func aNewerRequestReplacesOneNotYetTaken() {
        let requests = AppRequests()
        requests.send(.show(itemID: "movie-sintel"))
        requests.send(.search("The Kid"))
        #expect(requests.take() == .search("The Kid"))
    }

    @Test(arguments: ["../../System/Info", "a/b", "id?x=1", ""])
    func anItemIDJellyfinWouldNotIssueIsDropped(id: String) {
        let requests = AppRequests()
        requests.send(.show(itemID: id))
        requests.send(.play(itemID: id))
        #expect(requests.pending == nil)
    }
}

@Suite struct IntentLibraryTests {
    private func library(_ media: any MediaSource = SampleMediaSource()) -> IntentLibrary {
        IntentLibrary(media: media) { _ in nil }
    }

    private func items(_ titles: [String]) -> [MediaItem] {
        titles.map { MediaItem(card: MediaCard(id: $0, kind: .movie, title: $0), source: nil) }
    }

    @Test func continueWatchingPlaysWhatWasStartedMostRecently() async throws {
        let media = TestMediaSource(watching: [MockMedia.movies[1], MockMedia.episodes[0]])
        #expect(try await library(media).continueWatching().id == MockMedia.movies[1].id)
    }

    @Test func continueWatchingPassesOverWhatCannotPlayStraightAway() async throws {
        let media = TestMediaSource(watching: [MockMedia.series[0], MockMedia.episodes[0]])
        #expect(try await library(media).continueWatching().id == MockMedia.episodes[0].id)
    }

    @Test func withNothingStartedContinueWatchingSaysSo() async {
        await #expect(throws: IntentError.nothingToContinue) {
            try await library(TestMediaSource(watching: [])).continueWatching()
        }
    }

    @Test func exactTitlesComeFirstThenTitlesStartingWithTheWords() {
        let ranked = IntentLibrary.ranked(
            items(["Billy the Kid", "The Kid Brother", "Kid Auto Races", "The Kid"]), for: "KID")
        #expect(ranked.map(\.card.title) == ["The Kid", "The Kid Brother", "Kid Auto Races", "Billy the Kid"])
    }

    @Test func accentsAndArticlesDoNotCount() {
        let ranked = IntentLibrary.ranked(items(["Metropolis Revisited", "Métropolis"]), for: "the metropolis")
        #expect(ranked.first?.card.title == "Métropolis")
    }

    @Test func aSpokenTitleFindsItsMovie() async throws {
        let entities = try await library().entities(matching: "Sintel")
        let sintel = try #require(entities.first)
        #expect(sintel.id == "movie-sintel")
        #expect(sintel.caption == "Movie · 2010")
    }

    @Test func suggestionsAreContinueWatchingThenNextUp() async throws {
        let entities = try await library().suggestions()
        let expected = (MockLibrary.continueWatching + MockLibrary.nextUp).prefix(IntentLibrary.suggestionLimit)
        #expect(entities.map(\.id) == expected.map(\.id))
    }

    @Test func savedTitlesThatHaveLeftTheServerAreLeftOut() async throws {
        let entities = try await library().entities(for: ["movie-spring", "movie-gone", "series-oz"])
        #expect(entities.map(\.id) == ["movie-spring", "series-oz"])
    }

    @Test func titlesComeWithTheirPosters() async throws {
        let poster = Data([1, 2, 3])
        let library = IntentLibrary(media: SampleMediaSource()) { item in item.id == "movie-sintel" ? poster : nil }
        let entities = try await library.entities(matching: "Sintel")
        #expect(entities.first?.poster == poster)
    }

    @Test func aFailureReadsTheWayTheAppSaysIt() {
        #expect(
            IntentError(SerafinError.serverUnreachable)
                == .failed(
                    "Can't Reach the Server. Check that the server is running and that you're connected to the internet."
                )
        )
        #expect(IntentError(IntentError.locked) == .locked)
    }
}

@Suite struct MediaEntityTests {
    @Test func captionsSayWhatKindOfTitleItIs() throws {
        let sintel = try #require(MockMedia.movies.first { $0.id == "movie-sintel" })
        let caminandes = try #require(MockMedia.series.first { $0.id == "series-caminandes" })
        let episode = try #require(MockMedia.episodes.first)
        #expect(MediaEntity.caption(for: sintel) == "Movie · 2010")
        #expect(MediaEntity.caption(for: caminandes) == "Show · 2013")
        #expect(MediaEntity.caption(for: episode) == episode.eyebrowText)
        #expect(MediaEntity.caption(for: MediaCard(id: "untitled", kind: .movie, title: "Untitled")) == "Movie")
    }

    @Test func spotlightShowsTheTitleCaptionAndPoster() throws {
        let sintel = try #require(MockMedia.movies.first { $0.id == "movie-sintel" })
        let attributes = MediaEntity(MediaItem(card: sintel, source: nil), poster: Data([1])).attributeSet
        #expect(attributes.title == "Sintel")
        #expect(attributes.displayName == "Sintel")
        #expect(attributes.contentDescription == "Movie · 2010")
        #expect(attributes.thumbnailData == Data([1]))
    }
}

@Suite struct TabPathsTests {
    @Test func aTitleOpensOnTheTabShowing() {
        var paths = TabPaths()
        paths.library = [.genres]
        #expect(paths.show("movie-sintel", from: .library) == .library)
        #expect(paths.library == [.genres, .item(id: "movie-sintel")])
        #expect(paths.home.isEmpty)
    }

    @Test func fromSettingsATitleOpensOnHome() {
        var paths = TabPaths()
        #expect(paths.show("movie-sintel", from: .settings) == .home)
        #expect(paths.home == [.item(id: "movie-sintel")])
        #expect(paths.settings.isEmpty)
    }

    @Test func theTitleShowingIsNotOpenedTwice() {
        var paths = TabPaths()
        _ = paths.show("movie-sintel", from: .home)
        _ = paths.show("movie-sintel", from: .home)
        #expect(paths.home == [.item(id: "movie-sintel")])
    }
}
