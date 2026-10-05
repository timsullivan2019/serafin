import Foundation
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

/// A Spotlight index the test reads back.
private actor RecordingStore: SpotlightStore {
    nonisolated let isAvailable = true
    /// Each entry's domain, by item ID.
    private(set) var domains: [String: String] = [:]
    /// The items that came with a poster.
    private(set) var posters: Set<String> = []
    /// How many times each item was written.
    private(set) var writes: [String: Int] = [:]
    private(set) var removedDomains: [[String]] = []
    private(set) var emptied = 0

    func index(_ entities: [MediaEntity], domain: String) async throws {
        for entity in entities {
            domains[entity.id] = domain
            writes[entity.id, default: 0] += 1
            if entity.poster != nil {
                posters.insert(entity.id)
            }
        }
    }

    func remove(domains removed: [String]) async throws {
        domains = domains.filter { !removed.contains($0.value) }
        removedDomains.append(removed)
    }

    func removeAll() async throws {
        domains = [:]
        emptied += 1
    }

    /// An entry left over from a title that has since gone from the server.
    func addLeftover(_ id: String, in domain: String) {
        domains[id] = domain
    }
}

/// A date the test moves by hand.
private final class TestDate: @unchecked Sendable {
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
}

@Suite struct SpotlightIndexerTests {
    private let store = RecordingStore()
    private let date = TestDate()
    /// Where every indexer in a test keeps its notes, so a new one picks up where the last left off.
    private let suite = "app.getserafin.serafin.tests.\(UUID().uuidString)"
    private let alice = SessionKey(serverID: "server-1", userID: "alice")
    private let media = SampleMediaSource()
    private let everything = Set((MockMedia.movies + MockMedia.series).map(\.id))

    private func indexer() throws -> SpotlightIndexer {
        let defaults = try #require(UserDefaults(suiteName: suite))
        return SpotlightIndexer(store: store, defaults: defaults, now: { [date] in date.now })
    }

    @Test func theFirstPassWritesEveryMovieAndShowWithItsPoster() async throws {
        await (try indexer()).update(account: alice, media: media) { _ in Data([1]) }
        #expect(Set(await store.domains.keys) == everything)
        #expect(Set(await store.domains.values) == ["library-a"])
        #expect(await store.posters == everything)
    }

    @Test func withinADayThereIsNothingToDo() async throws {
        let indexer = try indexer()
        await indexer.update(account: alice, media: media) { _ in nil }
        date.now += 23 * 60 * 60
        await indexer.update(account: alice, media: media) { _ in nil }
        #expect(await store.writes.values.allSatisfy { $0 == 1 })
    }

    @Test func aDayLaterThePassTakesTheOtherDomainAndClearsTheOld() async throws {
        let indexer = try indexer()
        await indexer.update(account: alice, media: media) { _ in nil }
        await store.addLeftover("movie-gone", in: "library-a")
        date.now += 25 * 60 * 60
        await indexer.update(account: alice, media: media) { _ in nil }

        let domains = await store.domains
        #expect(Set(domains.keys) == everything)
        #expect(Set(domains.values) == ["library-b"])
        #expect(await store.removedDomains == [["library-a"]])
    }

    @Test func anotherAccountStartsFromAnEmptyIndex() async throws {
        let indexer = try indexer()
        await indexer.update(account: alice, media: media) { _ in nil }
        let emptiedForAlice = await store.emptied
        await store.addLeftover("alices-only", in: "library-a")
        await indexer.update(account: SessionKey(serverID: "server-1", userID: "bob"), media: media) { _ in nil }

        #expect(await store.emptied == emptiedForAlice + 1)
        #expect(Set(await store.domains.keys) == everything)
    }

    @Test func emptyingTheIndexForgetsWhatWasWritten() async throws {
        let indexer = try indexer()
        await indexer.update(account: alice, media: media) { _ in nil }
        await indexer.removeAll()
        #expect(await store.domains.isEmpty)

        // The next pass writes again, without waiting a day.
        await indexer.update(account: alice, media: media) { _ in nil }
        #expect(Set(await store.domains.keys) == everything)
    }

    @Test func aTitleInTwoLibrariesIsWrittenOnce() async throws {
        // Every grid of the test source lists the same titles, so both sample libraries hold them.
        let shared = TestMediaSource(titles: ["Safety Last!", "The Freshman"])
        await (try indexer()).update(account: alice, media: shared) { _ in nil }
        #expect(await store.writes == ["test-Safety Last!": 1, "test-The Freshman": 1])
    }
}
