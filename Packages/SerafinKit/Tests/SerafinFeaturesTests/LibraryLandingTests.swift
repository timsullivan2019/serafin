import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

@MainActor
@Suite struct LibraryLandingTests {
    @Test func eachLibrarysTileHasItsCountAndNewestPosters() async throws {
        let model = LibrariesModel()
        await model.load(from: SampleMediaSource())
        for library in MockLibrary.libraries {
            let overview = try #require(model.overviews[library.id])
            #expect(overview.total == library.items.count)
            #expect(overview.newest.count == min(LibrariesModel.collageSize, library.items.count))
            #expect(overview.cover == nil)
        }
    }

    @Test func aLibraryWithAPictureOfItsOwnKeepsItForItsTile() async throws {
        let library = try #require(MockLibrary.libraries.first)
        let model = LibrariesModel()
        await model.load(from: TestMediaSource(covers: [library.id]))
        #expect(try #require(model.overviews[library.id]).cover?.id == library.id)
        for other in MockLibrary.libraries.dropFirst() {
            #expect(try #require(model.overviews[other.id]).cover == nil)
        }
    }

    @Test func tileCaptionsCountInTheLibrarysOwnWords() {
        #expect(LibrariesModel.caption(total: 75, kind: .movies).contains("75"))
        #expect(LibrariesModel.caption(total: 1, kind: .shows).contains("1"))
        #expect(LibrariesModel.caption(total: 4, kind: .mixed).contains("4"))
    }

    @Test func oneOrTwoLibrariesFillTheWidthOnIPhone() {
        #expect(LibraryTilesLayout.columns(libraries: 2, isRegularWidth: false) == 1)
        #expect(LibraryTilesLayout.columns(libraries: 3, isRegularWidth: false) == 2)
        #expect(LibraryTilesLayout.columns(libraries: 2, isRegularWidth: true) == 2)
        #expect(LibraryTilesLayout.columns(libraries: 5, isRegularWidth: true) == 3)
    }

    @Test func browseShortcutsStartFilteredOrSortedTheirWay() {
        #expect(GridScope.shortcut(.favourites).initialOptions.favouritesOnly)
        #expect(GridScope.shortcut(.unwatched).initialOptions.unplayedOnly)
        let recent = GridScope.shortcut(.recentlyAdded).initialOptions
        #expect(recent.sort == .dateAdded && !recent.ascending)
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
        #expect(GridScope.shortcut(.recentlyAdded).offersUnwatchedChip)
        #expect(GridScope.shortcut(.recentlyAdded).offersFavouritesChip)
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
