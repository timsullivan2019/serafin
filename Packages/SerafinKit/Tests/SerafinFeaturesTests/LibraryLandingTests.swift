import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

@MainActor
@Suite struct LibraryLandingTests {
    private typealias Row = LibrariesModel.Row

    @Test func rowsComeInOrderEachLibraryUnderItsOwnName() async {
        let model = LibrariesModel()
        await model.load(from: SampleMediaSource())
        let libraries = MockLibrary.libraries
        #expect(
            model.visibleRows == [
                .library(libraries[0]), .library(libraries[1]), .collections, .shortcut(.favourites),
                .shortcut(.unwatched), .genres,
            ])
        #expect(
            model.visibleRows.map(\.title) == ["Movies", "Shows", "Collections", "Favorites", "Unwatched", "Genres"])
    }

    @Test func eachRowHoldsItsTwelveNewestTitlesNewestFirst() async throws {
        let model = LibrariesModel()
        await model.load(from: SampleMediaSource())
        let movies = try #require(model.titles[.library(MockLibrary.libraries[0])])
        // The samples are listed oldest addition first.
        #expect(movies.map(\.id) == MockMedia.movies.reversed().prefix(LibrariesModel.rowLength).map(\.id))
        for row in model.rows where row != .genres {
            #expect(try #require(model.titles[row]).count <= LibrariesModel.rowLength)
        }
    }

    @Test func librariesOfAKindKeepTheServersOrderMoviesFirst() {
        let everything = MediaLibrary(id: "e", name: "Everything", kind: .mixed, items: [])
        let anime = MediaLibrary(id: "a", name: "Anime", kind: .shows, items: [])
        let films = MediaLibrary(id: "f", name: "Films", kind: .movies, items: [])
        let television = MediaLibrary(id: "t", name: "Television", kind: .shows, items: [])
        let kids = MediaLibrary(id: "k", name: "Kids' Films", kind: .movies, items: [])
        let rows = LibrariesModel.rows(for: [everything, anime, films, television, kids])
        #expect(
            rows == [
                .library(films), .library(kids), .library(anime), .library(television), .library(everything),
                .collections, .shortcut(.favourites), .shortcut(.unwatched), .genres,
            ])
        #expect(rows.prefix(2).map(\.title) == ["Films", "Kids' Films"])
        #expect(LibrariesModel.rows(for: []).isEmpty)
    }

    @Test func rowsAskForTheNewestAdditionsFirst() throws {
        let library = MockLibrary.libraries[0]
        func query(_ row: Row) throws -> LibraryQuery {
            LiveMediaSource.query(for: try #require(row.scope), options: row.options)
        }
        for row in [Row.library(library), .collections, .shortcut(.favourites), .shortcut(.unwatched)] {
            let asked = try query(row)
            #expect(asked.sort == .dateAdded)
            #expect(!asked.ascending)
        }
        let movies = try query(.library(library))
        #expect(movies.parentID == library.id)
        #expect(movies.types == [.movie])
        #expect(!movies.favouritesOnly && !movies.unplayedOnly)
        #expect(try query(.collections).types == [.boxSet])
        // Favourites and Unwatched span every library.
        let favourites = try query(.shortcut(.favourites))
        #expect(favourites.parentID == nil)
        #expect(favourites.types == [.movie, .series])
        #expect(favourites.favouritesOnly && !favourites.unplayedOnly)
        let unwatched = try query(.shortcut(.unwatched))
        #expect(unwatched.parentID == nil)
        #expect(unwatched.unplayedOnly && !unwatched.favouritesOnly)
        #expect(Row.genres.scope == nil)
    }

    @Test func eachRowsTitleOpensItsGrid() {
        let library = MockLibrary.libraries[1]
        #expect(Row.library(library).route == .library(library))
        #expect(Row.collections.route == .collections)
        #expect(Row.shortcut(.favourites).route == .shortcut(.favourites))
        #expect(Row.shortcut(.unwatched).route == .shortcut(.unwatched))
        #expect(Row.genres.route == .genres)
    }

    @Test func rowsWithNothingInThemAreLeftOut() async {
        let model = LibrariesModel()
        await model.load(from: SampleMediaSource(includesCollections: false, includesFavourites: false))
        #expect(!model.visibleRows.contains(.collections))
        #expect(!model.visibleRows.contains(.shortcut(.favourites)))
        #expect(model.visibleRows.contains(.shortcut(.unwatched)))
        #expect(model.isSettled)
    }

    @Test func aRowShowsOnceTheRowsAboveItHaveLoaded() {
        let movies = Row.library(MockLibrary.libraries[0])
        let shows = Row.library(MockLibrary.libraries[1])
        let rows = LibrariesModel.rows(for: MockLibrary.libraries)
        // Nothing has loaded: the libraries' rows hold their places, and the rest wait.
        #expect(LibrariesModel.visible(rows, isLoaded: { _ in false }, isEmpty: { _ in true }) == [movies, shows])
        // Favourites and Genres are in, but Collections isn't, so they wait for it.
        let some: Set<Row> = [movies, .shortcut(.favourites), .genres]
        #expect(LibrariesModel.visible(rows, isLoaded: some.contains, isEmpty: { _ in false }) == [movies, shows])
        // Collections turns out empty, so the rows after it follow, up to Unwatched, which is still loading.
        let more = some.union([shows, .collections])
        #expect(
            LibrariesModel.visible(rows, isLoaded: more.contains, isEmpty: { $0 == .collections })
                == [movies, shows, .shortcut(.favourites)])
    }

    @Test func anEmptyLibraryLeavesNoRow() {
        let movies = Row.library(MockLibrary.libraries[0])
        let rows = LibrariesModel.rows(for: MockLibrary.libraries)
        let visible = LibrariesModel.visible(rows, isLoaded: { _ in true }, isEmpty: { $0 == movies })
        #expect(visible == Array(rows.dropFirst()))
    }

    @Test func aRowThatFailsIsLeftOutAndTheOthersStay() async {
        let model = LibrariesModel()
        await model.load(from: TestMediaSource(failingGrids: [.collections]))
        #expect(!model.visibleRows.contains(.collections))
        #expect(model.visibleRows.contains(.shortcut(.favourites)))
        #expect(model.isSettled)
        guard case .loaded = model.phase else {
            Issue.record("One row failing failed the tab")
            return
        }
    }

    @Test func whenEveryRowFailsTheTabSaysSoThenTryingAgainBringsThemBack() async {
        let grids = Set(LibrariesModel.rows(for: MockLibrary.libraries).compactMap(\.scope))
        let model = LibrariesModel()
        await model.load(from: TestMediaSource(failingGrids: grids, failsGenres: true))
        guard case .failed = model.phase else {
            Issue.record("The tab didn't say it failed")
            return
        }
        await model.load(from: SampleMediaSource())
        guard case .loaded = model.phase else {
            Issue.record("Trying again didn't bring the rows back")
            return
        }
        #expect(model.visibleRows == model.rows)
    }

    @Test func loadingAgainDropsARowThatEmptied() async {
        let model = LibrariesModel()
        await model.load(from: SampleMediaSource())
        #expect(model.visibleRows.contains(.shortcut(.favourites)))
        await model.load(from: SampleMediaSource(includesFavourites: false))
        #expect(!model.visibleRows.contains(.shortcut(.favourites)))
    }

    @Test func theGenresRowHoldsEveryGenre() async throws {
        let model = LibrariesModel()
        await model.load(from: SampleMediaSource())
        let genres = try await SampleMediaSource().genres()
        #expect(!genres.isEmpty)
        #expect(model.genres == genres)
    }

    @Test func aPosterInARowZoomsFromThatRow() {
        let movie = MediaItem(card: MockMedia.movies[0], source: nil)
        #expect(movie.route(zoomingFrom: "unwatched/\(movie.id)") == .card(movie, zoomID: "unwatched/\(movie.id)"))
        #expect(movie.route == .card(movie))
        // A collection opens its grid, which doesn't zoom.
        let collection = MediaItem(card: MockMedia.collections[0], source: nil)
        #expect(collection.route(zoomingFrom: "collections/\(collection.id)") == collection.route)
    }

    @Test func shortcutsStartFilteredTheirWay() {
        #expect(GridScope.shortcut(.favourites).initialOptions.favouritesOnly)
        #expect(GridScope.shortcut(.unwatched).initialOptions.unplayedOnly)
        for shortcut in LibraryShortcut.allCases {
            #expect(GridScope.shortcut(shortcut).offersChips)
            #expect(GridScope.shortcut(shortcut).title == shortcut.title)
        }
    }

    @Test func aGridLeavesOutTheChipItsScreenAlreadyImplies() {
        #expect(!GridScope.shortcut(.unwatched).offersUnwatchedChip)
        #expect(GridScope.shortcut(.unwatched).offersFavouritesChip)
        #expect(!GridScope.shortcut(.favourites).offersFavouritesChip)
        #expect(GridScope.shortcut(.favourites).offersUnwatchedChip)
        let library = GridScope.library(MockLibrary.libraries[0])
        #expect(library.offersUnwatchedChip && library.offersFavouritesChip)
        #expect(!GridScope.collections.offersUnwatchedChip && !GridScope.collections.offersFavouritesChip)
    }

    @Test func aShortcutAsksForEveryMovieAndShow() {
        let query = LiveMediaSource.query(for: .shortcut(.favourites), options: LibraryShortcut.favourites.options)
        #expect(query.parentID == nil)
        #expect(query.types == [.movie, .series])
        #expect(query.favouritesOnly)
    }

    @Test func favouritesListsOnlyFavourites() async throws {
        let page = try await SampleMediaSource().page(
            of: .shortcut(.favourites), options: LibraryShortcut.favourites.options, start: 0, limit: 100)
        let items = page.items.compactMap { $0 }
        #expect(!items.isEmpty)
        let allFavourites = items.allSatisfy { $0.card.isFavourite }
        #expect(allFavourites)
    }
}
