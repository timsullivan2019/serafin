import SwiftUI
import Testing

@testable import SerafinDesign

@MainActor @Suite struct EpisodeCardTests {
    private let short = "A short synopsis."
    private let long = String(
        repeating: "A synopsis long enough to run over several lines of a card on a show's page. ", count: 5)

    /// An episode with `overview`, from the samples.
    private func episode(_ overview: String?) -> MediaCard {
        var card = MockMedia.episodes[1]
        card.overview = overview
        return card
    }

    /// How tall `view` is at 300 points wide.
    private func height(of view: some View) throws -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: 300))
        let image = try #require(renderer.cgImage)
        return CGFloat(image.height) / renderer.scale
    }

    @Test func aCardIsAsTallAsItsWholeSynopsis() throws {
        let shortCard = try height(of: EpisodeCard(card: episode(short), artwork: nil) {})
        let longCard = try height(of: EpisodeCard(card: episode(long), artwork: nil) {})
        // Nothing is cut off: five sentences take several more lines than one.
        #expect(longCard > shortCard + 60)
    }

    @Test func aRowsTextHeightMakesAShorterCardAsTallAsTheTallest() throws {
        // The row hands every card the height of its tallest words, as measured hidden.
        let natural = try height(of: EpisodeCard(card: episode(short), artwork: nil) {})
        let lined = try height(
            of: EpisodeCard(card: episode(short), artwork: nil, textHeight: 400) {
            } menu: {
                EmptyView()
            })
        #expect(lined > natural)
        #expect(lined >= 400)
    }

    @Test func aDownloadsMarkKeepsTheCardAsTallAsItsMeasuredWords() throws {
        // The mark sits beside the number, so a row's hidden measure, which has no marks, still fits every card.
        let plain = try height(of: EpisodeCard(card: episode(short), artwork: nil) {})
        for mark in [DownloadMark.downloaded, .downloading(0.4), .downloading(nil)] {
            let marked = try height(
                of: EpisodeCard(card: episode(short), artwork: nil, download: mark) {
                } menu: {
                    EmptyView()
                })
            #expect(marked == plain)
        }
    }

    @Test func aDownloadsMarkIsSpoken() {
        let english = Locale(identifier: "en_US")
        #expect(DownloadMark.downloaded.accessibilityText(locale: english) == "Downloaded")
        #expect(DownloadMark.downloading(0.4).accessibilityText(locale: english) == "Downloading, 40%")
        #expect(DownloadMark.downloading(nil).accessibilityText(locale: english) == "Downloading")
    }
}
