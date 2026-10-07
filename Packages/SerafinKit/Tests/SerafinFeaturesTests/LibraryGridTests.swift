import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

/// 150 made-up titles, one word for each letter in turn, so letters A to T have six titles and U to Z five.
private let longGrid: [String] = {
    let words = [
        "Apple", "Brook", "Cedar", "Delta", "Ember", "Fable", "Grove", "Haven", "Iris", "Jade", "Kite", "Lumen",
        "Maple", "North", "Opal", "Pine", "Quill", "Raven", "Stone", "Tide", "Umber", "Vale", "Willow", "Xenon",
        "Yarrow", "Zephyr",
    ]
    return (0..<150).map { "\(words[$0 % 26]) \($0)" }
}()

@MainActor
@Suite struct LibraryGridTests {
    private let scope = GridScope.library(MockLibrary.libraries[0])
    private let media = TestMediaSource(titles: longGrid)

    @Test func aLongGridHoldsAPlaceForEveryItemAndLoadsPagesWhereTheyAreNeeded() async {
        let model = LibraryModel(scope: scope)
        await model.reload(from: media)
        #expect(model.total == 150)
        #expect(model.item(at: 59) != nil)
        #expect(model.item(at: 60) == nil)

        await model.load(around: 100, from: media)
        #expect(model.item(at: 60) != nil)
        #expect(model.item(at: 119) != nil)
        #expect(model.item(at: 120) == nil)

        // Near the end of its page, a place loads the next page too.
        await model.load(around: 115, from: media)
        #expect(model.item(at: 149) != nil)
        #expect(model.item(at: 150) == nil)
    }

    @Test func aChangeToPlayedMarksKeepsWhatIsShownWhileItReloads() async {
        let model = LibraryModel(scope: scope)
        await model.reload(from: media)
        await model.load(around: 70, from: media)
        let generation = model.generation
        await model.reload(from: media)
        #expect(model.item(at: 70) != nil)
        #expect(model.generation > generation)
    }

    @Test func newOptionsStartTheGridOver() async {
        let model = LibraryModel(scope: scope)
        await model.reload(from: media)
        await model.load(around: 70, from: media)
        model.select(.name)
        await model.reload(from: media)
        #expect(model.item(at: 70) == nil)
        #expect(model.item(at: 0)?.card.title.hasPrefix("Zephyr") == true)
    }

    @Test func theIndexShowsOnLongGridsSortedByName() async {
        let model = LibraryModel(scope: scope)
        await model.reload(from: media)
        #expect(model.indexLetters == LetterIndex.alphabet)
        model.select(.name)
        #expect(model.indexLetters == LetterIndex.alphabet.reversed())
        model.select(.dateAdded)
        #expect(model.indexLetters.isEmpty)

        let short = LibraryModel(scope: scope)
        await short.reload(from: SampleMediaSource())
        #expect(short.indexLetters.isEmpty)
    }

    @Test func lettersJumpToWhereTheirTitlesStart() async {
        let model = LibraryModel(scope: scope)
        await model.reload(from: media)
        #expect(await model.position(of: "#", from: media) == 0)
        // A to L have six titles each.
        #expect(await model.position(of: "M", from: media) == 72)
        #expect(await model.position(of: "Z", from: media) == 145)
    }

    @Test func lettersJumpTheOtherWayWhenSortedBackwards() async {
        let model = LibraryModel(scope: scope)
        model.select(.name)
        await model.reload(from: media)
        #expect(await model.position(of: "Z", from: media) == 0)
        // Z to N come first: N to T have six titles each and U to Z five.
        #expect(await model.position(of: "M", from: media) == 72)
        #expect(await model.position(of: "#", from: media) == 149)
    }
}

@Suite struct LetterPositionTests {
    @Test func aToZCountsTheTitlesBeforeTheLetter() {
        #expect(LetterPosition.name(for: "M", ascending: true) == "m")
        #expect(LetterPosition.name(for: "#", ascending: true) == nil)
    }

    @Test func zToACountsTheTitlesBeforeTheNextLetter() {
        #expect(LetterPosition.name(for: "M", ascending: false) == "n")
        #expect(LetterPosition.name(for: "Z", ascending: false) == "{")
        #expect(LetterPosition.name(for: "#", ascending: false) == "a")
    }

    @Test func positionsStayInsideTheGrid() {
        #expect(LetterPosition.position(counting: 72, ascending: true, total: 150) == 72)
        #expect(LetterPosition.position(counting: 150, ascending: true, total: 150) == 149)
        #expect(LetterPosition.position(counting: 72, ascending: false, total: 150) == 78)
        #expect(LetterPosition.position(counting: 0, ascending: false, total: 0) == 0)
    }
}

@Suite struct GridScopeTests {
    @Test func eachScopeAsksTheServerForItsItems() {
        let options = GridOptions(unplayedOnly: true)
        let library = LiveMediaSource.query(for: .library(MockLibrary.libraries[1]), options: options)
        #expect(library.parentID == "library-shows")
        #expect(library.types == [.series])
        #expect(library.unplayedOnly)

        let genre = LiveMediaSource.query(
            for: .genre(Genre(id: "g1", name: "Comedy", count: 4)), options: GridOptions())
        #expect(genre.parentID == nil)
        #expect(genre.types == [.movie, .series])
        #expect(genre.genres == ["Comedy"])

        let collections = LiveMediaSource.query(for: .collections, options: GridOptions())
        #expect(collections.types == [.boxSet])

        let collection = LiveMediaSource.query(for: .collection(id: "c1", title: "Silent"), options: GridOptions())
        #expect(collection.parentID == "c1")
        #expect(collection.types == [.movie, .series])
    }

    @Test func aCollectionStartsInReleaseOrderWithoutChips() {
        let scope = GridScope.collection(id: "c1", title: "Silent Classics")
        #expect(scope.initialOptions.sort == .premiereDate)
        #expect(scope.initialOptions.ascending)
        #expect(!scope.offersChips)
        #expect(GridScope.collections.initialOptions.sort == .name)
        #expect(GridScope.genre(Genre(id: "g1", name: "Comedy", count: nil)).offersChips)
    }

    @Test func aServerCollectionOpensItsGrid() throws {
        let item = try #require(MediaItem(BaseItemDto(id: "box1", name: "Silent Classics", type: .boxSet)))
        #expect(item.card.kind == .collection)
        #expect(item.route == .collection(id: "box1", title: "Silent Classics"))
    }

    @Test func genresCountTheirMoviesAndShows() throws {
        let genre = try #require(Genre(BaseItemDto(id: "g1", movieCount: 3, name: "Comedy", seriesCount: 1)))
        #expect(genre.name == "Comedy")
        #expect(genre.count == 4)
        #expect(Genre(BaseItemDto(id: "g2", name: "Drama"))?.count == nil)
        #expect(Genre(BaseItemDto(id: "g3", name: "")) == nil)
    }
}

@MainActor
@Suite struct BrowseTests {
    @Test func theLibraryTabOffersCollectionsWhenThereAreAny() async {
        let model = LibrariesModel()
        await model.load(from: SampleMediaSource())
        #expect(model.hasCollections)
    }

    @Test func theSamplesBrowseByGenreAndCollection() async throws {
        let genres = GenresModel()
        await genres.load(from: SampleMediaSource())
        guard case .loaded(let list) = genres.phase else {
            Issue.record("The genres didn't load")
            return
        }
        let horror = try #require(list.first { $0.name == "Horror" })
        let model = LibraryModel(scope: .genre(horror))
        await model.reload(from: SampleMediaSource())
        #expect(model.total == horror.count)

        let collection = LibraryModel(scope: .collection(id: "collection-silent-classics", title: "Silent Classics"))
        await collection.reload(from: SampleMediaSource())
        #expect(collection.slots.map { $0?.card.title } == ["Nosferatu", "The General"])
    }
}

@Suite struct SortMenuTests {
    @Test func eachSortOffersItsNaturalOrderFirst() {
        #expect(LibraryQuery.Sort.name.directions == [true, false])
        #expect(LibraryQuery.Sort.dateAdded.directions == [false, true])
        #expect(LibraryQuery.Sort.premiereDate.directions == [false, true])
        #expect(LibraryQuery.Sort.rating.directions == [false, true])
    }

    @Test func eachOrderIsNamedForWhatItSorts() {
        #expect(LibraryQuery.Sort.name.directionTitle(ascending: true) == "A to Z")
        #expect(LibraryQuery.Sort.name.directionTitle(ascending: false) == "Z to A")
        #expect(LibraryQuery.Sort.dateAdded.directionTitle(ascending: false) == "Newest First")
        #expect(LibraryQuery.Sort.premiereDate.directionTitle(ascending: true) == "Oldest First")
        #expect(LibraryQuery.Sort.rating.directionTitle(ascending: false) == "Highest First")
        #expect(LibraryQuery.Sort.rating.directionTitle(ascending: true) == "Lowest First")
    }
}
