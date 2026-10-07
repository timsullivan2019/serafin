import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

/// A date a whole number of days after a fixed day, for ordering.
private func day(_ number: Double) -> Date {
    Date(timeIntervalSince1970: 1_790_000_000 + number * 86_400)
}

/// An item as the server would send it, with when it was last played or added.
private func item(
    _ id: String,
    kind: MediaCard.Kind = .movie,
    progress: Double = 0,
    played: Date? = nil,
    added: Date? = nil,
    seriesID: String? = nil
) -> MediaItem {
    var source = BaseItemDto(id: id, name: id)
    source.userData = UserItemDataDto(key: id, lastPlayedDate: played)
    source.dateCreated = added
    let episode = seriesID.map {
        MediaCard.EpisodeInfo(seriesID: $0, seriesTitle: "Show", seasonNumber: 1, episodeNumber: 1)
    }
    let card = MediaCard(id: id, kind: kind, title: id, progress: progress, episode: episode)
    return MediaItem(card: card, source: source)
}

private func row(_ items: [MediaItem], kind: MediaLibrary.Kind = .movies) -> HomeContent.LatestRow {
    HomeContent.LatestRow(
        library: MediaLibrary(id: "library-\(kind)", name: "\(kind)", kind: kind, items: []), items: items)
}

private func pick(_ home: HomeContent, without: Set<String> = []) -> [String] {
    HomeHeroModel.candidates(from: home) { !without.contains($0.id) }.map(\.id)
}

@Suite struct HomeHeroPickingTests {
    @Test func theMostRecentlyPlayedStartedItemComesFirst() {
        let home = HomeContent(
            continueWatching: [
                item("older", progress: 0.5, played: day(1)),
                item("newest", progress: 0.5, played: day(3)),
                item("undated", progress: 0.5),
            ],
            nextUp: [],
            latest: []
        )
        #expect(pick(home) == ["newest"])
    }

    @Test func withoutDatesTheFirstStartedItemComesFirst() {
        let home = HomeContent(
            continueWatching: [item("first", progress: 0.2), item("second", progress: 0.4)], nextUp: [], latest: [])
        #expect(pick(home) == ["first"])
    }

    @Test func thenTheFirstNextUpEpisodeThenTheNewestAdditionsAcrossLibraries() {
        let home = HomeContent(
            continueWatching: [item("started", progress: 0.5, played: day(5))],
            nextUp: [
                item("next-a", kind: .episode, seriesID: "show-a"), item("next-b", kind: .episode, seriesID: "show-b"),
            ],
            latest: [
                row([item("movie-old", added: day(1)), item("movie-new", added: day(4))]),
                row([item("show-new", kind: .series, added: day(3))], kind: .shows),
            ]
        )
        #expect(pick(home) == ["started", "next-a", "movie-new", "show-new", "movie-old"])
    }

    @Test func aShowRanksByWhenItsNewestEpisodeArrivedNotWhenTheShowWasAdded() {
        var show = item("show", kind: .series, added: day(1))
        show.source?.dateLastMediaAdded = day(9)
        let home = HomeContent(
            continueWatching: [], nextUp: [],
            latest: [row([item("movie", added: day(5))]), row([show], kind: .shows)]
        )
        #expect(pick(home) == ["show", "movie"])
    }

    @Test func atMostFiveAreFeatured() {
        let home = HomeContent(
            continueWatching: [], nextUp: [],
            latest: [row((1...9).map { item("movie-\($0)", added: day(Double($0))) })]
        )
        #expect(pick(home) == ["movie-9", "movie-8", "movie-7", "movie-6", "movie-5"])
    }

    @Test func aBrandNewServerFeaturesItsNewestAdditionsTakingTurnsWhenUndated() {
        let home = HomeContent(
            continueWatching: [], nextUp: [],
            latest: [
                row([item("movie-1"), item("movie-2"), item("movie-3")]),
                row([item("show-1", kind: .series), item("show-2", kind: .series)], kind: .shows),
            ]
        )
        #expect(pick(home) == ["movie-1", "show-1", "movie-2", "show-2", "movie-3"])
    }

    @Test func nothingIsFeaturedTwiceAndAShowIsntFeaturedBesideItsEpisode() {
        let home = HomeContent(
            continueWatching: [item("episode", kind: .episode, progress: 0.5, seriesID: "show")],
            nextUp: [item("episode", kind: .episode, seriesID: "show")],
            latest: [
                row([item("show", kind: .series), item("episode", kind: .episode, seriesID: "show")], kind: .shows)
            ]
        )
        #expect(pick(home) == ["episode"])
    }

    @Test func itemsWithoutArtworkSeasonsAndCollectionsAreSkipped() {
        let home = HomeContent(
            continueWatching: [item("bare", progress: 0.5), item("pictured", progress: 0.5)],
            nextUp: [],
            latest: [row([item("season", kind: .season), item("collection", kind: .collection), item("movie")])]
        )
        #expect(pick(home, without: ["bare"]) == ["pictured", "movie"])
    }

    @Test func finishedOrUnstartedItemsInContinueWatchingArentTreatedAsStarted() {
        let home = HomeContent(
            continueWatching: [item("finished", progress: 1, played: day(9)), item("started", progress: 0.3)],
            nextUp: [], latest: [])
        #expect(pick(home) == ["started"])
    }
}

@MainActor
@Suite struct HomeHeroModelTests {
    @Test func theSamplesGiveAStartedItemNextUpAndNewAdditions() async throws {
        let model = HomeHeroModel()
        model.update(from: try await SampleMediaSource().home()) { _ in true }
        #expect(model.entries.first?.item.card.isInProgress == true)
        #expect(model.entries.count == HomeHeroModel.limit)
        #expect(Set(model.entries.map(\.id)).count == model.entries.count)
    }

    @Test func eachFeaturedShowFindsTheEpisodeItsPlayButtonStarts() async throws {
        let model = HomeHeroModel()
        let show = try #require(MockMedia.series.first { $0.id == "series-caminandes" })
        let home = HomeContent(
            continueWatching: [], nextUp: [],
            latest: [row([MediaItem(card: show, source: nil)], kind: .shows)]
        )
        model.update(from: home) { _ in true }
        await model.refreshShows(from: SampleMediaSource())
        let entry = try #require(model.entry(show.id))
        #expect(entry.playable?.card.kind == .episode)
        #expect(entry.hero.playable?.episode?.seriesID == show.id)
    }

    @Test func updatingKeepsTheShowsEpisodeAndThePageShowingWhileItsStillFeatured() async throws {
        let model = HomeHeroModel()
        let home = try await SampleMediaSource().home()
        model.update(from: home) { _ in true }
        await model.refreshShows(from: SampleMediaSource())
        let found = model.entries.compactMap(\.playable).count
        let second = model.entries[1].id
        model.selection = second
        model.update(from: home) { _ in true }
        #expect(model.entries.compactMap(\.playable).count == found)
        #expect(model.selection == second)

        // When the page showing is no longer featured, the first page shows.
        model.update(from: HomeContent(continueWatching: [], nextUp: [], latest: [row(Array(home.latest[0].items))])) {
            _ in true
        }
        #expect(model.selection == model.entries.first?.id)
    }

    @Test func aShowStandingInForANewSeasonGetsItsDetailsWhenLookedUp() async throws {
        let model = HomeHeroModel()
        let show = try #require(MockMedia.series.first { $0.id == "series-caminandes" })
        let bare = MediaCard(id: show.id, kind: .series, title: show.title)
        model.update(
            from: HomeContent(continueWatching: [], nextUp: [], latest: [row([MediaItem(card: bare, source: nil)])])
        ) { _ in true }
        #expect(model.entries.first?.item.card.overview == nil)
        await model.refreshShows(from: SampleMediaSource())
        #expect(model.entries.first?.item.card.overview == show.overview)
    }
}

@Suite struct HomeRowsTests {
    @Test func latestInMoviesComesBeforeLatestInShows() {
        let views = [
            BaseItemDto(collectionType: .tvshows, id: "shows", name: "Shows"),
            BaseItemDto(collectionType: .movies, id: "movies", name: "Movies"),
            BaseItemDto(id: "mixed", name: "Home Videos"),
        ]
        let snapshot = HomeSnapshot(date: day(0), libraries: views, resume: [], nextUp: [], latest: [:])
        #expect(HomeContent(snapshot).latest.map(\.library.id) == ["movies", "shows", "mixed"])
    }

    @Test func aShowStandingInForItsNewSeasonKeepsTheShowsArtworkAndDate() throws {
        var season = BaseItemDto(id: "season", name: "Season 1", type: .season)
        season.seriesID = "show"
        season.seriesName = "Sherlock Holmes"
        season.seriesPrimaryImageTag = "poster"
        season.parentBackdropItemID = "show"
        season.parentBackdropImageTags = ["backdrop"]
        season.parentLogoItemID = "show"
        season.parentLogoImageTag = "logo"
        season.dateCreated = day(2)
        let show = try #require(MediaItem.series(of: season))
        #expect(show.id == "show")
        #expect(show.type == .series)
        #expect(show.parentBackdropImageTags == ["backdrop"])
        #expect(show.parentLogoImageTag == "logo")
        #expect(show.dateCreated == day(2))
        #expect(show.dateLastMediaAdded == day(2))
    }
}

@MainActor
@Suite struct WatchListTests {
    @Test func continueWatchingAndNextUpListTheirItems() async {
        let watching = WatchListModel(list: .continueWatching)
        await watching.load(from: SampleMediaSource())
        guard case .loaded(let started) = watching.phase else {
            Issue.record("Continue Watching didn't load")
            return
        }
        #expect(started.map(\.card) == MockLibrary.continueWatching)

        let next = WatchListModel(list: .nextUp)
        await next.load(from: SampleMediaSource())
        guard case .loaded(let episodes) = next.phase else {
            Issue.record("Next Up didn't load")
            return
        }
        #expect(episodes.map(\.card) == MockLibrary.nextUp)
    }
}

@MainActor
@Suite struct HomeHeroPageTests {
    @Test func theBackdropIsAskedForWideEnoughToFillATallPage() {
        #expect(HomeHeroPage.backdropWidth(for: .zero) == 0)
        #expect(HomeHeroPage.backdropWidth(for: CGSize(width: 402, height: 542)) > 402 * 2)
        #expect(HomeHeroPage.backdropWidth(for: CGSize(width: 1200, height: 400)) == 1200)
    }
}

@MainActor
@Suite struct FeaturedDetailTests {
    @Test func aFeaturedItemsScreenShowsTheItemAtOnce() throws {
        let show = try #require(MockMedia.series.first)
        let episode = try #require(MockMedia.episodes.first { $0.episode?.seriesID == show.id })
        let model = ItemDetailModel(
            showing: MediaItem(card: show, source: nil), playable: MediaItem(card: episode, source: nil))
        let details = try #require(model.details)
        #expect(details.item.id == show.id)
        #expect(details.playable?.id == episode.id)
        #expect(model.id == show.id)
    }

    @Test func itsFullDetailsReplaceItOnceLoaded() async throws {
        let movie = MockMedia.movies[1]
        let model = ItemDetailModel(showing: MediaItem(card: movie, source: nil), playable: nil)
        #expect(model.details?.similar.isEmpty == true)
        await model.load(from: SampleMediaSource())
        #expect(model.details?.similar.isEmpty == false)
    }
}
