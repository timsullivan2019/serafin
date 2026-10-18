import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

private let key = SessionKey(serverID: "server", userID: "user")

/// A finished download as the device saved it.
private func record(
    _ itemID: String, _ metadata: DownloadMetadata, playback: DownloadPlayback? = nil
) -> DownloadRecord {
    DownloadRecord(
        key: key, itemID: itemID, mediaSourceID: itemID, fileExtension: "mp4", state: .finished, metadata: metadata,
        playback: playback)
}

/// An episode of a show as shown from what was saved with its download.
private func episode(
    _ number: Int, season: Int = 1, seriesID: String? = "show1111", seriesName: String = "Sherlock Holmes"
) -> MediaItem {
    let metadata = DownloadMetadata(
        title: "Episode \(number)", kind: .episode, seriesID: seriesID, seriesName: seriesName, seasonNumber: season,
        episodeNumber: number)
    return MediaItem(
        download: record("\(seriesID ?? seriesName)-s\(season)e\(number)", metadata), artwork: SavedArtwork())
}

/// The fifteen-minute movie Sintel as shown from its download, stopped at `position`, and marked watched or not as
/// `isPlayed` says, or for nil, as the stop counts.
private func sintel(at position: Duration? = nil, isPlayed: Bool? = nil) throws -> MediaItem {
    let card = try #require(MockMedia.movies.first { $0.id == "movie-sintel" })
    let playback = position.map { DownloadPlayback(position: $0, isPlayed: isPlayed) }
    return MediaItem(download: record(card.id, DownloadMetadata(card), playback: playback), artwork: SavedArtwork())
}

@Suite struct SavedDownloadTests {
    @Test func aDownloadedMovieShowsWhatWasSavedWithIt() {
        let metadata = DownloadMetadata(
            title: "Sintel", kind: .movie, runtime: .seconds(888), year: 2010, rating: "PG-13",
            overview: "A young woman crosses a frozen wilderness.")
        let poster = URL(filePath: "/Downloads/Artwork/download-poster")
        let item = MediaItem(
            download: record("aaaa1111", metadata, playback: DownloadPlayback(position: .seconds(444))),
            artwork: SavedArtwork(poster: poster))

        #expect(item.isSaved)
        #expect(item.id == "aaaa1111")
        #expect(item.card.kind == .movie)
        #expect(item.card.title == "Sintel")
        #expect(item.card.year == 2010)
        #expect(item.card.runtime == .seconds(888))
        #expect(item.card.rating == "PG-13")
        #expect(item.card.overview == "A young woman crosses a frozen wilderness.")
        #expect(item.card.progress == 0.5)
        #expect(!item.card.isPlayed)
        #expect(item.savedArtwork?.url(for: .poster) == poster)
        #expect(item.savedArtwork?.url(for: .backdrop) == nil)
        // The player takes an item from what was saved, with nothing that needs the server, such as picture tags.
        #expect(item.source?.id == "aaaa1111")
        #expect(item.source?.type == .movie)
        #expect(item.source?.runTimeTicks == 888 * 10_000_000)
        #expect(item.source?.productionYear == 2010)
        #expect(item.source?.imageTags == nil)
    }

    @Test func aDownloadedEpisodeKeepsItsShowAndNumbers() {
        let item = episode(3)
        #expect(item.card.kind == .episode)
        #expect(
            item.card.episode
                == MediaCard.EpisodeInfo(
                    seriesID: "show1111", seriesTitle: "Sherlock Holmes", seasonNumber: 1, episodeNumber: 3))
        #expect(item.source?.type == .episode)
        #expect(item.source?.seriesID == "show1111")
        #expect(item.source?.seriesName == "Sherlock Holmes")
        #expect(item.source?.parentIndexNumber == 1)
        #expect(item.source?.indexNumber == 3)
    }

    @Test func aStopNearTheEndShowsAsWatched() throws {
        let item = try sintel(at: .seconds(14 * 60 + 30))
        #expect(item.card.isWatched)
        #expect(item.card.progress == 0)
    }

    @Test func aMarkMadeWithNoServerSaysWhetherItsWatched() throws {
        #expect(try sintel(at: .zero, isPlayed: true).card.isWatched)
        // Marked unwatched after a stop near the end.
        let unwatched = try sintel(at: .seconds(14 * 60 + 30), isPlayed: false)
        #expect(!unwatched.card.isPlayed)
        #expect(unwatched.card.progress == 0)
    }

    @Test func aDownloadNotYetPlayedHasNoProgress() throws {
        let item = try sintel()
        #expect(item.card.progress == 0)
        #expect(!item.card.isPlayed)
    }

    @Test func eachPictureFillsTheRolesOfItsShape() {
        let poster = URL(filePath: "/poster")
        let backdrop = URL(filePath: "/backdrop")
        let artwork = SavedArtwork(poster: poster, backdrop: backdrop)
        #expect(artwork.url(for: .poster) == poster)
        #expect(artwork.url(for: .backdrop) == backdrop)
        #expect(artwork.url(for: .landscape) == backdrop)
        #expect(artwork.url(for: .watching) == backdrop)
        #expect(artwork.url(for: .logo) == nil)
        #expect(DownloadArtwork.poster.role == .poster)
        #expect(DownloadArtwork.backdrop.role == .backdrop)
    }

    @Test func aDownloadKeepsWhatItsPageShows() throws {
        var card = try #require(MockMedia.episodes.first)
        card.rating = "TV-PG"
        let metadata = DownloadMetadata(card)
        #expect(metadata.seriesID == card.episode?.seriesID)
        #expect(metadata.rating == "TV-PG")
        #expect(metadata.overview == card.overview)
    }

    @Test func whereTheServerSaysPlaybackStoppedIsKeptWithTheDownload() throws {
        let lastPlayed = Date(timeIntervalSince1970: 1_790_000_000)
        let started = try #require(
            MediaItem(
                BaseItemDto(
                    id: "aaaa1111", name: "Sintel", runTimeTicks: 888 * 10_000_000, type: .movie,
                    userData: UserItemDataDto(
                        key: "aaaa1111", lastPlayedDate: lastPlayed, playbackPositionTicks: 600 * 10_000_000))))
        #expect(
            DownloadCenter.serverPlayback(of: started)
                == DownloadPlayback(position: .seconds(600), changed: lastPlayed, isPlayed: false))

        let watched = try #require(
            MediaItem(
                BaseItemDto(
                    id: "cccc3333", name: "Big Buck Bunny", type: .movie,
                    userData: UserItemDataDto(isPlayed: true, key: "cccc3333", lastPlayedDate: lastPlayed))))
        let server = try #require(DownloadCenter.serverPlayback(of: watched))
        #expect(server.isPlayed(runtime: .seconds(596)))
        #expect(server.resumePosition(runtime: .seconds(596)) == .zero)

        let unstarted = try #require(MediaItem(BaseItemDto(id: "bbbb2222", name: "Spring", type: .movie)))
        #expect(DownloadCenter.serverPlayback(of: unstarted) == nil)
    }
}

@Suite struct SavedDetailsTests {
    @Test func aMoviesPageShowsTheMovieAndPlaysIt() throws {
        let movie = try sintel()
        let details = try #require(ItemDetails.saved(movie.id, among: [movie, episode(1)]))
        #expect(details.item == movie)
        #expect(details.playable == movie)
        #expect(details.seasonEpisodes.isEmpty)
    }

    @Test func anEpisodesPageListsTheOtherDownloadedEpisodesOfItsSeasonInOrder() throws {
        let third = episode(3)
        let downloads = [episode(5), third, episode(2, season: 2), episode(1), episode(4, seriesID: "show2222")]
        let details = try #require(ItemDetails.saved(third.id, among: downloads))
        #expect(details.item == third)
        #expect(details.seasonEpisodes.map(\.card.episode?.episodeNumber) == [1, 5])
        #expect(details.seasonEpisodes.allSatisfy { $0.card.episode?.seriesID == "show1111" })
    }

    @Test func episodesSavedWithoutTheirShowsIDMatchByItsName() throws {
        let first = episode(1, seriesID: nil)
        let downloads = [first, episode(2, seriesID: nil), episode(3, seriesID: nil, seriesName: "Alice")]
        let details = try #require(ItemDetails.saved(first.id, among: downloads))
        #expect(details.seasonEpisodes.map(\.card.title) == ["Episode 2"])
    }

    @Test func anItemThatIsntDownloadedHasNoSavedPage() throws {
        #expect(ItemDetails.saved("movie-spring", among: [try sintel()]) == nil)
    }
}

@Suite struct NextDownloadedEpisodeTests {
    /// A downloaded episode without an episode number, as one the server hadn't numbered.
    private let unnumbered = MediaItem(
        download: record(
            "show1111-pilot",
            DownloadMetadata(
                title: "Unaired Pilot", kind: .episode, seriesID: "show1111", seriesName: "Sherlock Holmes",
                seasonNumber: 1)),
        artwork: SavedArtwork())

    @Test func theNextOneIsTheShowsNextDownloadedByNumberAcrossSeasons() {
        let special = episode(1, season: 0)
        let downloads = [
            episode(1, season: 2), episode(5), episode(3), episode(4, seriesID: "show2222"), episode(1), special,
            unnumbered,
        ]
        #expect(episode(3).nextEpisode(among: downloads) == episode(5))
        #expect(episode(5).nextEpisode(among: downloads) == episode(1, season: 2))
        #expect(episode(1, season: 2).nextEpisode(among: downloads) == nil)
        // Specials come before the first season.
        #expect(special.nextEpisode(among: downloads) == episode(1))
    }

    @Test func episodesSavedWithoutTheirShowsIDFollowByItsName() {
        let downloads = [
            episode(1, seriesID: nil), episode(3, seriesID: nil), episode(2, seriesID: nil, seriesName: "Alice"),
        ]
        #expect(episode(1, seriesID: nil).nextEpisode(among: downloads) == episode(3, seriesID: nil))
    }

    @Test func onlyAnEpisodeWithBothNumbersHasANextOne() throws {
        let downloads = [episode(1), episode(2), unnumbered, try sintel()]
        #expect(unnumbered.nextEpisode(among: downloads) == nil)
        #expect(try sintel().nextEpisode(among: downloads) == nil)
    }

    @Test func theEpisodeTakenFromTheDownloadsShowsWithWhatWasSavedWithIt() throws {
        let second = episode(2)
        let saved = try #require(second.source)
        #expect(PlaybackCoordinator.item(for: saved, among: [episode(1), second]) == second)
        // The server's description of the same episode, as when the server named it, shows as the server has it.
        var server = saved
        server.userData = UserItemDataDto(isPlayed: true, key: "show1111-s1e2")
        let item = PlaybackCoordinator.item(for: server, among: [second])
        #expect(item?.isSaved == false)
        #expect(item?.card.isPlayed == true)
    }
}

@Suite struct DownloadArtworkSizesTests {
    @Test func aPhonesPicturesAreAsWideAsItsScreenDrawsThem() {
        let sizes = DownloadArtworkSizes(screen: CGSize(width: 440, height: 956), scale: 3)
        // A poster as wide as one column of posters across the screen.
        #expect(sizes.poster == 440 - Spacing.medium * 2)
        // Upright at the largest text sizes, the hero is 77% of the screen's height, and a 16:9 backdrop filling it
        // is wider than the screen.
        #expect(abs(sizes.backdrop - 956 * 0.77 * 16 / 9) < 0.01)
        #expect(sizes.width(of: .poster) == sizes.poster)
        #expect(sizes.width(of: .backdrop) == sizes.backdrop)
        #expect(sizes.scale == 3)
    }

    @Test func aTabletsPosterStopsAtTheWidestCard() {
        let sizes = DownloadArtworkSizes(screen: CGSize(width: 1376, height: 1032), scale: 2)
        #expect(sizes.poster == DownloadArtworkSizes.posterLimit)
        // A regular width's hero is 62% of the screen's height at the largest text sizes, tallest held upright.
        #expect(abs(sizes.backdrop - 1376 * 0.62 * 16 / 9) < 0.01)
    }
}

@MainActor @Suite struct OfflineDownloadsHomeTests {
    @Test func withNoConnectionHomeIsOfflineEvenBeforeALoadFails() {
        let model = HomeModel()
        #expect(model.failure == nil)
        #expect(model.offlineReason(isOnline: true) == nil)
        #expect(model.offlineReason(isOnline: false) == UserMessage(SerafinError.offline))
    }

    @Test func aFailedLoadSaysWhyTheServerCantBeReached() async throws {
        let model = HomeModel()
        let saved = HomeContent(continueWatching: [try sintel()], nextUp: [], latest: [])
        await model.load(from: TestMediaSource(saved: saved, homeFailure: .serverUnreachable))
        #expect(model.failure?.title == "Can't Reach the Server")
        #expect(model.offlineReason(isOnline: true)?.title == "Can't Reach the Server")
        // With no connection at all, that's the reason given.
        #expect(model.offlineReason(isOnline: false)?.title == "You're Offline")

        await model.load(from: TestMediaSource())
        #expect(model.failure == nil)
        #expect(model.offlineReason(isOnline: true) == nil)
    }

    @Test func withNothingSavedTheFailureIsTheReason() async {
        let model = HomeModel()
        await model.load(from: TestMediaSource(homeFailure: .serverUnreachable))
        #expect(model.offlineReason(isOnline: true)?.title == "Can't Reach the Server")
    }

    @Test func theBannerSaysTheDownloadsStillPlay() {
        #expect(
            HomeNoticeBanner.announcement(UserMessage(SerafinError.offline), detail: HomeDownloads.detail)
                == "You're Offline. Your downloads still play.")
    }
}

@MainActor @Suite struct SavedDetailsPageTests {
    @Test func aDownloadsPageShowsWhatWasSavedWhenTheServerCantBeReached() async throws {
        let movie = try sintel()
        let model = ItemDetailModel(id: movie.id)
        await model.load(from: TestMediaSource(detailsFailure: .offline, downloaded: [movie]))
        #expect(model.details?.item == movie)
        #expect(model.showsSavedDetails)
    }

    @Test func aPageForSomethingNotDownloadedSaysWhy() async {
        let model = ItemDetailModel(id: "movie-sintel")
        await model.load(from: TestMediaSource(detailsFailure: .offline))
        guard case .failed(let message) = model.phase else {
            Issue.record("The page should say it can't load.")
            return
        }
        #expect(message.title == "You're Offline")
        #expect(!model.showsSavedDetails)
    }

    @Test func aPageOpenedFromADownloadShowsItAtOnceWhileTheServerIsAsked() async throws {
        let movie = try sintel()
        let model = ItemDetailModel(id: movie.id, preview: movie)
        let media = TestMediaSource(detailsDelay: .seconds(30), downloaded: [movie])
        let loading = Task { await model.load(from: media) }
        defer { loading.cancel() }
        try await waitUntil { model.showsSavedDetails }
        #expect(model.details?.item == movie)
    }

    @Test func aSlowServerShowsWhatWasSavedAfterAMoment() async throws {
        let movie = try sintel()
        let model = ItemDetailModel(id: movie.id)
        model.savedDetailsWait = .milliseconds(20)
        let media = TestMediaSource(detailsDelay: .seconds(30), downloaded: [movie])
        let loading = Task { await model.load(from: media) }
        defer { loading.cancel() }
        try await waitUntil { model.showsSavedDetails }
        #expect(model.details?.item == movie)
    }

    @Test func theServersDetailsReplaceWhatWasSavedOnceTheyArrive() async throws {
        let movie = try sintel()
        let model = ItemDetailModel(id: movie.id, preview: movie)
        await model.load(from: TestMediaSource(detailsDelay: .milliseconds(50), downloaded: [movie]))
        #expect(!model.showsSavedDetails)
        #expect(model.details?.item.isSaved == false)
        #expect(model.details?.item.id == movie.id)
    }

    @Test func aDeletedDownloadsPageSaysItCantLoad() async throws {
        let movie = try sintel()
        let model = ItemDetailModel(id: movie.id)
        await model.load(from: TestMediaSource(detailsFailure: .offline, downloaded: [movie]))
        #expect(model.showsSavedDetails)

        await model.load(from: TestMediaSource(detailsFailure: .offline))
        #expect(model.details == nil)
        #expect(!model.showsSavedDetails)
    }

    @Test func aReloadShowsAMarkMadeWithNoServerAtOnce() async throws {
        let unwatched = try sintel()
        let model = ItemDetailModel(id: unwatched.id)
        await model.load(from: TestMediaSource(detailsFailure: .offline, downloaded: [unwatched]))
        #expect(model.details?.item.card.isWatched == false)

        // Marked watched, it shows as watched without waiting for the server, which is slow to answer.
        let watched = try sintel(at: .zero, isPlayed: true)
        let media = TestMediaSource(detailsDelay: .seconds(30), downloaded: [watched])
        let reloading = Task { await model.load(from: media) }
        defer { reloading.cancel() }
        try await waitUntil { model.details?.item.card.isWatched == true }
        #expect(model.showsSavedDetails)
    }

    @Test func theServersDetailsStayWhenAReloadFails() async throws {
        let movie = try sintel()
        let model = ItemDetailModel(id: movie.id)
        await model.load(from: TestMediaSource(downloaded: [movie]))
        #expect(model.details?.item.isSaved == false)

        await model.load(from: TestMediaSource(detailsFailure: .offline, downloaded: [movie]))
        #expect(model.details?.item.isSaved == false)
        #expect(!model.showsSavedDetails)
    }

    /// Waits, a few seconds at most, until `condition` holds.
    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}
