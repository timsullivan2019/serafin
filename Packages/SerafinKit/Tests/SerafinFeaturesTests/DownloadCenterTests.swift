import Foundation
import SerafinCore
import SerafinDesign
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
    }
}
