import Foundation
import Testing

@testable import SerafinDesign

@Suite struct MediaCardDisplayTests {
    private let english = Locale(identifier: "en_US")

    private let episode = MediaCard(
        id: "episode",
        kind: .episode,
        title: "Gran Dillama",
        year: 2013,
        runtime: .seconds(150),
        progress: 0.4,
        episode: MediaCard.EpisodeInfo(
            seriesID: "series",
            seriesTitle: "Caminandes",
            seasonNumber: 1,
            episodeNumber: 2
        )
    )

    private let movie = MediaCard(
        id: "movie",
        kind: .movie,
        title: "Sintel",
        year: 2010,
        runtime: .seconds(99 * 60),
        progress: 0.4
    )

    @Test func episodesShowTheirCodeUnderTheSeriesTitle() {
        #expect(episode.episodeCode == "S1 E2")
        #expect(episode.eyebrowText == "Caminandes · S1 E2")
    }

    @Test func specialsAreNamedRatherThanCalledSeasonZero() throws {
        var special = episode
        special.episode?.seasonNumber = 0
        #expect(special.episodeCode(locale: english) == "Special 2")
        #expect(special.episodeCaption(locale: english) == "Special 2")
        #expect(special.accessibilityLabel(locale: english).contains("Special 2"))
        #expect(!special.accessibilityLabel(locale: english).contains("Season"))
    }

    @Test func anEpisodeOnItsShowsPageSaysItsNumberTitleTimeAndWhetherItsWatched() {
        #expect(episode.episodeCaption(locale: english) == "Episode 2")
        #expect(
            episode.episodeAccessibilityLabel(locale: english) == "Episode 2, Gran Dillama, 40% watched, 2 minutes left"
        )
        var watched = episode
        watched.progress = 0
        watched.isPlayed = true
        watched.isFavourite = true
        #expect(
            watched.episodeAccessibilityLabel(locale: english)
                == "Episode 2, Gran Dillama, 3 minutes, Watched, Favorite")
        #expect(movie.episodeCaption == nil)
    }

    @Test func moviesShowTheirYearInstead() {
        #expect(movie.episodeCode == nil)
        #expect(movie.eyebrowText == "2010")
    }

    @Test func anEpisodesPosterNamesItsSeries() {
        #expect(episode.posterTitle == "Caminandes")
        #expect(episode.posterCaption == "S1 E2")
        #expect(movie.posterTitle == movie.title)
        #expect(movie.posterCaption == "2010")
    }

    @Test func runtimeIsInHoursAndMinutes() {
        #expect(movie.runtimeText(locale: english) == "1 hr, 39 min")
    }

    @Test func remainingTimeRoundsUpToTheNextMinute() {
        var almostDone = movie
        almostDone.runtime = .seconds(10 * 60)
        almostDone.progress = 0.95
        #expect(almostDone.remainingText(locale: english) == "1 min left")
    }

    @Test func remainingTimeOnlyShowsWhileInProgress() {
        var unstarted = movie
        unstarted.progress = 0
        #expect(unstarted.remainingText(locale: english) == nil)
        var played = movie
        played.progress = 0
        played.isPlayed = true
        #expect(played.remainingText(locale: english) == nil)
    }

    @Test func voiceOverDescribesAMovieWithItsProgressAndTimeLeft() {
        #expect(movie.accessibilityLabel(locale: english) == "Sintel, 2010, 40% watched, 1 hour left")
    }

    @Test func voiceOverGivesAnUnstartedMovieItsRunningTime() {
        var unstarted = movie
        unstarted.progress = 0
        #expect(unstarted.accessibilityLabel(locale: english) == "Sintel, 2010, 1 hour, 39 minutes")
    }

    @Test func voiceOverLeavesAShowsRunningTimeOut() {
        let show = MediaCard(id: "show", kind: .series, title: "Caminandes", year: 2013, runtime: .seconds(150))
        #expect(show.accessibilityLabel(locale: english) == "Caminandes, 2013")
    }

    @Test func voiceOverDescribesAWatchedFavouriteEpisode() {
        var card = episode
        card.progress = 0
        card.isPlayed = true
        card.isFavourite = true
        #expect(
            card.accessibilityLabel(locale: english)
                == "Gran Dillama, Caminandes, Season 1, episode 2, 3 minutes, Watched, Favorite"
        )
    }

    @Test func anItemIsWatchedOnlyOncePlayedAndNotStartedAgain() {
        var card = movie
        card.progress = 0
        #expect(!card.isWatched)
        card.isPlayed = true
        #expect(card.isWatched)
        // Watched before and started again: the server keeps it played, but it's in progress.
        card.progress = 0.4
        #expect(!card.isWatched)
        card.isPlayed = false
        #expect(!card.isWatched)
    }

    @Test func voiceOverDescribesAFilmWatchedAgainByItsProgress() {
        var card = movie
        card.isPlayed = true
        #expect(card.accessibilityLabel(locale: english) == "Sintel, 2010, 40% watched, 1 hour left")
    }
}
