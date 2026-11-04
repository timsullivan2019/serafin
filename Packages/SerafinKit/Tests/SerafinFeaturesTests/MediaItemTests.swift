import Foundation
import JellyfinAPI
import SerafinDesign
import Testing

@testable import SerafinFeatures

@Suite struct MediaItemTests {
    @Test func aMovieBecomesACardWithItsProgress() throws {
        let item = BaseItemDto(
            id: "aaaa1111",
            name: "Nosferatu",
            officialRating: "NR",
            overview: "A real estate agent travels to Transylvania.",
            productionYear: 1922,
            runTimeTicks: 94 * 60 * 10_000_000,
            type: .movie,
            userData: UserItemDataDto(isFavorite: true, isPlayed: false, key: "aaaa1111", playedPercentage: 25)
        )
        let card = try #require(MediaItem(item)).card
        #expect(card.kind == .movie)
        #expect(card.title == "Nosferatu")
        #expect(card.year == 1922)
        #expect(card.runtime == .seconds(94 * 60))
        #expect(card.rating == "NR")
        #expect(card.progress == 0.25)
        #expect(card.isFavourite)
        #expect(!card.isPlayed)
        #expect(card.overview == "A real estate agent travels to Transylvania.")
    }

    @Test func aRunTimeOfZeroIsUnknown() throws {
        let item = BaseItemDto(id: "aaaa1111", name: "Earth", runTimeTicks: 0, type: .movie)
        let card = try #require(MediaItem(item)).card
        #expect(card.runtime == nil)
        #expect(card.runtimeText == nil)
    }

    @Test func progressFallsBackToThePlaybackPosition() throws {
        let item = BaseItemDto(
            id: "bbbb2222",
            name: "Detour",
            runTimeTicks: 1000,
            type: .movie,
            userData: UserItemDataDto(key: "bbbb2222", playbackPositionTicks: 400)
        )
        #expect(try #require(MediaItem(item)).card.progress == 0.4)
    }

    @Test func anEpisodeKnowsItsShowSeasonAndNumber() throws {
        let item = BaseItemDto(
            id: "cccc3333",
            indexNumber: 2,
            name: "The Red-Headed League",
            parentIndexNumber: 1,
            seriesID: "show1111",
            seriesName: "Sherlock Holmes",
            type: .episode
        )
        let episode = try #require(MediaItem(item)?.card.episode)
        #expect(episode.seriesID == "show1111")
        #expect(episode.seriesTitle == "Sherlock Holmes")
        #expect(episode.seasonNumber == 1)
        #expect(episode.episodeNumber == 2)
    }

    @MainActor @Test func aCardOpensItsPageWithWhatTheCardShowed() throws {
        let movie = try #require(
            MediaItem(
                BaseItemDto(
                    id: "aaaa1111", name: "Metropolis", type: .movie,
                    userData: UserItemDataDto(isFavorite: true, key: "aaaa1111"))))
        #expect(movie.route == .card(movie))
        // The page's navigation bar shows the card's marks before the details load.
        let model = ItemDetailModel(id: movie.id, preview: movie)
        #expect(model.details == nil)
        #expect(model.preview?.card.isFavourite == true)
    }

    @Test func anEpisodeOffersItsShowAndNothingElseDoes() throws {
        let episode = BaseItemDto(id: "cccc3333", name: "The Red-Headed League", seriesID: "show1111", type: .episode)
        #expect(try #require(MediaItem(episode)).showRoute == .item(id: "show1111"))
        let movie = BaseItemDto(id: "aaaa1111", name: "Metropolis", type: .movie)
        #expect(try #require(MediaItem(movie)).showRoute == nil)
        // A show ID Jellyfin wouldn't issue opens nothing.
        let odd = BaseItemDto(id: "cccc4444", name: "The Blue Carbuncle", seriesID: "../show", type: .episode)
        #expect(try #require(MediaItem(odd)).showRoute == nil)
    }

    @Test(arguments: [BaseItemKind.audio, .musicAlbum, .book, .photo, .folder])
    func kindsSerafinDoesNotShowAreLeftOut(_ kind: BaseItemKind) {
        #expect(MediaItem(BaseItemDto(id: "dddd4444", name: "Something", type: kind)) == nil)
    }

    @Test func aNewSeasonStandsForItsSeriesAmongWhatsNew() throws {
        let season = BaseItemDto(
            id: "eeee5555", name: "Season 2", seriesID: "ffff6666", seriesName: "Caminandes",
            seriesPrimaryImageTag: "show-poster", type: .season)
        let episode = BaseItemDto(id: "aaaa7777", name: "Pilot", seriesID: "ffff6666", type: .episode)
        let series = BaseItemDto(id: "ffff6666", name: "Caminandes", type: .series)
        let latest = MediaItem.latest([season, episode, series])
        #expect(latest.map(\.id) == ["ffff6666", "aaaa7777"])
        let card = try #require(latest.first).card
        #expect(card.kind == .series)
        #expect(card.title == "Caminandes")
        #expect(latest.first?.source?.imageTags?["Primary"] == "show-poster")
    }

    @Test func aSeasonWithoutItsSeriesPosterStaysASeason() {
        let season = BaseItemDto(id: "eeee5555", name: "Season 2", seriesID: "ffff6666", type: .season)
        #expect(MediaItem.latest([season]).map(\.card.kind) == [.season])
    }

    @Test func itemsFromTheSameServerItemCompareEqualAndHashAlike() throws {
        let server = BaseItemDto(id: "aaaa1111", imageTags: ["Primary": "p1"], name: "Nosferatu", type: .movie)
        let item = try #require(MediaItem(server))
        let copy = item
        let reloaded = try #require(MediaItem(server))
        #expect(copy == item)
        #expect(reloaded == item)
        #expect(reloaded.hashValue == item.hashValue)
        #expect(reloaded.source?.imageTags == ["Primary": "p1"])

        var newPoster = server
        newPoster.imageTags = ["Primary": "p2"]
        #expect(try #require(MediaItem(newPoster)) != item)

        var renamed = item
        renamed.card.title = "Nosferatu the Vampyre"
        #expect(renamed != item)
    }

    @Test func itemsWithoutAnIDAreLeftOut() {
        #expect(MediaItem(BaseItemDto(name: "No ID", type: .movie)) == nil)
    }

    @Test func librariesMapToTheKindsSerafinShows() {
        #expect(MediaLibrary(view: BaseItemDto(collectionType: .movies, id: "m", name: "Movies"))?.kind == .movies)
        #expect(MediaLibrary(view: BaseItemDto(collectionType: .tvshows, id: "t", name: "Shows"))?.kind == .shows)
        #expect(MediaLibrary(view: BaseItemDto(id: "x", name: "Everything"))?.kind == .mixed)
        #expect(MediaLibrary(view: BaseItemDto(collectionType: .music, id: "a", name: "Music")) == nil)
        #expect(MediaLibrary.Kind.mixed.itemTypes == [.movie, .series])
    }
}

@Suite struct PlainTextTests {
    @Test func tagsAreDroppedAndLineBreaksKept() {
        let text = PlainText("<p>A <i>silent</i> classic.<br/>Restored in 4K.</p>").text
        #expect(text == "A silent classic.\nRestored in 4K.")
    }

    @Test func entitiesAreDecodedOnce() {
        #expect(PlainText("Tom &amp; Jerry &quot;meet&quot; &amp;lt;3").text == "Tom & Jerry \"meet\" &lt;3")
    }

    @Test func scriptsNeverSurviveAsMarkup() {
        let text = PlainText("<script>alert('x')</script>Hello").text
        #expect(text?.contains("<") == false)
    }

    @Test func emptyOverviewsBecomeNil() {
        #expect(PlainText("  <br> ").text == nil)
    }
}
