import Foundation
import SwiftUI
import Testing

@testable import SerafinDesign

@Suite struct HeroItemTests {
    private let english = Locale(identifier: "en_US")

    private func episode(progress: Double = 0, isPlayed: Bool = false) -> MediaCard {
        MediaCard(
            id: "episode-identity",
            kind: .episode,
            title: "A Case of Identity",
            year: 1954,
            runtime: .seconds(36 * 60),
            progress: progress,
            isPlayed: isPlayed,
            episode: MediaCard.EpisodeInfo(
                seriesID: "series-sherlock", seriesTitle: "Sherlock Holmes", seasonNumber: 1, episodeNumber: 3)
        )
    }

    private let movie = MediaCard(
        id: "movie-metropolis", kind: .movie, title: "Metropolis", year: 1927, runtime: .seconds(92 * 60),
        rating: "NR")

    private func series(progress: Double = 0) -> MediaCard {
        MediaCard(
            id: "series-sherlock", kind: .series, title: "Sherlock Holmes", year: 1954, rating: "NR",
            progress: progress)
    }

    @Test func anEpisodesLineNamesItsShowCodeAndTitle() {
        let item = HeroItem(card: episode())
        #expect(
            item.metadata(includesSeries: true, locale: english) == "Sherlock Holmes · S1 E3 · A Case of Identity")
        #expect(item.metadata(includesSeries: false, locale: english) == "S1 E3 · A Case of Identity")
        #expect(item.heading == "Sherlock Holmes")
    }

    @Test func aMoviesLineHasYearTimeAndRatingWithoutACommaInTheTime() {
        let item = HeroItem(card: movie)
        #expect(item.metadata(includesSeries: true, locale: english) == "1927 · 1 hr 32 min · NR")
        #expect(item.heading == "Metropolis")
    }

    @Test func aShowsLineHasYearAndRating() {
        #expect(HeroItem(card: series()).metadata(includesSeries: true, locale: english) == "1954 · NR")
    }

    @Test func runningTimesDropTheCommaAndEmptyParts() {
        #expect(MediaCard.compactDurationText(.seconds(92 * 60), locale: english) == "1 hr 32 min")
        #expect(MediaCard.compactDurationText(.seconds(45 * 60), locale: english) == "45 min")
        #expect(MediaCard.compactDurationText(.seconds(120 * 60), locale: english) == "2 hr")
        #expect(MediaCard.compactDurationText(.seconds(150), locale: english) == "3 min")
    }

    @Test func playSaysResumeWithTheTimeLeftForAStartedItem() {
        let item = HeroItem(card: episode(progress: 0.75))
        #expect(item.playTitle(locale: english) == "Resume · 9 min left")
        #expect(item.playActionName(locale: english) == "Resume")
    }

    @Test func playNamesTheEpisodeForAnEpisodeOrAShow() {
        #expect(HeroItem(card: episode()).playTitle(locale: english) == "Play S1 E3")
        // A show plays the episode found for it, the first for a show nobody has started.
        let first = MediaCard(
            id: "episode-scandal", kind: .episode, title: "A Scandal in Bohemia",
            episode: MediaCard.EpisodeInfo(
                seriesID: "series-sherlock", seriesTitle: "Sherlock Holmes", seasonNumber: 1, episodeNumber: 1))
        #expect(HeroItem(card: series(), playable: first).playTitle(locale: english) == "Play S1 E1")
        #expect(HeroItem(card: series()).playTitle(locale: english) == "Play")
        // A show part way through plays the episode found for it, and resumes one in progress.
        #expect(HeroItem(card: series(progress: 0.3), playable: episode()).playTitle(locale: english) == "Play S1 E3")
        #expect(
            HeroItem(card: series(progress: 0.3), playable: episode(progress: 0.75)).playTitle(locale: english)
                == "Resume · 9 min left")
        // Until that episode is known, it just says Play.
        #expect(HeroItem(card: series(progress: 0.3)).playTitle(locale: english) == "Play")
    }

    @Test func playIsPlainForAMovie() {
        #expect(HeroItem(card: movie).playTitle(locale: english) == "Play")
        #expect(HeroItem(card: movie).playActionName(locale: english) == "Play")
    }

    @Test func voiceOverReadsThePageAsOneFeaturedItem() {
        #expect(
            HeroItem(card: episode(progress: 0.75)).accessibilityLabel(locale: english)
                == "Featured: Sherlock Holmes, A Case of Identity, 9 minutes left")
        #expect(
            HeroItem(card: movie).accessibilityLabel(locale: english)
                == "Featured: Metropolis, 1927, 1 hour, 32 minutes")
        #expect(
            HeroItem(card: series(progress: 0.3), playable: episode(progress: 0.75)).accessibilityLabel(locale: english)
                == "Featured: Sherlock Holmes, 1954, 9 minutes left")
    }

    @Test func theHeroIsTallerOnPhonesAndAtAccessibilitySizes() {
        #expect(HomeHeroLayout.heightFraction(isRegularWidth: false) == 0.62)
        #expect(HomeHeroLayout.heightFraction(isRegularWidth: true) == 0.48)
        #expect(HomeHeroLayout.heightFraction(isRegularWidth: false, dynamicTypeSize: .large) == 0.62)
        #expect(HomeHeroLayout.heightFraction(isRegularWidth: false, dynamicTypeSize: .accessibility5) > 0.62)
        #expect(HomeHeroLayout.heightFraction(isRegularWidth: true, dynamicTypeSize: .accessibility1) > 0.48)
    }

    @Test func theButtonsLeaveRoomForThePageDotsOnlyWhenThereAreSeveralPages() {
        #expect(HomeHeroLayout.indicatorReserve(pageCount: 1) == 0)
        #expect(HomeHeroLayout.indicatorReserve(pageCount: 4) > HomeHeroLayout.indicatorReserve(pageCount: 3))
    }

    @MainActor @Test func theHerosZoomSourcesDifferFromTheCardsShowingTheSameItem() {
        #expect(HomeHeroLayout.zoomID(for: "movie-metropolis") != "movie-metropolis")
        #expect(HomeHeroLayout.playZoomID(for: "movie-metropolis") != HeroHeader.playZoomID(for: "movie-metropolis"))
    }

    @Test func theSampleHeroFeaturesAStartedItemThenNextUpWithoutRepeats() {
        let ids = MockLibrary.hero.map(\.id)
        #expect(ids.count == Set(ids).count)
        #expect(MockLibrary.hero.first?.card.isInProgress == true)
        #expect((3...5).contains(MockLibrary.hero.count))
    }

    @Test func aCardWithoutItsWatchedCheckDoesntSayWatched() {
        let watched = MediaCard(
            id: "movie", kind: .movie, title: "Metropolis", year: 1927, runtime: .seconds(92 * 60), isPlayed: true)
        #expect(watched.accessibilityLabel(locale: english).contains("Watched"))
        #expect(!watched.accessibilityLabel(locale: english, includesPlayed: false).contains("Watched"))
    }
}

@Suite struct HeroScrollTests {
    @Test func aPageCountsAsScrolledOnceItMovesAndAtRestOnceBack() {
        #expect(!HomeHeroLayout.isScrolled(offset: 0, wasScrolled: false))
        #expect(!HomeHeroLayout.isScrolled(offset: -40, wasScrolled: false))
        #expect(!HomeHeroLayout.isScrolled(offset: 8, wasScrolled: false))
        #expect(HomeHeroLayout.isScrolled(offset: 9, wasScrolled: false))
        #expect(HomeHeroLayout.isScrolled(offset: 4, wasScrolled: true))
        #expect(!HomeHeroLayout.isScrolled(offset: 2, wasScrolled: true))
    }

    @Test func theForegroundFadesOverTheEightyPointsBeforeTheSafeArea() {
        func opacity(_ top: CGFloat) -> Double {
            HomeHeroLayout.topFadeOpacity(top: top, restingTop: 400, safeAreaTop: 116)
        }
        #expect(opacity(400) == 1)
        #expect(opacity(116 + 80) == 1)
        #expect(opacity(116 + 40) == 0.5)
        #expect(opacity(116) == 0)
        #expect(opacity(20) == 0)
    }

    @Test func aForegroundRestingNearTheTopIsWholeAtRestAndFadesOverTheRoomItHas() {
        // As in a short iPad window: resting 40 points below the safe area, it fades over those 40.
        func nearer(_ top: CGFloat) -> Double {
            HomeHeroLayout.topFadeOpacity(top: top, restingTop: 120, safeAreaTop: 80)
        }
        #expect(nearer(120) == 1)
        #expect(nearer(100) == 0.5)
        #expect(nearer(80) == 0)
        // Resting under the bars, it fades over its first 24 points of travel.
        func under(_ top: CGFloat) -> Double {
            HomeHeroLayout.topFadeOpacity(top: top, restingTop: 50, safeAreaTop: 80)
        }
        #expect(under(50) == 1)
        #expect(under(38) == 0.5)
        #expect(under(26) == 0)
        // Pulled down past rest, it stays whole.
        #expect(under(90) == 1)
    }
}
