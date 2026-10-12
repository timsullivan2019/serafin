import Foundation
import JellyfinAPI
import Testing

@testable import SerafinCore

/// Responses in the shape Jellyfin 10.10 returns, with public-domain titles, in `Fixtures/`.
enum Fixture {
    static func json(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// A library signed in as `user-1` on a stubbed server at `host`, keeping its Home in `homeSnapshots` when given.
func library(
    on host: String,
    cacheLifetime: Duration = LibraryRepository.defaultCacheLifetime,
    homeSnapshots: HomeSnapshotStore.Slot? = nil
) throws -> LibraryRepository {
    let configuration = JellyfinClient.Configuration(
        url: try #require(URL(string: "https://\(host)")),
        accessToken: "token-1",
        client: "Serafin",
        deviceName: "iPhone",
        deviceID: "device-1",
        version: "0.1.0"
    )
    let client = JellyfinClient(configuration: configuration, sessionConfiguration: StubURLProtocol.configuration())
    let errors = ServerErrors(pinning: PinningDelegate(pins: PinStore(secrets: InMemorySecretStore())))
    return LibraryRepository(
        client: client, userID: "user-1", errors: errors, cacheLifetime: cacheLifetime, homeSnapshots: homeSnapshots)
}

let moviesView = "f137a2dd21bbc1b99aa5c0f6bf02a805"

@Suite struct LibraryHomeTests {
    @Test func userViewsKeepsMoviesShowsAndMixedLibraries() async throws {
        let host = "views.example.com"
        StubURLProtocol.stub("\(host):443", path: "/UserViews", .json(200, try Fixture.json("UserViews")))
        let views = try await library(on: host).userViews()
        #expect(views.map(\.name) == ["Movies", "Shows", "Everything"])
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/UserViews").first?.query("userId") == "user-1")
    }

    @Test func resumeAsksForVideosWithWhatCardsNeed() async throws {
        let host = "resume.example.com"
        StubURLProtocol.stub("\(host):443", path: "/UserItems/Resume", .json(200, try Fixture.json("Resume")))
        let items = try await library(on: host).resume()

        #expect(items.map(\.name) == ["Night of the Living Dead", "The Red-Headed League"])
        #expect(items.first?.userData?.playedPercentage == 40)
        #expect(items.last?.type == .episode)
        #expect(items.last?.seriesName == "Sherlock Holmes")
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/UserItems/Resume").first)
        #expect(request.query("limit") == "20")
        #expect(request.queryValues("fields") == ["PrimaryImageAspectRatio", "Overview"])
        #expect(request.queryValues("mediaTypes") == ["Video"])
        #expect(request.query("enableUserData") == "true")
        #expect(request.authorization?.contains("Token=token-1") == true)
    }

    @Test func nextUpLeavesStartedEpisodesToContinueWatching() async throws {
        let host = "next-up.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Shows/NextUp", .json(200, try Fixture.json("NextUp")))
        let items = try await library(on: host).nextUp(limit: 12)
        #expect(items.map(\.name) == ["A Scandal in Bohemia"])
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/NextUp").first)
        #expect(request.query("enableResumable") == "false")
        #expect(request.query("limit") == "12")
    }

    @Test func aShowsPlayButtonResumesAStartedEpisode() async throws {
        let host = "series-next-up.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Shows/NextUp", .json(200, try Fixture.json("NextUp")))
        _ = try await library(on: host).nextUp(limit: 1, series: "9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c")
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/NextUp").first)
        #expect(request.query("seriesId") == "9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c")
        #expect(request.query("enableResumable") == "true")
    }

    @Test func filtersListAGridsGenresAndYears() async throws {
        let host = "filters.example.com"
        StubURLProtocol.stub(
            "\(host):443",
            path: "/Items/Filters",
            .json(200, #"{"Genres":["Horror","Comedy","comedy","Action"],"Years":[1926,1968,1940,1926],"Tags":[]}"#)
        )
        let filters = try await library(on: host).filters(in: moviesView, types: [.movie])
        #expect(filters.genres == ["Action", "comedy", "Comedy", "Horror"])
        #expect(filters.years == [1968, 1940, 1926])
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items/Filters").first)
        #expect(request.query("parentId") == moviesView)
        #expect(request.queryValues("includeItemTypes") == ["Movie"])
    }

    @Test func latestGroupsNewEpisodesUnderTheirShow() async throws {
        let host = "latest.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/Latest", .json(200, try Fixture.json("Latest")))
        let items = try await library(on: host).latest(in: moviesView)
        #expect(items.map(\.name) == ["Nosferatu", "Sherlock Holmes"])
        #expect(items.first?.userData?.isFavorite == true)
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items/Latest").first)
        #expect(request.query("parentId") == moviesView)
        #expect(request.query("groupItems") == "true")
    }
}

@Suite struct LibraryBrowsingTests {
    @Test func itemsReturnsAPageAndItsPlaceInTheWholeList() async throws {
        let host = "items.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items", .json(200, try Fixture.json("Items")))
        let query = LibraryQuery(
            parentID: moviesView,
            types: [.movie],
            sort: .dateAdded,
            ascending: false,
            unplayedOnly: true,
            favouritesOnly: true,
            genres: ["Comedy"],
            years: [1940]
        )
        let page = try await library(on: host).items(query, start: 60)

        #expect(page.items.map(\.name) == ["Charade", "His Girl Friday"])
        #expect(page.start == 60)
        #expect(page.total == 122)
        #expect(page.hasMore)
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items").first)
        #expect(request.query("parentId") == moviesView)
        #expect(request.queryValues("includeItemTypes") == ["Movie"])
        #expect(request.query("recursive") == "true")
        #expect(request.queryValues("sortBy") == ["DateCreated", "SortName"])
        #expect(request.queryValues("sortOrder") == ["Descending"])
        #expect(request.queryValues("filters") == ["IsUnplayed", "IsFavorite"])
        #expect(request.queryValues("genres") == ["Comedy"])
        #expect(request.queryValues("years") == ["1940"])
        #expect(request.query("startIndex") == "60")
        #expect(request.query("limit") == "60")
    }

    @Test func countingBeforeANameKeepsTheGridsFiltersAndAsksForNoItems() async throws {
        let host = "count.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/Items", .json(200, #"{"Items":[],"TotalRecordCount":17,"StartIndex":0}"#))
        let query = LibraryQuery(parentID: moviesView, types: [.movie], unplayedOnly: true, genres: ["Comedy"])
        let count = try await library(on: host).count(query, before: "m")

        #expect(count == 17)
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items").first)
        #expect(request.query("nameLessThan") == "m")
        #expect(request.query("limit") == "0")
        #expect(request.query("parentId") == moviesView)
        #expect(request.queryValues("includeItemTypes") == ["Movie"])
        #expect(request.queryValues("filters") == ["IsUnplayed"])
        #expect(request.queryValues("genres") == ["Comedy"])
        #expect(request.query("enableTotalRecordCount") == "true")
        #expect(request.query("fields") == nil)
    }

    @Test func aGridOfAnyKindSendsNoKinds() async throws {
        let host = "anykind.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items", .json(200, try Fixture.json("Items")))
        _ = try await library(on: host).items(LibraryQuery(parentID: "collection-1", types: []))
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items").first)
        #expect(request.query("parentId") == "collection-1")
        #expect(request.query("includeItemTypes") == nil)
    }

    @Test func genresComeWithTheirCountsInOrder() async throws {
        let host = "genres.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Genres", .json(200, try Fixture.json("Genres")))
        let genres = try await library(on: host).genres()

        #expect(genres.map(\.name) == ["Comedy", "Horror"])
        #expect(genres.first?.movieCount == 3)
        #expect(genres.first?.seriesCount == 1)
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Genres").first)
        #expect(request.query("userId") == "user-1")
        #expect(request.queryValues("includeItemTypes") == ["Movie", "Series"])
        #expect(request.queryValues("fields") == ["ItemCounts"])
        #expect(request.queryValues("sortBy") == ["SortName"])
    }

    @Test func itemReturnsEverythingTheDetailScreenShows() async throws {
        let host = "item.example.com"
        let id = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"
        StubURLProtocol.stub("\(host):443", path: "/Items/\(id)", .json(200, try Fixture.json("Movie")))
        let item = try await library(on: host).item(id: id)

        #expect(item.name == "The General")
        #expect(item.genres == ["Comedy", "Action"])
        #expect(item.people?.count == 2)
        #expect(item.mediaSources?.first?.mediaStreams?.count == 3)
        #expect(item.premiereDate != nil)
    }

    @Test func anItemThatIsGoneIsReported() async throws {
        let host = "gone.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/0123456789abcdef", .json(404, "{}"))
        await #expect(throws: SerafinError.notFound) {
            try await library(on: host).item(id: "0123456789abcdef")
        }
    }

    @Test(arguments: ["../../System/Info", "a/b", "id?x=1", "", "%2e%2e"])
    func anIDJellyfinWouldNotIssueIsNeverSent(id: String) async throws {
        let host = "odd-id.example.com"
        await #expect(throws: SerafinError.notFound) {
            try await library(on: host).item(id: id)
        }
        #expect(StubURLProtocol.lastRequest(to: "\(host):443") == nil)
    }

    @Test func seasonsAndTheirEpisodesComeInOrder() async throws {
        let host = "show.example.com"
        let series = "9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c"
        let season = "a09b8c7d6e5f4a3b2c1d0e9f8a7b6c5d"
        StubURLProtocol.stub("\(host):443", path: "/Shows/\(series)/Seasons", .json(200, try Fixture.json("Seasons")))
        StubURLProtocol.stub("\(host):443", path: "/Shows/\(series)/Episodes", .json(200, try Fixture.json("Episodes")))
        let library = try library(on: host)

        #expect(try await library.seasons(series: series).map(\.indexNumber) == [1, 2])
        let episodes = try await library.episodes(series: series, season: season)
        #expect(episodes.map(\.name) == ["A Scandal in Bohemia", "The Red-Headed League"])
        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/\(series)/Episodes").first)
        #expect(request.query("seasonId") == season)
        // Episodes carry their streams, for the badges, and seasons how many episodes they have, for the menu.
        #expect(request.queryValues("fields").contains("MediaStreams"))
        let seasons = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/\(series)/Seasons").first)
        #expect(seasons.queryValues("fields").contains("ChildCount"))
    }

    @Test func similarTitles() async throws {
        let host = "similar.example.com"
        let id = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"
        StubURLProtocol.stub("\(host):443", path: "/Items/\(id)/Similar", .json(200, try Fixture.json("Similar")))
        #expect(try await library(on: host).similar(to: id).map(\.name) == ["His Girl Friday"])
    }

    @Test func searchGroupsResultsByKind() async throws {
        let host = "search.example.com"
        let movies =
            #"{"Items":[{"Name":"Nosferatu","Id":"6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f","Type":"Movie"}],"TotalRecordCount":1}"#
        let series =
            #"{"Items":[{"Name":"Sherlock Holmes","Id":"9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c","Type":"Series"}],"TotalRecordCount":1}"#
        StubURLProtocol.stub("\(host):443", path: "/Items", query: ["includeItemTypes": "Movie"], .json(200, movies))
        StubURLProtocol.stub("\(host):443", path: "/Items", query: ["includeItemTypes": "Series"], .json(200, series))
        StubURLProtocol.stub(
            "\(host):443",
            path: "/Items",
            query: ["includeItemTypes": "Episode"],
            .json(200, #"{"Items":[],"TotalRecordCount":0}"#)
        )
        let collections =
            #"{"Items":[{"Name":"Nosferatu Restorations","Id":"1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d","Type":"BoxSet"}]}"#
        StubURLProtocol.stub(
            "\(host):443", path: "/Items", query: ["includeItemTypes": "BoxSet"], .json(200, collections))
        let people =
            #"{"Items":[{"Name":"Max Schreck","Id":"2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e","Type":"Person","ImageTags":{"Primary":"p1"}}]}"#
        StubURLProtocol.stub("\(host):443", path: "/Persons", .json(200, people))
        let results = try await library(on: host).search(term: "  no  ")

        #expect(results.movies.map(\.name) == ["Nosferatu"])
        #expect(results.series.map(\.name) == ["Sherlock Holmes"])
        #expect(results.episodes.isEmpty)
        #expect(results.collections.map(\.name) == ["Nosferatu Restorations"])
        #expect(results.people.map(\.name) == ["Max Schreck"])
        let requests = StubURLProtocol.requests(to: "\(host):443", path: "/Items")
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.query("searchTerm") == "no" })
        let person = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Persons").first)
        #expect(person.query("searchTerm") == "no")
        #expect(person.query("userId") == "user-1")
    }

    @Test func suggestionsAreTwelveUnwatchedTitlesAtRandom() async throws {
        let host = "suggestions.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items", .json(200, try Fixture.json("Items")))
        _ = try await library(on: host).suggestions()

        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items").first)
        #expect(request.queryValues("includeItemTypes") == ["Movie", "Series"])
        #expect(request.queryValues("filters") == ["IsUnplayed"])
        #expect(request.queryValues("sortBy") == ["Random"])
        #expect(request.query("limit") == "12")
        #expect(request.query("recursive") == "true")
    }

    @Test func watchedTitlesFillSuggestionsWhenFewAreUnwatched() async throws {
        let host = "suggestions-top-up.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items", .json(200, try Fixture.json("Items")))
        let suggestions = try await library(on: host).suggestions()

        // Two unwatched titles aren't twelve, so a second ask takes any title, and the two aren't repeated.
        let requests = StubURLProtocol.requests(to: "\(host):443", path: "/Items")
        #expect(requests.count == 2)
        #expect(requests.last?.queryValues("filters") == [])
        #expect(suggestions.count == 2)
    }

    @Test func aPersonsGridAsksForTheirTitles() async throws {
        let host = "person-grid.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items", .json(200, try Fixture.json("Items")))
        let query = LibraryQuery(parentID: nil, types: [.movie, .series], personIDs: ["person-1"])
        _ = try await library(on: host).items(query)

        let request = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Items").first)
        #expect(request.queryValues("personIds") == ["person-1"])
        #expect(request.query("parentId") == nil)
    }

    @Test func anEmptySearchAsksNothing() async throws {
        let results = try await library(on: "empty-search.example.com").search(term: "   ")
        #expect(results.isEmpty)
        #expect(StubURLProtocol.lastRequest(to: "empty-search.example.com:443") == nil)
    }
}

@Suite struct LibraryChangesTests {
    private let item = "5b4c3d2e1f0a9b8c7d6e5f4a3b2c1d0e"

    @Test func markingPlayedTellsTheServerAndRefreshesHome() async throws {
        let host = "played.example.com"
        StubURLProtocol.stub("\(host):443", path: "/UserItems/Resume", .json(200, try Fixture.json("Resume")))
        StubURLProtocol.stub(
            "\(host):443", path: "/UserPlayedItems/\(item)", .json(200, try Fixture.json("UserItemData")))
        let library = try library(on: host)

        _ = try await library.resume()
        let data = try await library.markPlayed(id: item)
        _ = try await library.resume()

        #expect(data.isPlayed == true)
        let change = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/UserPlayedItems/\(item)").first)
        #expect(change.request.httpMethod == "POST")
        #expect(change.query("userId") == "user-1")
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/UserItems/Resume").count == 2)
    }

    @Test func markingUnplayedDeletesThePlayedMark() async throws {
        let host = "unplayed.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/UserPlayedItems/\(item)", .json(200, try Fixture.json("UserItemData")))
        try await library(on: host).markUnplayed(id: item)
        #expect(
            StubURLProtocol.requests(to: "\(host):443", path: "/UserPlayedItems/\(item)").first?.request.httpMethod
                == "DELETE")
    }

    @Test func favouritesAreAddedAndTakenAway() async throws {
        let host = "favourites.example.com"
        StubURLProtocol.stub(
            "\(host):443", path: "/UserFavoriteItems/\(item)", .json(200, try Fixture.json("UserItemData")))
        let library = try library(on: host)

        #expect(try await library.setFavourite(id: item, on: true).isFavorite == true)
        try await library.setFavourite(id: item, on: false)

        let methods = StubURLProtocol.requests(to: "\(host):443", path: "/UserFavoriteItems/\(item)").map(
            \.request.httpMethod)
        #expect(methods == ["POST", "DELETE"])
    }

    @Test func aSignInTheServerNoLongerAcceptsIsReported() async throws {
        let host = "revoked.example.com"
        StubURLProtocol.stub("\(host):443", path: "/UserViews", .json(401, "{}"))
        await #expect(throws: SerafinError.notSignedIn) {
            try await library(on: host).userViews()
        }
    }
}

@Suite struct LibraryCacheTests {
    @Test func aRepeatedReadIsAnsweredFromTheCache() async throws {
        let host = "cached.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Shows/NextUp", .json(200, try Fixture.json("NextUp")))
        let library = try library(on: host)
        _ = try await library.nextUp()
        #expect(try await library.nextUp().count == 1)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/NextUp").count == 1)
    }

    @Test func differentRequestsAreCachedApart() async throws {
        let host = "cached-apart.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Shows/NextUp", .json(200, try Fixture.json("NextUp")))
        let library = try library(on: host)
        _ = try await library.nextUp(limit: 5)
        _ = try await library.nextUp(limit: 6)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/NextUp").count == 2)
    }

    @Test func clearingTheCacheAsksTheServerAgain() async throws {
        let host = "refreshed.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Shows/NextUp", .json(200, try Fixture.json("NextUp")))
        let library = try library(on: host)
        _ = try await library.nextUp()
        await library.clearCache()
        _ = try await library.nextUp()
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/NextUp").count == 2)
    }

    @Test func cachedAnswersExpire() async throws {
        let host = "expired-cache.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Shows/NextUp", .json(200, try Fixture.json("NextUp")))
        let library = try library(on: host, cacheLifetime: .milliseconds(20))
        _ = try await library.nextUp()
        try await Task.sleep(for: .milliseconds(40))
        _ = try await library.nextUp()
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Shows/NextUp").count == 2)
    }

    @Test func failuresAreNotCached() async throws {
        let host = "flaky-home.example.com"
        StubURLProtocol.stub(
            "\(host):443",
            path: "/Shows/NextUp",
            .failure(.notConnectedToInternet),
            .json(200, try Fixture.json("NextUp"))
        )
        let library = try library(on: host)
        await #expect(throws: SerafinError.offline) { try await library.nextUp() }
        #expect(try await library.nextUp().count == 1)
    }
}
