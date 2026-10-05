import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

/// When the saved Home is from.
private let savedDate = Date(timeIntervalSince1970: 1_790_000_000)

/// Home as saved on the device: one started movie.
private let saved = HomeContent(
    continueWatching: [MediaItem(card: MockMedia.movies[0], source: nil)], nextUp: [], latest: [], date: savedDate)

extension HomeModel.Phase {
    /// The rows showing, or nil while loading or after a failure.
    fileprivate var rows: HomeContent? {
        if case .loaded(let home) = self { home } else { nil }
    }

    /// The failure filling the screen, if there is one.
    fileprivate var failure: UserMessage? {
        if case .failed(let message) = self { message } else { nil }
    }
}

@MainActor
@Suite struct OfflineHomeTests {
    @Test func theServersRowsTakeTheSavedRowsPlace() async throws {
        let model = HomeModel()
        await model.load(from: TestMediaSource(saved: saved))
        let home = try #require(model.phase.rows)
        #expect(home.date != savedDate)
        #expect(home.continueWatching.count == MockLibrary.continueWatching.count)
        #expect(model.notice == nil)
        #expect(!model.isWorthRetrying)
    }

    @Test func whenTheServerCantBeReachedTheSavedRowsShowUnderANotice() async throws {
        let model = HomeModel()
        await model.load(from: TestMediaSource(saved: saved, homeFailure: .offline))
        let home = try #require(model.phase.rows)
        #expect(home.continueWatching.map(\.id) == saved.continueWatching.map(\.id))
        #expect(model.notice == HomeModel.Notice(message: UserMessage(SerafinError.offline), date: savedDate))
        #expect(model.notice?.message.title == "You're Offline")
        #expect(!model.isLoading)
        #expect(model.isWorthRetrying)
    }

    @Test func withNothingSavedAFailureFillsTheScreen() async {
        let model = HomeModel()
        await model.load(from: TestMediaSource(homeFailure: .serverUnreachable))
        #expect(model.phase.failure?.title == "Can't Reach the Server")
        #expect(model.notice == nil)
        #expect(model.isWorthRetrying)
    }

    @Test func anEmptySavedHomeIsntPassedOffAsAnEmptyLibrary() async {
        let model = HomeModel()
        let empty = HomeContent(continueWatching: [], nextUp: [], latest: [], date: savedDate)
        await model.load(from: TestMediaSource(saved: empty, homeFailure: .offline))
        #expect(model.phase.failure?.title == "You're Offline")
    }

    @Test func rowsKeepShowingWhenAReloadFailsUntilOneWorks() async throws {
        let model = HomeModel()
        await model.load(from: TestMediaSource())
        let first = try #require(model.phase.rows)

        await model.load(from: TestMediaSource(homeFailure: .serverUnreachable))
        #expect(model.notice?.message.title == "Can't Reach the Server")
        #expect(model.notice?.date == first.date)

        await model.load(from: TestMediaSource())
        #expect(model.notice == nil)
    }

    @Test func anEndedSignInAsksToSignInAgainAboveTheRows() async {
        let model = HomeModel()
        await model.load(from: TestMediaSource(saved: saved, homeFailure: .notSignedIn))
        #expect(model.notice?.message.needsSignIn == true)
    }
}

@Suite struct SavedHomeTests {
    @Test func aSavedHomeShowsAsTheServerSentIt() {
        let started = BaseItemDto(
            id: "metropolis", name: "Metropolis", productionYear: 1927, type: .movie,
            userData: UserItemDataDto(key: "metropolis", playedPercentage: 40))
        let snapshot = HomeSnapshot(
            date: savedDate,
            libraries: [
                BaseItemDto(collectionType: .movies, id: "movies", name: "Movies"),
                BaseItemDto(collectionType: .music, id: "music", name: "Music"),
            ],
            resume: [started],
            nextUp: [],
            latest: [
                "movies": [
                    BaseItemDto(id: "nosferatu", name: "Nosferatu", type: .movie),
                    BaseItemDto(id: "song", name: "Song", type: .audio),
                ],
                "music": [BaseItemDto(id: "album", name: "Album", type: .musicAlbum)],
            ]
        )
        let home = HomeContent(snapshot)
        #expect(home.date == savedDate)
        #expect(home.continueWatching.map(\.card.title) == ["Metropolis"])
        #expect(home.continueWatching.first?.card.progress == 0.4)
        #expect(home.nextUp.isEmpty)
        #expect(home.latest.map(\.library.name) == ["Movies"])
        #expect(home.latest.first?.items.map(\.card.title) == ["Nosferatu"])
    }
}

@Suite struct HomeNoticeTextTests {
    private let locale = Locale(identifier: "en_US")
    private let calendar: Calendar
    private let now: Date

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        self.calendar = calendar
        now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 15)))
    }

    /// The banner's line for a time on another day, in the test's locale, with the spaces iOS puts before AM and PM
    /// written as plain ones.
    private func line(_ components: DateComponents) throws -> String {
        let date = try #require(calendar.date(from: components))
        return HomeNoticeBanner.lastUpdated(date, now: now, calendar: calendar, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    @Test func earlierTodayShowsTheTime() throws {
        #expect(try line(DateComponents(year: 2026, month: 10, day: 5, hour: 9, minute: 41)) == "Last updated 9:41 AM")
    }

    @Test func anotherDayShowsTheDayToo() throws {
        #expect(
            try line(DateComponents(year: 2026, month: 10, day: 3, hour: 21, minute: 41))
                == "Last updated Oct 3 at 9:41 PM")
    }

    @Test func anotherYearShowsTheYearToo() throws {
        #expect(
            try line(DateComponents(year: 2025, month: 12, day: 30, hour: 21, minute: 41))
                == "Last updated Dec 30, 2025 at 9:41 PM")
    }
}
