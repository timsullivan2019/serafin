import Testing

@testable import SerafinDesign

@Suite struct MockMediaTests {
    private var everything: [MediaCard] { MockMedia.movies + MockMedia.series + MockMedia.episodes }

    @Test func hasTwelveMoviesAndFourSeries() {
        #expect(MockMedia.movies.count == 12)
        #expect(MockMedia.movies.allSatisfy { $0.kind == .movie })
        #expect(MockMedia.series.count == 4)
        #expect(MockMedia.series.allSatisfy { $0.kind == .series })
    }

    @Test func identifiersAreUniqueAcrossAllItemsAndSeasons() {
        let cardIDs = everything.map(\.id)
        let seasonIDs = MockMedia.series.flatMap { MockMedia.seasons(of: $0) }.map(\.id)
        let ids = cardIDs + seasonIDs
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyCardHasATitleYearRuntimeAndOverviewWhereItShould() {
        for card in everything {
            #expect(!card.title.isEmpty)
            #expect(card.year != nil, "\(card.id) has no year")
            #expect(card.runtime != nil, "\(card.id) has no runtime")
        }
        for card in MockMedia.movies + MockMedia.series {
            #expect(card.overview?.isEmpty == false, "\(card.id) has no overview")
        }
    }

    @Test func playbackStateIsConsistent() {
        for card in everything {
            #expect((0...1).contains(card.progress))
            if card.isPlayed {
                #expect(card.progress == 0, "\(card.id) is played but has progress")
            }
        }
        #expect(everything.contains { $0.isPlayed })
        #expect(everything.contains { $0.isInProgress })
        #expect(everything.contains { $0.isFavourite })
    }

    @Test(arguments: MockMedia.series)
    func episodesPointBackToTheirSeriesAndSeason(series: MediaCard) throws {
        let seasons = MockMedia.seasons(of: series)
        try #require(!seasons.isEmpty)
        // Numbered seasons count up from 1, and Specials, season 0, come after them.
        let numbered = seasons.prefix { $0.number > 0 }
        #expect(numbered.map(\.number) == Array(1...numbered.count))
        #expect(seasons.dropFirst(numbered.count).allSatisfy { $0.number == 0 && $0.title == "Specials" })
        for season in seasons {
            #expect(season.seriesID == series.id)
            #expect(!season.episodes.isEmpty)
            for (episodeIndex, episode) in season.episodes.enumerated() {
                let info = try #require(episode.episode)
                #expect(episode.kind == .episode)
                #expect(info.seriesID == series.id)
                #expect(info.seriesTitle == series.title)
                #expect(info.seasonNumber == season.number)
                #expect(info.episodeNumber == episodeIndex + 1)
                #expect(MockMedia.series(of: episode) == series)
            }
        }
    }

    @Test func onlyEpisodesCarrySeriesDetails() {
        #expect((MockMedia.movies + MockMedia.series).allSatisfy { $0.episode == nil })
        #expect(MockMedia.episodes.allSatisfy { $0.episode != nil })
    }

    @Test func theSeriesCoverOneSeasonSixteenAndSpecials() {
        #expect(MockMedia.seasons(of: MockMedia.series[0]).count == 1)
        #expect(MockMedia.seasons(of: MockMedia.series[3]).count == 16)
        #expect(MockMedia.seasons(of: MockMedia.series[1]).last?.number == 0)
        // Some episodes have a synopsis for the episode cards, and some don't.
        #expect(MockMedia.episodes.contains { $0.overview != nil })
        #expect(MockMedia.episodes.contains { $0.overview == nil })
    }

    @Test func seasonsOfSomethingThatIsNotASeriesAreEmpty() {
        #expect(MockMedia.seasons(of: MockMedia.movies[0]).isEmpty)
    }

    @Test func stableSeedDoesNotChangeBetweenLaunches() {
        // FNV-1a of "a", fixed, so artwork for an item never changes between runs.
        #expect(MockMedia.stableSeed(for: "a") == Int(truncatingIfNeeded: 0xAF63_DC4C_8601_EC8C as UInt64))
    }
}

@Suite struct MockLibraryTests {
    @Test func continueWatchingHoldsOnlyStartedItems() {
        #expect(!MockLibrary.continueWatching.isEmpty)
        #expect(MockLibrary.continueWatching.allSatisfy { $0.isInProgress })
        #expect(MockLibrary.continueWatching.contains { $0.kind == .movie })
        #expect(MockLibrary.continueWatching.contains { $0.kind == .episode })
    }

    @Test func nextUpHoldsOneUnstartedEpisodePerStartedSeries() {
        #expect(!MockLibrary.nextUp.isEmpty)
        #expect(MockLibrary.nextUp.allSatisfy { $0.kind == .episode && !$0.isPlayed && $0.progress == 0 })
        let seriesIDs = MockLibrary.nextUp.compactMap(\.episode?.seriesID)
        #expect(Set(seriesIDs).count == seriesIDs.count)
        // Specials are never next, as on a server.
        #expect(MockLibrary.nextUp.allSatisfy { $0.episode?.seasonNumber != 0 })
    }

    @Test func latestResolvesEveryEntry() {
        #expect(MockLibrary.latest.count == 6)
        #expect(MockLibrary.latest.allSatisfy { $0.kind != .episode })
    }

    @Test func librariesSplitMoviesAndShows() {
        let kinds = MockLibrary.libraries.map(\.kind)
        #expect(kinds == [.movies, .shows])
        #expect(MockLibrary.libraries[0].items == MockMedia.movies)
        #expect(MockLibrary.libraries[1].items == MockMedia.series)
    }
}
