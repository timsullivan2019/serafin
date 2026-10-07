import Foundation
import Testing

@testable import SerafinDesign

@Suite struct InformationColumnsTests {
    private let english = Locale(identifier: "en_US")
    private let languages = [
        "English", "French", "German", "Spanish", "Italian", "Portuguese", "Dutch", "Swedish", "Norwegian", "Danish",
        "Finnish", "Polish", "Japanese", "Korean",
    ]

    @Test func aListedRowReadsAsOneList() {
        let row = InformationColumns.Row(label: "Subtitles", items: ["English", "French"], locale: english)
        #expect(row.value == "English, French")
        #expect(row.items == ["English", "French"])
        #expect(InformationColumns.Row(label: "Rated", value: "NR").items.isEmpty)
    }

    @Test func aShortListShowsWhole() {
        #expect(InformationColumns.summary(of: Array(languages.prefix(3)), locale: english) == nil)
        #expect(InformationColumns.summary(of: [], locale: english) == nil)
    }

    @Test func aLongListShowsThreeAndCountsTheRest() throws {
        let summary = try #require(InformationColumns.summary(of: languages, locale: english))
        #expect(summary.shown == "English, French, German")
        #expect(summary.more == 11)
        let fewer = try #require(InformationColumns.summary(of: Array(languages.prefix(6)), locale: english))
        #expect(fewer.more == 3)
    }

    @Test func onlyTenOrFewerOpenInPlace() {
        #expect(InformationColumns.shownItems == 3)
        #expect(InformationColumns.inlineItems == 10)
        #expect(languages.count > InformationColumns.inlineItems)
    }
}

@Suite struct PlayPillTitleTests {
    @Test func thePillSaysWhatItPlays() throws {
        var film = MockMedia.movies[0]
        film.progress = 0
        let play = HeroHeader.playTitle(for: film)
        #expect(!play.contains("·"))

        film.progress = 0.4
        let remaining = try #require(film.remainingText)
        #expect(HeroHeader.playTitle(for: film).contains(remaining))

        let episode = try #require(MockMedia.episodes.first { $0.episodeCode != nil && !$0.isInProgress })
        #expect(HeroHeader.playTitle(for: episode).contains(try #require(episode.episodeCode)))
    }
}
