import SerafinCore
import SerafinDesign
import SerafinPlayback
import SwiftUI

/// The full-screen player: the video under glass controls, double-tap skipping, pinching to fill the screen or fit
/// it, the audio and subtitle picker, and Up Next when an episode ends. On iPhone the interface turns to landscape
/// while it shows.
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
        @State private var screen = PlayerScreenModel()
        @State private var showsTracks = false

        /// What restarts the wait before the controls hide: a touch, a change in playback, or the picker closing.
        private struct HideTrigger: Equatable {
            let interaction: Int
            let state: PlaybackState
            let showsTracks: Bool
        }

        private var isUpNext: Bool {
            engine.state == .ended && engine.nextItem != nil
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
            .task(id: isUpNext) {
                guard isUpNext else {
                    screen.cancelCountdown()
                    return
                }
                await screen.runCountdown { playback.playNext() }
            }
            .onChange(of: engine.state) { _, state in
                // A movie or a last episode closes the player at the end; an episode with a next one shows Up Next.
                if state == .ended, engine.nextItem == nil {
                    playback.stop()
                }
            }
        }

        @ViewBuilder private var overlay: some View {
            if engine.state == .failed {
                PlayerFailure(error: engine.failure)
            } else if isUpNext, let next = engine.nextItem.flatMap(MediaItem.init) {
                UpNext(next: next, secondsLeft: screen.countdown ?? PlayerScreenModel.countdownSeconds)
            } else {
                ZStack {
                    if engine.isBuffering, !screen.controlsVisible {
                        ProgressView()
                            .controlSize(.large)
                            .tint(.white)
                            .allowsHitTesting(false)
                    }
                    // Hidden controls fade out but stay in place, so a menu open on one of them stays usable.
                    controls
                        .opacity(screen.controlsVisible ? 1 : 0)
                        .allowsHitTesting(screen.controlsVisible)
                        .accessibilityHidden(!screen.controlsVisible)
                }
                // Outside the controls, so the offer to skip stays while they're hidden.
                .overlay(alignment: .bottomTrailing) { skipPill }
            }
        }

        /// Skip Intro and its kin, while the server's marked stretch plays.
        private var skipPill: some View {
            let segment = PlaybackSegment.skippable(at: engine.elapsed, in: engine.segments)
            return SkipPill(segment.map { SkipPill.Kind($0.kind) }) {
                guard let segment else { return }
                Task { await engine.seek(to: segment.end) }
            }
            .padding(.trailing, Spacing.medium)
            .padding(.bottom, PlayerLayout.bottomBarClearance)
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
                    seek: { position in Task { await engine.seek(to: position) } },
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
                    }
                )
            ) {
                AirPlayButton()
            }
        }

        @ViewBuilder private var tracks: some View {
            if let plan = engine.plan {
                let choices = TrackChoices(plan: plan)
                TrackPicker(
                    delivery: PlaybackDelivery(plan.method),
                    audio: choices.audio,
                    selectedAudio: choices.selectedAudio,
                    subtitles: choices.subtitles,
                    selectedSubtitle: choices.selectedSubtitle,
                    selectAudio: { index in Task { await engine.selectAudio(index) } },
                    selectSubtitle: { index in Task { await engine.selectSubtitle(index) } }
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

    /// The next episode with its countdown, over the last frame of the one that ended.
    private struct UpNext: View {
        let next: MediaItem
        let secondsLeft: Int
        @Environment(PlaybackCoordinator.self) private var playback

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                ItemArtwork(next, role: .landscape) { image in
                    UpNextCard(
                        card: next.card,
                        artwork: image,
                        secondsLeft: secondsLeft,
                        playNow: { playback.playNext() },
                        cancel: { playback.stop() }
                    )
                }
                .fixedSize()
                .padding(Spacing.large)
            }
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

extension SkipPill.Kind {
    /// The pill for a stretch the server marked.
    init(_ kind: PlaybackSegment.Kind) {
        switch kind {
        case .intro: self = .intro
        case .recap: self = .recap
        case .credits: self = .credits
        case .preview: self = .preview
        case .advert: self = .advert
        }
    }
}
