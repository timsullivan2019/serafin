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
        #expect(DownloadCenter.state(of: record(.downloading), progress: progress) == .downloading(0.25))
        #expect(DownloadCenter.state(of: record(.downloading), progress: [:]) == .downloading(nil))
        #expect(DownloadCenter.state(of: record(.finished), progress: progress) == .finished)
        #expect(
            DownloadCenter.state(of: record(.failed, failure: .notAllowed), progress: progress) == .failed(.notAllowed))
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
}
