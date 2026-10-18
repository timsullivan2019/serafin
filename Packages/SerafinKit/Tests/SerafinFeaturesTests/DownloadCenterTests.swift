import Foundation
import SerafinCore
import SerafinDesign
import SerafinPlayback
import Testing

@testable import SerafinFeatures

@MainActor @Suite struct DownloadCenterTests {
    private let key = SessionKey(serverID: "server", userID: "user")

    private func record(_ state: DownloadRecord.State, failure: DownloadFailure? = nil) -> DownloadRecord {
        DownloadRecord(
            id: "download", key: key, itemID: "movie-sintel", mediaSourceID: "movie-sintel", fileExtension: "mp4",
            state: state, failure: failure, metadata: DownloadMetadata(title: "Sintel", kind: .movie))
    }

    @Test func eachRecordShowsWhereItsDownloadIs() {
        let progress = ["download": Downloads.Progress(received: 25, expected: 100)]
        #expect(DownloadCenter.state(of: nil, progress: progress) == .notDownloaded)
        #expect(DownloadCenter.state(of: record(.waiting), progress: progress) == .waiting)
        #expect(DownloadCenter.state(of: record(.downloading), progress: progress) == .downloading(0.25))
        #expect(DownloadCenter.state(of: record(.downloading), progress: [:]) == .downloading(nil))
        #expect(DownloadCenter.state(of: record(.finished), progress: progress) == .finished)
        #expect(
            DownloadCenter.state(of: record(.failed, failure: .notAllowed), progress: progress) == .failed(.notAllowed))
    }

    @Test func aCardMarksADownloadOnItsWayOrSaved() {
        #expect(DownloadCenter.mark(for: .notDownloaded) == nil)
        // A failed download says so in its menu instead.
        #expect(DownloadCenter.mark(for: .failed(.network)) == nil)
        #expect(DownloadCenter.mark(for: .waiting) == .downloading(nil))
        #expect(DownloadCenter.mark(for: .downloading(0.25)) == .downloading(0.25))
        #expect(DownloadCenter.mark(for: .preparing) == .downloading(nil))
        #expect(DownloadCenter.mark(for: .finished) == .downloaded)
    }

    @Test func anEpisodeKeepsItsSeriesAndNumbers() throws {
        let card = try #require(MockMedia.episodes.first)
        let metadata = DownloadMetadata(card)
        #expect(metadata.kind == .episode)
        #expect(metadata.title == card.title)
        #expect(metadata.seriesName == card.episode?.seriesTitle)
        #expect(metadata.seasonNumber == card.episode?.seasonNumber)
        #expect(metadata.episodeNumber == card.episode?.episodeNumber)
    }

    @Test func aMovieKeepsItsYearAndRuntime() throws {
        let card = try #require(MockMedia.movies.first)
        let metadata = DownloadMetadata(card)
        #expect(metadata.kind == .movie)
        #expect(metadata.year == card.year)
        #expect(metadata.runtime == card.runtime)
        #expect(metadata.seriesName == nil)
    }

    @Test func failuresReadAsAFewWords() {
        #expect(DownloadRow.reason(.interrupted) != DownloadRow.reason(.network))
        #expect(DownloadRow.reason(nil) == DownloadRow.reason(.serverError))
        #expect(DownloadRow.reason(.preparationFailed) != DownloadRow.reason(nil))
    }

    @Test func downloadsAreMadeAtMaximumUntilAnotherQualityIsPicked() throws {
        let defaults = try #require(UserDefaults(suiteName: "app.getserafin.serafin.tests.\(UUID().uuidString)"))
        #expect(DownloadCenter.quality(in: defaults) == .maximum)
        #expect(DownloadCenter.quality(in: defaults).bitsPerSecond == nil)
        defaults.set(PlaybackQuality.mbps8.rawValue, forKey: DownloadCenter.qualityKey)
        #expect(DownloadCenter.quality(in: defaults).bitsPerSecond == 8_000_000)
        // A value no quality has reads as Maximum.
        defaults.set(12_345, forKey: DownloadCenter.qualityKey)
        #expect(DownloadCenter.quality(in: defaults) == .maximum)
    }

    @Test func eachRefusalSaysWhatToDo() {
        let messages = [DownloadRefusal.notAllowed, .overQuality, .unavailable].map { UserMessage.refused($0) }
        #expect(Set(messages.map(\.message)).count == 3)
        #expect(Set(messages.map(\.title)).count == 1)
    }

    @Test func theNextUnwatchedEpisodesSkipThoseWatchedOutOfOrder() {
        func episode(_ number: Int, played: Bool = false, progress: Double = 0) -> MediaItem {
            let card = MediaCard(
                id: "episode-\(number)", kind: .episode, title: "Episode \(number)", progress: progress,
                isPlayed: played)
            return MediaItem(card: card, source: nil)
        }
        let episodes = [
            episode(4, progress: 0.3),
            episode(5),
            episode(6, played: true),
            episode(7),
            episode(8),
        ]

        // One part way through counts as not yet watched.
        #expect(DownloadCenter.unwatched(3, of: episodes).map(\.id) == ["episode-4", "episode-5", "episode-7"])
        #expect(DownloadCenter.unwatched(10, of: episodes).count == 4)
        #expect(DownloadCenter.unwatched(3, of: []).isEmpty)
    }

    @Test func episodesThatDidntStartSayWhyAndWhetherOthersDid() {
        let reasons: [UserMessage.UnstartedEpisodes] = [
            .refused(.notAllowed), .refused(.overQuality), .refused(.unavailable), .notEnoughSpace,
        ]
        let messages = reasons.map { UserMessage.episodesNotStarted($0, anyStarted: true) }
        #expect(Set(messages.map(\.message)).count == reasons.count)
        #expect(Set(messages.map(\.title)).count == 1)
        #expect(
            UserMessage.episodesNotStarted(.notEnoughSpace, anyStarted: false).title
                != UserMessage.episodesNotStarted(.notEnoughSpace, anyStarted: true).title)
        // Anything else says what the error does.
        let offline = UserMessage.episodesNotStarted(.failed(SerafinError.offline), anyStarted: false)
        #expect(offline.message == UserMessage(SerafinError.offline).message)
        #expect(ShowDownloadMenuItems.episodes(5).contains("5"))
    }
}

@MainActor @Suite struct DownloadGroupTests {
    private let key = SessionKey(serverID: "server", userID: "user")

    /// A download of an episode of `seriesID`'s show, as the device saved it.
    private func episode(
        _ id: String,
        season: Int? = 1,
        _ number: Int?,
        seriesID: String? = "series-sherlock",
        seriesName: String = "Sherlock Holmes",
        state: DownloadRecord.State = .finished,
        isWatched: Bool = false
    ) -> DownloadRecord {
        DownloadRecord(
            id: id, key: key, itemID: id, mediaSourceID: id, fileExtension: "mp4", state: state, bytes: 640_000_000,
            metadata: DownloadMetadata(
                title: id, kind: .episode, seriesID: seriesID, seriesName: seriesName, seasonNumber: season,
                episodeNumber: number, runtime: .seconds(3000)),
            playback: isWatched ? DownloadPlayback(position: .zero, isPlayed: true) : nil)
    }

    /// A download of a movie, as the device saved it.
    private func movie(_ id: String, isWatched: Bool = false) -> DownloadRecord {
        DownloadRecord(
            id: id, key: key, itemID: id, mediaSourceID: id, fileExtension: "mp4", state: .finished,
            metadata: DownloadMetadata(title: id, kind: .movie, runtime: .seconds(888)),
            playback: isWatched ? DownloadPlayback(position: .seconds(880)) : nil)
    }

    @Test func eachShowsEpisodesAreListedTogetherInOrderWithTheNewestGroupFirst() {
        // Newest first, as the downloads are kept.
        let records = [
            episode("s2e1", season: 2, 1), movie("sintel"), episode("s1e3", 3),
            episode("alice", 1, seriesID: "alice", seriesName: "Alice"), episode("s1e1", 1),
            episode("special", season: 0, 1), movie("spring"), episode("unnumbered", nil),
        ]
        let groups = DownloadGroup.groups(of: records)
        #expect(groups.map(\.title) == ["Sherlock Holmes", "Movies", "Alice"])
        #expect(groups.map(\.isShow) == [true, false, true])
        // Specials come before the first season, and an episode missing its number after the rest.
        #expect(groups[0].records.map(\.id) == ["special", "s1e1", "s1e3", "s2e1", "unnumbered"])
        #expect(groups[1].records.map(\.id) == ["sintel", "spring"])
        #expect(groups[2].records.map(\.id) == ["alice"])
    }

    @Test func episodesSavedWithoutTheirShowsIDAreListedByItsName() {
        let records = [
            episode("a", 2, seriesID: nil), episode("b", 1, seriesID: nil),
            episode("c", 1, seriesID: nil, seriesName: "Alice"),
        ]
        #expect(DownloadGroup.groups(of: records).map { $0.records.map(\.id) } == [["b", "a"], ["c"]])
    }

    @Test func deleteWatchedTakesOnlyTheSavedEpisodesThatHaveBeenWatched() {
        let records = [
            episode("watched", 1, isWatched: true), episode("unwatched", 2), movie("sintel", isWatched: true),
            episode("downloading", 3, state: .downloading, isWatched: true),
        ]
        #expect(records.map(\.isWatched) == [true, false, true, true])
        #expect(DownloadGroup.watchedEpisodes(in: records).map(\.id) == ["watched"])
    }

    @Test func aWatchedDownloadSaysSoWithItsSize() {
        let watched = DownloadRow.status(of: episode("watched", 1, isWatched: true), state: .finished)
        let unwatched = DownloadRow.status(of: episode("unwatched", 2), state: .finished)
        #expect(unwatched == DownloadRow.size(640_000_000))
        #expect(watched != unwatched)
        #expect(watched.contains(unwatched))
    }
}
