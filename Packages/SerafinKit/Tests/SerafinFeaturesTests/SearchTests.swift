import Foundation
import JellyfinAPI
import SerafinCore
import Testing

@testable import SerafinFeatures

private func throwawayDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "serafin-tests-\(UUID().uuidString)"))
}

private let alice = SessionKey(serverID: "server-a", userID: "alice")
private let bram = SessionKey(serverID: "server-a", userID: "bram")
private let carol = SessionKey(serverID: "server-b", userID: "carol")

@Suite struct RecentSearchesTests {
    @Test func theNewestSearchComesFirstAndARepeatMovesUp() throws {
        let recents = RecentSearches(account: alice, defaults: try throwawayDefaults())
        recents.record("Nosferatu")
        recents.record("  keaton ")
        let terms = recents.record("NOSFERATU")
        #expect(terms == ["NOSFERATU", "keaton"])
        #expect(recents.terms == terms)
    }

    @Test func onlyTheLastTenAreKept() throws {
        let recents = RecentSearches(account: alice, defaults: try throwawayDefaults())
        for index in 1...12 {
            recents.record("Search \(index)")
        }
        #expect(recents.terms.count == RecentSearches.limit)
        #expect(recents.terms.first == "Search 12")
        #expect(recents.terms.last == "Search 3")
    }

    @Test func eachAccountHasItsOwnAndEmptySearchesAreSkipped() throws {
        let defaults = try throwawayDefaults()
        RecentSearches(account: alice, defaults: defaults).record("Metropolis")
        RecentSearches(account: bram, defaults: defaults).record("   ")
        #expect(RecentSearches(account: bram, defaults: defaults).terms.isEmpty)
        #expect(RecentSearches(account: alice, defaults: defaults).terms == ["Metropolis"])
        #expect(RecentSearches(account: nil, defaults: defaults).record("Kept nowhere").isEmpty)
    }

    @Test func signingOutForgetsThatAccountsSearches() throws {
        let defaults = try throwawayDefaults()
        RecentSearches(account: alice, defaults: defaults).record("Metropolis")
        RecentSearches(account: bram, defaults: defaults).record("Sunrise")
        RecentSearches.forget(alice, in: defaults)
        #expect(RecentSearches(account: alice, defaults: defaults).terms.isEmpty)
        #expect(RecentSearches(account: bram, defaults: defaults).terms == ["Sunrise"])
    }

    @Test func removingAServerForgetsEveryoneOnIt() throws {
        let defaults = try throwawayDefaults()
        RecentSearches(account: alice, defaults: defaults).record("Metropolis")
        RecentSearches(account: bram, defaults: defaults).record("Sunrise")
        RecentSearches(account: carol, defaults: defaults).record("Faust")
        RecentSearches.forget(server: "server-a", in: defaults)
        #expect(RecentSearches(account: alice, defaults: defaults).terms.isEmpty)
        #expect(RecentSearches(account: bram, defaults: defaults).terms.isEmpty)
        #expect(RecentSearches(account: carol, defaults: defaults).terms == ["Faust"])
    }
}

@MainActor @Suite struct SearchModelTests {
    @Test func searchingAgainFillsTheFieldAndMovesTheSearchUp() throws {
        let model = SearchModel()
        model.showRecents(of: alice, in: try throwawayDefaults())
        model.query = "Sunrise"
        model.remember()
        model.query = "Faust"
        model.remember()
        model.searchAgain("Sunrise")
        #expect(model.query == "Sunrise")
        #expect(model.recents == ["Sunrise", "Faust"])
        model.clearRecents()
        #expect(model.recents.isEmpty)
    }

    @Test func eachAccountSeesItsOwnRecents() throws {
        let defaults = try throwawayDefaults()
        RecentSearches(account: alice, defaults: defaults).record("Metropolis")
        let model = SearchModel()
        model.showRecents(of: alice, in: defaults)
        #expect(model.recents == ["Metropolis"])
        model.showRecents(of: bram, in: defaults)
        #expect(model.recents.isEmpty)
    }

    @Test func suggestionsAreUnwatchedTitles() async {
        let model = SearchModel()
        #expect(!model.hasLoadedSuggestions)
        await model.loadSuggestions(from: SampleMediaSource())
        #expect(model.hasLoadedSuggestions)
        #expect(!model.suggestions.isEmpty)
        #expect(model.suggestions.count <= 6)
        #expect(model.suggestions.allSatisfy { !$0.card.isPlayed && $0.card.kind != .episode })
    }

    @Test func peopleAndCollectionsCountAsResults() async throws {
        let model = SearchModel()
        model.query = "Keaton"
        await model.search(in: SampleMediaSource())
        guard case .results(let results) = model.phase else {
            Issue.record("No results")
            return
        }
        #expect(results.people.map(\.name) == ["Buster Keaton"])
        #expect(model.isShowingResults)
    }
}

@Suite struct PersonPageTests {
    private let keaton = CastMember(
        id: "3-person-1", name: "Buster Keaton", role: "Johnnie Gray",
        source: BaseItemPerson(id: "person-1", name: "Buster Keaton"))

    @Test func aPersonsPageListsTheirMoviesAndShowsNewestFirst() {
        let scope = GridScope.person(keaton)
        let query = LiveMediaSource.query(for: scope, options: scope.initialOptions)
        #expect(query.personIDs == ["person-1"])
        #expect(query.types == [.movie, .series])
        #expect(query.sort == .premiereDate)
        #expect(!query.ascending)
        #expect(scope.title == "Buster Keaton")
        #expect(!scope.offersChips)
    }

    @Test func onlyAPersonTheServerNamedHasAPage() {
        #expect(keaton.personID == "person-1")
        let unnamed = CastMember(id: "0-Someone", name: "Someone", role: nil, source: BaseItemPerson(name: "Someone"))
        #expect(unnamed.personID == nil)
        let sample = CastMember(id: "keaton", name: "Buster Keaton", role: nil, source: nil)
        #expect(sample.personID == "keaton")
    }

    @Test func aPersonSearchFoundKeepsTheirPhoto() throws {
        let found = BaseItemDto(id: "person-2", imageTags: ["Primary": "p2"], name: "Harold Lloyd", type: .person)
        let person = try #require(LiveMediaSource.person(found))
        #expect(person.personID == "person-2")
        #expect(person.source?.primaryImageTag == "p2")
        #expect(person.role == nil)
        #expect(LiveMediaSource.person(BaseItemDto(id: "person-3")) == nil)
    }
}
