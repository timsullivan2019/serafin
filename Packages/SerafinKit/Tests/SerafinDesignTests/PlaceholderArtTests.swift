import CoreGraphics
import Foundation
import Testing

@testable import SerafinDesign

@Suite struct PlaceholderArtTests {
    @Test func postersAreTwoByThreeAndBackdropsSixteenByNine() throws {
        let poster = try #require(PlaceholderArt.poster(seed: 1))
        #expect(poster.width * 3 == poster.height * 2)
        let backdrop = try #require(PlaceholderArt.backdrop(seed: 1))
        #expect(backdrop.width * 9 == backdrop.height * 16)
    }

    @Test func theSameSeedGivesTheSameImage() throws {
        let first = try pixels(of: #require(PlaceholderArt.poster(seed: 42)))
        let second = try pixels(of: #require(PlaceholderArt.poster(seed: 42)))
        #expect(first == second)
    }

    @Test func differentSeedsGiveDifferentImages() throws {
        let first = try pixels(of: #require(PlaceholderArt.backdrop(seed: 1)))
        let second = try pixels(of: #require(PlaceholderArt.backdrop(seed: 2)))
        #expect(first != second)
    }

    @Test func everyFixtureHasArtwork() {
        for card in MockMedia.movies + MockMedia.series + MockMedia.episodes {
            #expect(MockMedia.poster(for: card) != nil)
            #expect(MockMedia.backdrop(for: card) != nil)
        }
    }

    @Test func artworkGivesALegibleTint() throws {
        for seed in 0..<20 {
            let poster = try #require(PlaceholderArt.poster(seed: seed))
            let tint = try #require(ArtworkTint.tint(for: poster))
            #expect(tint.contrastRatio(with: RGB(red: 1, green: 1, blue: 1)) >= 4.5)
        }
    }

    private func pixels(of image: CGImage) throws -> Data {
        let data = try #require(image.dataProvider?.data)
        return data as Data
    }
}
