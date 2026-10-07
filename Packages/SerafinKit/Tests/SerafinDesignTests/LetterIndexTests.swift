import CoreGraphics
import Testing

@testable import SerafinDesign

@Suite struct LetterIndexTests {
    @Test func theIndexRunsFromSymbolsThroughZ() {
        #expect(LetterIndex.alphabet.count == 27)
        #expect(LetterIndex.alphabet.first == "#")
        #expect(LetterIndex.alphabet.last == "Z")
    }

    @Test func aTouchPicksTheLetterUnderIt() {
        #expect(LetterIndexMath.letter(at: 0, height: 270, count: 27) == 0)
        #expect(LetterIndexMath.letter(at: 135, height: 270, count: 27) == 13)
        #expect(LetterIndexMath.letter(at: 269.9, height: 270, count: 27) == 26)
        // A drag that runs past either end stays on the first or last letter.
        #expect(LetterIndexMath.letter(at: -40, height: 270, count: 27) == 0)
        #expect(LetterIndexMath.letter(at: 400, height: 270, count: 27) == 26)
        #expect(LetterIndexMath.letter(at: 10, height: 0, count: 27) == 0)
    }

    @Test func everyLetterShowsWhenThereIsRoom() {
        #expect(LetterIndexMath.rows(for: LetterIndex.alphabet, capacity: 40) == LetterIndex.alphabet)
        #expect(LetterIndexMath.rows(for: LetterIndex.alphabet, capacity: 27) == LetterIndex.alphabet)
    }

    @Test func aShortStripSkipsLettersWithADotBetween() {
        let rows = LetterIndexMath.rows(for: LetterIndex.alphabet, capacity: 13)
        #expect(rows.count == 13)
        #expect(rows.first == "#")
        #expect(rows.last == "Z")
        #expect(rows.enumerated().allSatisfy { index, row in (index % 2 == 1) == (row == "•") })
        #expect(LetterIndexMath.rows(for: LetterIndex.alphabet, capacity: 1) == ["#", "•", "Z"])
    }
}

@Suite struct MockCollectionTests {
    @Test func theSampleCollectionsHoldTheirMoviesInReleaseOrder() {
        let blender = MockMedia.members(of: MockMedia.collections[0])
        #expect(blender.count == 7)
        #expect(blender.map(\.year) == blender.map(\.year).sorted { ($0 ?? 0) < ($1 ?? 0) })
        #expect(MockMedia.members(of: MockMedia.collections[1]).map(\.title) == ["Nosferatu", "The General"])
        #expect(MockMedia.collections.allSatisfy { $0.kind == .collection && $0.posterCaption == nil })
        #expect(MockMedia.members(of: MockMedia.movies[0]).isEmpty)
    }
}
