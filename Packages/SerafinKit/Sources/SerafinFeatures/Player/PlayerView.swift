import JellyfinAPI
import SerafinCore
import SerafinDesign
import SerafinPlayback
import SwiftUI

/// The full-screen player: the video under glass controls, double-tap skipping, pinching to fill the screen or fit
/// it, the audio and subtitle picker, skipping the stretches the server marked, and the next episode's card over the
/// credits and as an episode ends. On iPhone the interface turns to landscape while it shows.
struct PlayerView: View {
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if let item = playback.nowPlaying {
                #if os(iOS)
                    if let engine = playback.engine {
                        EnginePlayer(engine: engine, item: item)
                    } else {
                        PretendPlayer(item: item)
                    }
                #else
                    PretendPlayer(item: item)
                #endif
            }
        }
        .persistentSystemOverlays(.hidden)
        #if os(iOS)
            .statusBarHidden()
            .onAppear { InterfaceOrientations.playerAppeared() }
            .onDisappear { InterfaceOrientations.playerDisappeared() }
        #endif
    }
}

#if os(iOS)
    /// The player for the signed-in account's engine.
    private struct EnginePlayer: View {
        let engine: PlayerEngine
        let item: MediaItem
        @Environment(PlaybackCoordinator.self) private var playback
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
        @Environment(\.artwork) private var artwork
        @Environment(\.displayScale) private var displayScale
        @State private var screen = PlayerScreenModel()
        @State private var showsTracks = false
        /// The next episode's thumbnail and the tint taken from it, once loaded.
        @State private var nextArtwork: NextEpisodeArtwork?

        /// What restarts the wait before the controls hide: a touch, a change in playback, or the picker closing.
        private struct HideTrigger: Equatable {
            let interaction: Int
            let state: PlaybackState
            let showsTracks: Bool
        }

        /// What decides the offer for the stretch the server marked at the playback position.
        private struct SegmentInputs: Equatable {
            let position: Duration
            let segments: [PlaybackSegment]
            let itemID: String?
            let hasNextEpisode: Bool
        }

        /// What decides whether the next episode's card shows.
        private struct NextEpisodeInputs: Equatable {
            let position: Duration
            let duration: Duration
            let segments: [PlaybackSegment]
            let itemID: String?
            let hasNextEpisode: Bool
            let hasEnded: Bool
        }

        /// Whether the next episode's countdown runs: while playback runs or has ended, and not while it's paused or a
        /// finger is on the scrubber.
        private var countdownRuns: Bool {
            (engine.state == .playing || engine.state == .ended) && !screen.isScrubbing
        }

        /// The next episode's card, while it's offered after the episode this screen shows. Tied to that episode, so
        /// the card goes in the same update that shows the next episode's title.
        private var nextEpisode: NextEpisodePrompt? {
            guard let offered = screen.nextEpisodeOffer, offered == item.id, offered == engine.item?.id,
                let next = engine.nextItem.flatMap(MediaItem.init)
            else { return nil }
            let artwork = nextArtwork?.itemID == next.id ? nextArtwork : nil
            return NextEpisodePrompt(
                card: next.card,
                artwork: artwork?.image,
                tint: artwork?.tint ?? ArtworkTint.neutral,
                countdown: screen.countdown,
                secondsLeft: screen.secondsLeft
            )
        }

        /// The skip pill, or the notice that a stretch was skipped by itself.
        private var segmentPrompt: SegmentPrompt? {
            if let notice = screen.skippedNotice {
                return .skipped(notice)
            }
            guard case .offer(let segment) = screen.segmentAction else { return nil }
            return .skip(SkipSegmentButton.Kind(segment.kind))
        }

        var body: some View {
            ZStack {
                PlayerSurface(engine: engine)
                    .ignoresSafeArea()
                PlayerGestures(screen: screen, engine: engine)
                SkipFlash(screen: screen)
                overlay
            }
            .animation(
                Motion.animation(.easeInOut(duration: 0.25), reduceMotion: reduceMotion), value: screen.controlsVisible
            )
            .sheet(isPresented: $showsTracks, onDismiss: { screen.touched() }) {
                tracks
            }
            .task(id: HideTrigger(interaction: screen.interaction, state: engine.state, showsTracks: showsTracks)) {
                // VoiceOver users keep the controls, as in the system player.
                await screen.hideControlsLater(whilePlaying: engine.state == .playing && !showsTracks && !voiceOver)
            }
            .task(id: screen.skipCount) {
                guard screen.skip != nil else { return }
                await screen.clearSkipLater()
            }
            .task(id: screen.countdown) {
                await screen.tickCountdown { playNext() }
            }
            .task(id: engine.nextItem?.id) {
                guard let next = engine.nextItem else { return }
                nextArtwork = await NextEpisodeArtwork.load(next, artwork: artwork, scale: displayScale)
            }
            .task(id: screen.noticeCount) {
                guard screen.skippedNotice != nil else { return }
                await screen.clearNoticeLater()
            }
            .onChange(
                of: SegmentInputs(
                    position: engine.elapsed, segments: engine.segments, itemID: engine.item?.id,
                    hasNextEpisode: engine.nextItem != nil),
                initial: true
            ) { _, inputs in
                let skipped = screen.updateSegment(
                    at: inputs.position, in: inputs.segments, itemID: inputs.itemID,
                    automatic: AutomaticSkips.kinds(in: .standard), hasNextEpisode: inputs.hasNextEpisode)
                guard let skipped else { return }
                AccessibilityNotification.Announcement(SkipSegmentButton.Kind(skipped.kind).skippedTitle).post()
                Task { await engine.seek(to: skipped.skipTarget) }
            }
            .onChange(
                of: NextEpisodeInputs(
                    position: engine.elapsed, duration: engine.duration, segments: engine.segments,
                    itemID: engine.item?.id, hasNextEpisode: engine.nextItem != nil, hasEnded: engine.state == .ended),
                initial: true
            ) { _, inputs in
                screen.updateNextEpisode(
                    at: inputs.position, duration: inputs.duration, segments: inputs.segments, itemID: inputs.itemID,
                    hasNextEpisode: inputs.hasNextEpisode, hasEnded: inputs.hasEnded,
                    countsDown: engine.playsNextEpisodeAutomatically, countdownRuns: countdownRuns)
            }
            .onChange(of: countdownRuns) { _, runs in
                screen.setCountdownRunning(runs)
            }
            .onChange(of: engine.state) { _, state in
                // A movie, a last episode or an episode whose next one was put away closes the player at the end;
                // otherwise the next episode's card stays.
                if state == .ended, engine.nextItem == nil || screen.hasCancelledNextEpisode(after: engine.item?.id) {
                    playback.stop()
                }
            }
        }

        /// Plays the next episode as a cut: the card goes, the old picture with it, and the next episode's title and
        /// loading show in the same frame, with nothing animating across it, so no frame has one episode's title with
        /// the other's card.
        private func playNext() {
            var cut = Transaction()
            cut.disablesAnimations = true
            withTransaction(cut) {
                screen.handOff()
                playback.playNext()
            }
        }

        /// Puts the next episode's card away; at the end of the episode, that closes the player.
        private func cancelNextEpisode() {
            screen.cancelNextEpisode()
            if engine.state == .ended {
                playback.stop()
            }
        }

        @ViewBuilder private var overlay: some View {
            if engine.state == .failed {
                PlayerFailure(error: engine.failure)
            } else {
                ZStack {
                    if engine.isBuffering, !screen.controlsVisible {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                            .allowsHitTesting(false)
                    }
                    controls
                }
            }
        }

        private var controls: some View {
            PlayerControls(
                title: item.card.title,
                subtitle: item.card.eyebrowText,
                status: PlayerControlsStatus(
                    isPlaying: engine.state == .playing,
                    isBuffering: engine.isBuffering,
                    elapsed: engine.elapsed,
                    duration: engine.duration,
                    buffered: engine.buffered,
                    rate: engine.rate
                ),
                showsPictureInPicture: engine.isPictureInPicturePossible,
                fillsScreen: engine.fillsScreen,
                showsControls: screen.controlsVisible,
                segmentPrompt: segmentPrompt,
                nextEpisode: nextEpisode,
                actions: PlayerControlActions(
                    minimize: { playback.dismissPlayer() },
                    playPause: {
                        screen.touched()
                        playback.togglePlayPause()
                    },
                    skipBackward: {
                        screen.touched()
                        Task { await engine.skip(by: -10) }
                    },
                    skipForward: {
                        screen.touched()
                        Task { await engine.skip(by: 10) }
                    },
                    // Started at once, so the position moves in the same frame the scrubber lets go.
                    seek: { position in Task.immediate { await engine.seek(to: position) } },
                    scrubbingChanged: { screen.scrubbingChanged($0) },
                    setRate: { rate in
                        screen.touched()
                        engine.setRate(rate)
                    },
                    showTracks: { showsTracks = true },
                    togglePictureInPicture: { engine.togglePictureInPicture() },
                    toggleFill: {
                        screen.touched()
                        engine.setFillsScreen(!engine.fillsScreen, animated: !reduceMotion)
                    },
                    skipSegment: {
                        guard case .offer(let segment) = screen.segmentAction else { return }
                        screen.dismiss(segment)
                        Task { await engine.seek(to: segment.skipTarget) }
                    },
                    playNextEpisode: { playNext() },
                    cancelNextEpisode: { cancelNextEpisode() }
                )
            ) {
                AirPlayButton()
            }
        }

        @ViewBuilder private var tracks: some View {
            if let plan = engine.plan {
                let choices = TrackChoices(
                    plan: plan,
                    subtitles: engine.subtitleSelection,
                    pending: engine.pendingSubtitleSelection,
                    generated: engine.generatedSubtitles
                )
                TrackPicker(
                    delivery: PlaybackDelivery(plan.method),
                    audio: choices.audio,
                    selectedAudio: choices.selectedAudio,
                    subtitles: choices.subtitles,
                    generatedSubtitles: choices.generatedSubtitles,
                    selectedSubtitles: choices.selectedSubtitles,
                    pendingSubtitles: choices.pendingSubtitles,
                    selectAudio: { index in Task { await engine.selectAudio(index) } },
                    selectSubtitles: { pick in Task { await engine.selectSubtitles(TrackChoices.selection(pick)) } }
                )
                .scrollIndicators(.never)
                .presentationDetents([.medium, .large])
                // The player is always dark, so its sheet is too.
                .preferredColorScheme(.dark)
            }
        }
    }

    /// Taps and swipes on the video: a tap shows or hides the controls, a double tap on either half skips 10
    /// seconds that way, and a swipe down puts the player away, into Picture in Picture while it plays.
    private struct PlayerGestures: View {
        let screen: PlayerScreenModel
        let engine: PlayerEngine
        @Environment(PlaybackCoordinator.self) private var playback
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var width: CGFloat = 0

        var body: some View {
            Color.clear
                .contentShape(.rect)
                .ignoresSafeArea()
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    width = $0
                }
                .gesture(
                    SpatialTapGesture(count: 2)
                        .onEnded { value in skip(at: value.location.x) }
                        .exclusively(before: TapGesture().onEnded { screen.toggleControls() })
                )
                // Pinching out fills the screen with the picture and pinching in fits it again, as in other players.
                .simultaneousGesture(
                    MagnifyGesture()
                        .onEnded { value in
                            if value.magnification > 1.1, !engine.fillsScreen {
                                engine.setFillsScreen(true, animated: !reduceMotion)
                            } else if value.magnification < 0.9, engine.fillsScreen {
                                engine.setFillsScreen(false, animated: !reduceMotion)
                            }
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40)
                        .onEnded { value in
                            let down = value.translation.height
                            if down > 120, abs(value.translation.width) < down {
                                playback.dismissPlayer()
                            }
                        }
                )
                .accessibilityHidden(true)
        }

        private func skip(at x: CGFloat) {
            let direction: SkipIndicator.Direction = x < width / 2 ? .backward : .forward
            screen.skipped(direction)
            Task { await engine.skip(by: direction == .backward ? -10 : 10) }
        }
    }

    /// The glass circle that flashes on the side a double tap skipped.
    private struct SkipFlash: View {
        let screen: PlayerScreenModel
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            GlassEffectContainer {
                HStack {
                    if screen.skip == .backward {
                        SkipIndicator(.backward)
                    }
                    Spacer()
                    if screen.skip == .forward {
                        SkipIndicator(.forward)
                    }
                }
            }
            .padding(.horizontal, Spacing.xLarge * 2)
            .allowsHitTesting(false)
            .animation(Motion.animation(reduceMotion: reduceMotion), value: screen.skip)
        }
    }

    /// The next episode's thumbnail on its card, and the tint taken from it for Play Now.
    private struct NextEpisodeArtwork {
        let itemID: String
        let image: Image
        let tint: Color

        /// Loads `item`'s thumbnail at the card's size, or nil when there's none to show.
        static func load(_ item: BaseItemDto, artwork: Artwork?, scale: CGFloat) async -> NextEpisodeArtwork? {
            guard let id = item.id, let artwork,
                let request = artwork.request(
                    .landscape, of: item, width: NextEpisodeCard.thumbnailWidth, scale: scale),
                let loaded = try? await artwork.pipeline.image(for: request),
                let bitmap = loaded.bitmap
            else { return nil }
            return NextEpisodeArtwork(itemID: id, image: Image(uiImage: loaded), tint: ArtworkTint.color(for: bitmap))
        }
    }

    /// Why playback failed, with Try Again and a way out.
    private struct PlayerFailure: View {
        let error: (any Error)?
        @Environment(PlaybackCoordinator.self) private var playback

        var body: some View {
            let message = UserMessage(error ?? PlaybackError.playerFailed)
            VStack(spacing: Spacing.medium) {
                ErrorState(message.title, message: message.message, systemImage: message.systemImage) {
                    playback.retry()
                }
                Button(String(localized: "Close", bundle: .module, comment: "Button that closes the player.")) {
                    playback.stop()
                }
                .buttonStyle(.glass)
            }
            .padding(Spacing.large)
            .environment(\.colorScheme, .dark)
        }
    }
#endif

/// The controls over black, for previews and anywhere without an engine.
private struct PretendPlayer: View {
    let item: MediaItem
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        let card = item.card
        PlayerControls(
            title: card.title,
            subtitle: card.eyebrowText,
            status: PlayerControlsStatus(
                isPlaying: playback.isPlaying,
                elapsed: (card.runtime ?? .zero) * card.progress,
                duration: card.runtime ?? .zero
            ),
            actions: PlayerControlActions(
                minimize: { playback.dismissPlayer() },
                playPause: { playback.togglePlayPause() }
            )
        )
    }
}

#Preview {
    let playback = PlaybackCoordinator()
    playback.play(MediaItem(card: MockMedia.movies[1], source: nil))
    return PlayerView()
        .environment(playback)
}
