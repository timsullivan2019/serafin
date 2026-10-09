import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

/// A season as the menu lists it, with art of its own as given.
private func season(_ number: Int?, backdrop: Bool = false, poster: Bool = false) -> ShowSeason {
    let id = "season-\(number.map(String.init) ?? "none")"
    return ShowSeason(
        item: MediaItem(card: MediaCard(id: id, kind: .season, title: id), source: nil),
        number: number,
        episodeCount: 6,
        hasBackdrop: backdrop,
        hasPoster: poster
    )
}

/// The hero on an iPhone 17.
private let phoneHero = ItemDetailModel.HeroGeometry(size: CGSize(width: 402, height: 490), scale: 3, isCompact: true)

@Suite struct ShowSeasonTests {
    @Test func specialsComeAfterTheNumberedSeasons() {
        // The server lists Specials first.
        let ordered = ShowSeason.ordered([season(0), season(1), season(2), season(nil)])
        #expect(ordered.map(\.number) == [1, 2, nil, 0])
    }

    @Test func theHeroShowsASeasonsBackdropOrOnAPhoneItsPoster() {
        #expect(season(1, backdrop: true, poster: true).heroRole(isCompact: true) == .backdrop)
        #expect(season(1, backdrop: true).heroRole(isCompact: false) == .backdrop)
        #expect(season(2, poster: true).heroRole(isCompact: true) == .poster)
        // On a wider screen a poster would be cropped to a sliver, so the show's art stays.
        #expect(season(2, poster: true).heroRole(isCompact: false) == nil)
        #expect(season(3).heroRole(isCompact: true) == nil)
    }

    @Test func aSeasonFromTheServerKnowsItsArtAndEpisodeCount() throws {
        let full = BaseItemDto(
            backdropImageTags: ["b1"], childCount: 10, id: "a1b2c3", imageTags: ["Primary": "p1"], indexNumber: 2,
            name: "Season 2", type: .season)
        let season = try #require(ShowSeason(full))
        #expect(season.number == 2)
        #expect(season.title == "Season 2")
        #expect(season.episodeCount == 10)
        #expect(season.hasBackdrop)
        #expect(season.hasPoster)
        #expect(season.menuEntry.detail?.contains("10") == true)

        // A season with only its show's art says so, as the server lists the show's backdrop separately.
        let bare = try #require(
            ShowSeason(
                BaseItemDto(
                    id: "d4e5f6", indexNumber: 0, name: "Specials", parentBackdropImageTags: ["show"], type: .season)))
        #expect(bare.isSpecials)
        #expect(!bare.hasBackdrop)
        #expect(!bare.hasPoster)
        #expect(bare.menuEntry.detail == nil)
    }
}

@MainActor @Suite struct ShowPageTests {
    @Test func playStartsASeasonsFirstEpisodeNotYetWatched() {
        let episodes = MockMedia.seasons(of: MockMedia.series[1])[0].episodes.map { MediaItem(card: $0, source: nil) }
        // The first three are watched and the fourth is part way through, which Play resumes.
        #expect(ItemDetailModel.firstToWatch(in: episodes)?.id == "series-sherlock-holmes-s1e4")
        let allWatched = episodes.map { episode in
            var watched = episode
            watched.card.progress = 0
            watched.card.isPlayed = true
            return watched
        }
        #expect(ItemDetailModel.firstToWatch(in: allWatched)?.id == "series-sherlock-holmes-s1e1")
        #expect(ItemDetailModel.firstToWatch(in: []) == nil)
    }

    @Test func aShowsPageOpensOnTheSeasonOfItsNextEpisode() async throws {
        let model = ItemDetailModel(id: "series-sherlock-holmes")
        await model.load(from: SampleMediaSource())
        let details = try #require(model.details)
        #expect(details.seasons.map(\.title) == ["The Adventures", "The Memoirs", "Specials"])
        #expect(details.seasons.map(\.episodeCount) == [6, 4, 2])
        #expect(model.selectedSeasonID == "series-sherlock-holmes-s1")
        #expect(model.episodes["series-sherlock-holmes-s1"]?.count == 6)
        // Play resumes the episode part way through, with its badges, and the row starts at it.
        #expect(model.playable?.id == "series-sherlock-holmes-s1e4")
        #expect(model.playable?.card.isInProgress == true)
        #expect(!model.badges.isEmpty)
        #expect(model.startingEpisode(in: "series-sherlock-holmes-s1") == "series-sherlock-holmes-s1e4")
        // The hero shows the show itself until a season is picked.
        #expect(model.heroSeasonID == nil)
        #expect(model.seasonArtwork == nil)
    }

    @Test func pickingASeasonListsItsEpisodesAndTheHeroFollows() async throws {
        let media = SampleMediaSource()
        let model = ItemDetailModel(id: "series-oz")
        await model.load(from: media)
        #expect(model.details?.seasons.count == 16)
        #expect(model.selectedSeasonID == "series-oz-s1")

        let change = model.selectSeason("series-oz-s7", from: media, artwork: nil, hero: phoneHero)
        // The season lists at once; the hero follows once its episodes and picture are ready.
        #expect(model.selectedSeasonID == "series-oz-s7")
        await change?.value
        #expect(model.heroSeasonID == "series-oz-s7")
        #expect(model.playable?.id == "series-oz-s7e1")
        #expect(model.episodes["series-oz-s7"]?.count == 5)
        // Season 7 has a backdrop of its own; season 8 only a poster, which fills a phone's hero.
        #expect(model.seasonArtwork?.seasonID == "series-oz-s7")
        #expect(model.seasonArtwork?.isPoster == false)
        await model.selectSeason("series-oz-s8", from: media, artwork: nil, hero: phoneHero)?.value
        #expect(model.seasonArtwork?.isPoster == true)
        #expect(model.tint == model.seasonArtwork?.tint)

        // Widened to an iPad's regular width, the poster gives way to the show's art.
        var regular = phoneHero
        regular.isCompact = false
        await model.heroChanged(to: regular, artwork: nil)?.value
        #expect(model.seasonArtwork == nil)
        #expect(model.heroSeasonID == "series-oz-s8")

        // Picking the season already listed does nothing.
        #expect(model.selectSeason("series-oz-s8", from: media, artwork: nil, hero: phoneHero) == nil)
    }

    @Test func aReloadKeepsThePickedSeasonAndItsEpisodes() async {
        let media = SampleMediaSource()
        let model = ItemDetailModel(id: "series-oz")
        await model.load(from: media)
        await model.selectSeason("series-oz-s3", from: media, artwork: nil, hero: phoneHero)?.value
        await model.load(from: media)
        #expect(model.selectedSeasonID == "series-oz-s3")
        #expect(model.heroSeasonID == "series-oz-s3")
        #expect(model.episodes["series-oz-s3"] != nil)
        #expect(model.episodes["series-oz-s1"] != nil)
    }

    @Test func aLinkToASeasonOpensTheShowOnIt() async {
        let model = ItemDetailModel(id: "series-oz", seasonID: "series-oz-s12")
        await model.load(from: SampleMediaSource())
        #expect(model.selectedSeasonID == "series-oz-s12")
        #expect(model.episodes["series-oz-s12"]?.isEmpty == false)
        // The hero stays on the show until a season is picked.
        #expect(model.heroSeasonID == nil)
        #expect(model.playable?.id == "series-oz-s1e1")
    }

    @Test func aSeasonThatFailsToLoadCanBeTriedAgain() async {
        let failing = TestMediaSource(failingSeasons: ["series-oz-s2"])
        let model = ItemDetailModel(id: "series-oz")
        await model.load(from: failing)
        await model.selectSeason("series-oz-s2", from: failing, artwork: nil, hero: phoneHero)?.value
        #expect(model.failedSeasons.contains("series-oz-s2"))
        // Without the season's episodes the hero doesn't follow, since Play couldn't either.
        #expect(model.heroSeasonID == nil)

        await model.followSelectedSeason(from: SampleMediaSource(), artwork: nil, hero: phoneHero)?.value
        #expect(model.failedSeasons.isEmpty)
        #expect(model.heroSeasonID == "series-oz-s2")
    }

    @Test func playOnAShowWithSpecialsStartsTheFirstSeasonNotTheSpecials() async throws {
        let media = SampleMediaSource()
        #expect(try await media.playable(ofSeries: "series-oz")?.id == "series-oz-s1e1")
        // Every numbered episode of Sherlock Holmes before the fourth is watched; a played special doesn't count.
        #expect(try await media.playable(ofSeries: "series-sherlock-holmes")?.id == "series-sherlock-holmes-s1e4")
    }

    @Test func aSeasonCardOpensItsShowOnThatSeason() {
        let season = MediaItem(card: MockMedia.seasons(of: MockMedia.series[3])[4].card, source: nil)
        #expect(season.route == .season(id: "series-oz-s5", seriesID: "series-oz"))
    }
}
