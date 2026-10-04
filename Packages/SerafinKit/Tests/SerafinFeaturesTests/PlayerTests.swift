import Foundation
import JellyfinAPI
import SerafinDesign
import Testing

@testable import SerafinFeatures

@MainActor
@Suite struct PlayerScreenModelTests {
    private let screen = PlayerScreenModel()

    @Test func aTapHidesAndShowsTheControls() {
        #expect(screen.controlsVisible)
        screen.toggleControls()
        #expect(!screen.controlsVisible)
        screen.touched()
        #expect(screen.controlsVisible)
        #expect(screen.interaction == 2)
    }

    @Test func theControlsHideWhilePlaying() async {
        await screen.hideControlsLater(whilePlaying: true, after: .milliseconds(1))
        #expect(!screen.controlsVisible)
    }

    @Test func theControlsStayWhilePausedOrScrubbing() async {
        await screen.hideControlsLater(whilePlaying: false, after: .milliseconds(1))
        #expect(screen.controlsVisible)
        screen.scrubbingChanged(true)
        await screen.hideControlsLater(whilePlaying: true, after: .milliseconds(1))
        #expect(screen.controlsVisible)
    }

    @Test func anotherTouchCancelsTheWait() async {
        let wait = Task { await screen.hideControlsLater(whilePlaying: true, after: .seconds(5)) }
        wait.cancel()
        await wait.value
        #expect(screen.controlsVisible)
    }

    @Test func upNextCountsDownThenPlays() async {
        var finished = false
        await screen.runCountdown(tick: .milliseconds(1)) { finished = true }
        #expect(finished)
        #expect(screen.countdown == nil)
    }

    @Test func cancellingUpNextNeverPlays() async {
        var finished = false
        let countdown = Task { await screen.runCountdown(tick: .seconds(5)) { finished = true } }
        await Task.yield()
        countdown.cancel()
        await countdown.value
        #expect(!finished)
        #expect(screen.countdown == nil)
    }

    @Test func aDoubleTapShowsItsSideForAMoment() async {
        screen.skipped(.forward)
        #expect(screen.skip == .forward)
        #expect(screen.skipCount == 1)
        await screen.clearSkipLater(after: .milliseconds(1))
        #expect(screen.skip == nil)
    }
}

@Suite struct TrackChoicesTests {
    private let english = Locale(identifier: "en_US")

    @Test func tracksAreNamedByLanguageWithTheirFormatBeneath() throws {
        let stream = MediaStream(
            channelLayout: "5.1", codec: "eac3", index: 1, language: "eng", title: "Commentary", type: .audio)
        let choice = try #require(TrackChoices.choice(for: stream, locale: english))
        #expect(choice.id == 1)
        #expect(choice.title == "English")
        #expect(choice.detail == "Commentary · Dolby Digital Plus · 5.1")
    }

    @Test func whatATracksNameAlreadySaysIsntRepeated() throws {
        let stream = MediaStream(
            channelLayout: "5.1", codec: "aac", index: 1, language: "eng", title: "Surround 5.1", type: .audio)
        #expect(try #require(TrackChoices.choice(for: stream, locale: english)).detail == "Surround 5.1 · AAC")
    }

    @Test func forcedAndHearingImpairedSubtitlesSaySo() throws {
        let stream = MediaStream(
            codec: "subrip", index: 4, isForced: true, isHearingImpaired: true, language: "spa", type: .subtitle)
        let choice = try #require(TrackChoices.choice(for: stream, locale: english))
        #expect(choice.title == "Spanish")
        #expect(choice.detail == "Forced · SDH · SRT")
    }

    @Test func aTrackWithoutALanguageOrNameIsNumbered() throws {
        let stream = MediaStream(index: 3, type: .audio)
        #expect(try #require(TrackChoices.choice(for: stream, locale: english)).title == "Track 3")
        #expect(TrackChoices.choice(for: MediaStream(type: .audio), locale: english) == nil)
    }

    @Test func subtitlesOffReadAsNoSelection() {
        let choices = TrackChoices(
            audioStreams: [MediaStream(index: 1, type: .audio)],
            subtitleStreams: [MediaStream(index: 2, type: .subtitle)],
            selectedAudio: 1,
            selectedSubtitle: -1,
            locale: english
        )
        #expect(choices.selectedAudio == 1)
        #expect(choices.selectedSubtitle == nil)
        #expect(choices.subtitles.map(\.id) == [2])
    }

    @Test func channelLayoutsReadTheWayPeopleSayThem() {
        #expect(TrackChoices.channelsName("stereo") == "Stereo")
        #expect(TrackChoices.channelsName("5.1(side)") == "5.1")
        #expect(TrackChoices.formatName("truehd") == "Dolby TrueHD")
        #expect(TrackChoices.formatName("mystery") == "MYSTERY")
    }
}

/// A network whose cost a test can change.
@MainActor private final class Network {
    var isExpensive = false
}

@MainActor
@Suite struct PlaybackCoordinatorTests {
    private let defaults: UserDefaults

    init() throws {
        let suite = "app.getserafin.serafin.tests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    private func episode(positionTicks: Int?) throws -> MediaItem {
        let userData = UserItemDataDto(key: "key", playbackPositionTicks: positionTicks)
        let item = BaseItemDto(
            id: "aaaa1111", name: "A Scandal in Bohemia", seriesID: "bbbb2222", seriesName: "Sherlock Holmes",
            type: .episode, userData: userData)
        return try #require(MediaItem(item))
    }

    @Test func resumingStartsWhereTheServerSaysPlaybackStopped() throws {
        let item = try episode(positionTicks: 9_000_000_000)
        #expect(PlaybackCoordinator.startPosition(of: item, from: .resume) == .seconds(900))
        #expect(PlaybackCoordinator.startPosition(of: item, from: .beginning) == .zero)
        #expect(PlaybackCoordinator.startPosition(of: item, from: .position(.seconds(42))) == .seconds(42))
        #expect(PlaybackCoordinator.startPosition(of: try episode(positionTicks: nil), from: .resume) == .zero)
    }

    @Test func theStreamingCapFollowsTheNetwork() {
        let network = Network()
        let playback = PlaybackCoordinator(defaults: defaults, isOnExpensiveNetwork: { network.isExpensive })
        #expect(playback.maxBitrate == nil)
        network.isExpensive = true
        #expect(playback.maxBitrate == 8_000_000)
        defaults.set(PlaybackQuality.mbps2.rawValue, forKey: PlaybackQuality.cellularKey)
        #expect(playback.maxBitrate == 2_000_000)
    }

    @Test func withoutAnEnginePlaybackOnlyPretends() throws {
        let playback = PlaybackCoordinator(defaults: defaults, isOnExpensiveNetwork: { false })
        let item = try episode(positionTicks: nil)
        playback.play(item)
        #expect(playback.nowPlaying?.id == item.id)
        #expect(playback.isPlayerPresented)
        #expect(playback.isPlaying)
        playback.togglePlayPause()
        #expect(!playback.isPlaying)
        playback.isPlayerPresented = false
        playback.showPlayer()
        #expect(playback.isPlayerPresented)
        playback.stop()
        #expect(playback.nowPlaying == nil)
        #expect(!playback.isPlayerPresented)
    }

    @Test func thePlayerGrowsOutOfTheControlThatOpenedIt() throws {
        let playback = PlaybackCoordinator(defaults: defaults, isOnExpensiveNetwork: { false })
        let item = try episode(positionTicks: nil)
        playback.play(item, zoomSource: "hero-play-1")
        #expect(playback.zoomSource == "hero-play-1")
        // Playing on, as Up Next does, keeps the control the player came from.
        playback.play(item, zoomSource: "something-else")
        #expect(playback.zoomSource == "hero-play-1")
        // Minimizing shrinks the player back into it.
        playback.minimize()
        #expect(!playback.isPlayerPresented)
        #expect(playback.zoomSource == "hero-play-1")
        // Reopening from the mini player grows the player out of the mini player.
        playback.showPlayer()
        #expect(playback.isPlayerPresented)
        #expect(playback.zoomSource == PlaybackCoordinator.miniPlayerZoomSource)
    }

    @Test func stoppingDoesntShrinkIntoTheVanishingMiniPlayer() throws {
        let playback = PlaybackCoordinator(defaults: defaults, isOnExpensiveNetwork: { false })
        playback.play(try episode(positionTicks: nil))
        playback.minimize()
        playback.showPlayer()
        playback.stop()
        #expect(playback.zoomSource == nil)
        #expect(playback.nowPlaying == nil)
        #expect(!playback.isPlayerPresented)
    }

    @Test func showsAndSeasonsDontPlayThemselves() throws {
        let playback = PlaybackCoordinator(defaults: defaults, isOnExpensiveNetwork: { false })
        let show = try #require(MediaItem(BaseItemDto(id: "cccc3333", name: "Sherlock Holmes", type: .series)))
        playback.play(show)
        #expect(playback.nowPlaying == nil)
        #expect(!playback.isPlayerPresented)
    }
}

@Suite struct PlaybackQualityTests {
    @Test func aCapNobodyPickedIsTheDefault() throws {
        let defaults = try #require(UserDefaults(suiteName: "app.getserafin.serafin.tests.\(UUID().uuidString)"))
        #expect(PlaybackQuality.saved(onCellular: false, in: defaults) == .maximum)
        #expect(PlaybackQuality.saved(onCellular: true, in: defaults) == .mbps8)
        defaults.set(PlaybackQuality.mbps20.rawValue, forKey: PlaybackQuality.wifiKey)
        #expect(PlaybackQuality.saved(onCellular: false, in: defaults) == .mbps20)
        defaults.set(123, forKey: PlaybackQuality.wifiKey)
        #expect(PlaybackQuality.saved(onCellular: false, in: defaults) == .maximum)
    }
}

@Suite struct PlaybackDeliveryTests {
    @Test func eachMethodHasItsDelivery() {
        #expect(PlaybackDelivery(.directPlay) == .directPlay)
        #expect(PlaybackDelivery(.directStream) == .repackaged)
        #expect(PlaybackDelivery(.transcode) == .transcoding)
    }
}
