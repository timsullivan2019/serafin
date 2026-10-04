import JellyfinAPI
import Testing

@testable import SerafinCore

@Suite struct SearchRankingTests {
    private func titles(_ items: [BaseItemDto]) -> [String] {
        items.compactMap(\.name)
    }

    @Test func anExactTitleComesFirstThenTitlesThatStartWithTheTerm() {
        let fromServer = [
            BaseItemDto(name: "The Adventures of Sherlock Holmes"),
            BaseItemDto(name: "Sherlock Holmes Baffled"),
            BaseItemDto(name: "Sherlock Holmes"),
        ]
        #expect(
            titles(SearchRanking.ranked(fromServer, for: " sherlock holmes "))
                == ["Sherlock Holmes", "Sherlock Holmes Baffled", "The Adventures of Sherlock Holmes"])
    }

    @Test func aLeadingArticleDoesNotHideAnExactTitle() {
        let fromServer = [
            BaseItemDto(name: "The Kid Brother", sortName: "kid brother"),
            BaseItemDto(name: "The Kid", sortName: "kid"),
        ]
        #expect(titles(SearchRanking.ranked(fromServer, for: "Kid")) == ["The Kid", "The Kid Brother"])
        #expect(titles(SearchRanking.ranked(fromServer, for: "the kid")) == ["The Kid", "The Kid Brother"])
    }

    @Test func caseAndAccentsDoNotMatter() {
        let fromServer = [BaseItemDto(name: "Häxan: Witchcraft Through the Ages"), BaseItemDto(name: "Häxan")]
        #expect(
            titles(SearchRanking.ranked(fromServer, for: "HAXAN")) == ["Häxan", "Häxan: Witchcraft Through the Ages"])
    }

    @Test func equallyCloseTitlesKeepTheServersOrder() {
        let fromServer = [BaseItemDto(name: "Nosferatu"), BaseItemDto(name: "Metropolis"), BaseItemDto(name: "Faust")]
        #expect(titles(SearchRanking.ranked(fromServer, for: "u")) == ["Nosferatu", "Metropolis", "Faust"])
    }
}
