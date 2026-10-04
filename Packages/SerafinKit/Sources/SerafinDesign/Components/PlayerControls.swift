import SwiftUI

/// What the player's controls do when tapped. Each action defaults to doing nothing.
public struct PlayerControlActions {
    /// Closes the player.
    public var close: () -> Void
    /// Toggles between playing and paused.
    public var playPause: () -> Void
    /// Skips back 10 seconds.
    public var skipBackward: () -> Void
    /// Skips forward 10 seconds.
    public var skipForward: () -> Void
    /// Opens the audio and subtitle picker.
    public var showTracks: () -> Void
    /// Starts or stops Picture in Picture.
    public var togglePictureInPicture: () -> Void

    /// Creates the set of actions.
    public init(
        close: @escaping () -> Void = {},
        playPause: @escaping () -> Void = {},
        skipBackward: @escaping () -> Void = {},
        skipForward: @escaping () -> Void = {},
        showTracks: @escaping () -> Void = {},
        togglePictureInPicture: @escaping () -> Void = {}
    ) {
        self.close = close
        self.playPause = playPause
        self.skipBackward = skipBackward
        self.skipForward = skipForward
        self.showTracks = showTracks
        self.togglePictureInPicture = togglePictureInPicture
    }
}

/// The player's glass controls, laid over the video: close, title, Picture in Picture and AirPlay along the top;
/// skip back, play or pause and skip forward in the middle; the scrubber and the audio and subtitle button along
/// the bottom.
///
/// All controls share one glass container and always render in dark appearance. The AirPlay control is a slot,
/// because the real route picker is a UIKit view that SerafinPlayback provides.
public struct PlayerControls<RoutePicker: View>: View {
    private let title: String
    private let subtitle: String?
    private let isPlaying: Bool
    private let elapsed: Duration
    private let duration: Duration
    private let actions: PlayerControlActions
    private let routePicker: RoutePicker

    /// Creates the player controls.
    ///
    /// - Parameters:
    ///   - title: The title of what is playing.
    ///   - subtitle: A second line, such as the series and episode code.
    ///   - isPlaying: Whether playback is running, which decides between the play and pause symbols.
    ///   - elapsed: The playback position.
    ///   - duration: The total running time.
    ///   - actions: What each control does.
    ///   - routePicker: The AirPlay route picker, shown in a glass circle at the top trailing corner.
    public init(
        title: String,
        subtitle: String? = nil,
        isPlaying: Bool,
        elapsed: Duration,
        duration: Duration,
        actions: PlayerControlActions,
        @ViewBuilder routePicker: () -> RoutePicker
    ) {
        self.title = title
        self.subtitle = subtitle
        self.isPlaying = isPlaying
        self.elapsed = elapsed
        self.duration = duration
        self.actions = actions
        self.routePicker = routePicker()
    }

    public var body: some View {
        GlassEffectContainer(spacing: Spacing.medium) {
            VStack(spacing: 0) {
                topBar
                Spacer(minLength: Spacing.large)
                transport
                Spacer(minLength: Spacing.large)
                bottomBar
            }
            .padding(Spacing.medium)
        }
        .background {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.1), location: 0.3),
                    .init(color: .black.opacity(0.1), location: 0.7),
                    .init(color: .black.opacity(0.6), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        // Like the system player, the overlay stops growing at the largest standard size; the buttons offer the
        // Large Content Viewer instead.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var topBar: some View {
        HStack(spacing: Spacing.small) {
            GlassIconButton(
                systemImage: "xmark",
                label: String(localized: "Close", bundle: .module, comment: "Button that closes the player."),
                action: actions.close
            )
            VStack(spacing: 2) {
                Text(title)
                    .typography(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .typography(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            GlassIconButton(
                systemImage: "pip.enter",
                label: String(
                    localized: "Picture in Picture",
                    bundle: .module,
                    comment: "Button that moves the video into a floating window."
                ),
                action: actions.togglePictureInPicture
            )
            routePicker
                .frame(width: 44, height: 44)
                .glassEffect(.regular.interactive(), in: .circle)
        }
    }

    private var transport: some View {
        HStack(spacing: Spacing.xLarge) {
            GlassIconButton(
                systemImage: "gobackward.10",
                size: 60,
                label: String(
                    localized: "Skip back 10 seconds",
                    bundle: .module,
                    comment: "Button that jumps back 10 seconds."
                ),
                action: actions.skipBackward
            )
            GlassIconButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                size: 80,
                label: isPlaying
                    ? String(localized: "Pause", bundle: .module, comment: "Button that pauses playback.")
                    : String(localized: "Play", bundle: .module, comment: "Button that starts playback."),
                action: actions.playPause
            )
            .contentTransition(.symbolEffect(.replace))
            GlassIconButton(
                systemImage: "goforward.10",
                size: 60,
                label: String(
                    localized: "Skip forward 10 seconds",
                    bundle: .module,
                    comment: "Button that jumps forward 10 seconds."
                ),
                action: actions.skipForward
            )
        }
    }

    private var bottomBar: some View {
        HStack(spacing: Spacing.small) {
            Scrubber(elapsed: elapsed, duration: duration)
            GlassIconButton(
                systemImage: "captions.bubble",
                label: String(
                    localized: "Audio and Subtitles",
                    bundle: .module,
                    comment: "Button that opens the audio and subtitle picker."
                ),
                action: actions.showTracks
            )
        }
    }
}

extension PlayerControls where RoutePicker == EmptyView {
    /// Creates the player controls without an AirPlay control.
    public init(
        title: String,
        subtitle: String? = nil,
        isPlaying: Bool,
        elapsed: Duration,
        duration: Duration,
        actions: PlayerControlActions
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            actions: actions
        ) { EmptyView() }
    }
}

/// A round glass button holding one symbol.
private struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityShowsLargeContentViewer {
            Label(label, systemImage: systemImage)
        }
    }
}

/// The playback position: elapsed time, a progress track and time remaining, on one glass capsule.
private struct Scrubber: View {
    let elapsed: Duration
    let duration: Duration

    private var fraction: Double {
        guard duration > .zero else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: Spacing.small) {
            Text(Self.timecode(elapsed))
                .fixedSize()
            Capsule()
                .fill(.white.opacity(0.3))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.white)
                            .frame(width: max(proxy.size.height, proxy.size.width * fraction))
                    }
                }
                .frame(height: 5)
            Text(verbatim: "-" + Self.timecode(duration - elapsed))
                .fixedSize()
        }
        .font(.caption.monospacedDigit().weight(.medium))
        .padding(.horizontal, Spacing.medium)
        .frame(minHeight: 44)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "Playback position", bundle: .module, comment: "Spoken name of the player scrubber.")
        )
        .accessibilityValue(
            String(
                localized: "\(Self.timecode(elapsed)) of \(Self.timecode(duration))",
                bundle: .module,
                comment: "Spoken playback position, such as 12:34 of 1:39:00."
            )
        )
    }

    static func timecode(_ duration: Duration) -> String {
        duration.formatted(.time(pattern: duration >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond))
    }
}

#if DEBUG
    private struct PlayerControlsSample: View {
        @State private var isPlaying = true
        private let card = MockMedia.movies[1]

        var body: some View {
            PlayerControls(
                title: card.title,
                subtitle: card.year.map(String.init),
                isPlaying: isPlaying,
                elapsed: .seconds(372),
                duration: .seconds(888),
                actions: PlayerControlActions(playPause: { isPlaying.toggle() })
            ) {
                Image(systemName: "airplay.video")
                    .font(.system(size: 17, weight: .semibold))
            }
            .background {
                (MockMedia.backdropImage(for: card) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }
        }
    }

    #Preview("Light") {
        PlayerControlsSample()
    }

    #Preview("Dark", traits: .landscapeLeft) {
        PlayerControlsSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        PlayerControlsSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
