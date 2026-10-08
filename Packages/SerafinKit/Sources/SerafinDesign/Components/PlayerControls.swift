import SwiftUI

/// What the player's controls do. Each action defaults to doing nothing.
public struct PlayerControlActions {
    /// Puts the player away. A video that's playing carries on in Picture in Picture.
    public var minimize: () -> Void
    /// Toggles between playing and paused.
    public var playPause: () -> Void
    /// Skips back 10 seconds.
    public var skipBackward: () -> Void
    /// Skips forward 10 seconds.
    public var skipForward: () -> Void
    /// Moves playback to a position, when a drag on the scrubber ends.
    public var seek: (Duration) -> Void
    /// Called with true when a drag on the scrubber begins and false when it ends, so the screen keeps the controls
    /// showing meanwhile.
    public var scrubbingChanged: (Bool) -> Void
    /// Plays at another speed, such as 1.5.
    public var setRate: @MainActor (Float) -> Void
    /// Opens the audio and subtitle picker.
    public var showTracks: () -> Void
    /// Starts or stops Picture in Picture.
    public var togglePictureInPicture: () -> Void
    /// Switches the picture between fitting the screen and filling it.
    public var toggleFill: () -> Void
    /// Skips the stretch the skip pill offers, such as the intro.
    public var skipSegment: () -> Void

    /// Creates the set of actions.
    public init(
        minimize: @escaping () -> Void = {},
        playPause: @escaping () -> Void = {},
        skipBackward: @escaping () -> Void = {},
        skipForward: @escaping () -> Void = {},
        seek: @escaping (Duration) -> Void = { _ in },
        scrubbingChanged: @escaping (Bool) -> Void = { _ in },
        setRate: @escaping @MainActor (Float) -> Void = { _ in },
        showTracks: @escaping () -> Void = {},
        togglePictureInPicture: @escaping () -> Void = {},
        toggleFill: @escaping () -> Void = {},
        skipSegment: @escaping () -> Void = {}
    ) {
        self.minimize = minimize
        self.playPause = playPause
        self.skipBackward = skipBackward
        self.skipForward = skipForward
        self.seek = seek
        self.scrubbingChanged = scrubbingChanged
        self.setRate = setRate
        self.showTracks = showTracks
        self.togglePictureInPicture = togglePictureInPicture
        self.toggleFill = toggleFill
        self.skipSegment = skipSegment
    }
}

/// What the controls offer above the scrubber at the trailing edge while a stretch the server marked plays, whether
/// or not the other controls show.
public enum SegmentPrompt: Hashable, Sendable {
    /// The pill that skips the stretch, such as Skip Intro.
    case skip(SkipSegmentButton.Kind)
    /// The brief notice that Serafin skipped one by itself, such as "Skipped intro".
    case skipped(SkipSegmentButton.Kind)
}

/// Where playback is and how it is going, as the player's controls show it.
public struct PlayerControlsStatus: Equatable, Sendable {
    /// Whether playback is running, which decides between the play and pause symbols.
    public var isPlaying: Bool
    /// Whether the player is loading or waiting for data, which shows a spinner in the play button.
    public var isBuffering: Bool
    /// The playback position.
    public var elapsed: Duration
    /// The total running time.
    public var duration: Duration
    /// How far ahead of the start the player has loaded.
    public var buffered: Duration
    /// The playback speed, such as 1.5.
    public var rate: Float

    /// Creates a status.
    public init(
        isPlaying: Bool,
        isBuffering: Bool = false,
        elapsed: Duration,
        duration: Duration,
        buffered: Duration = .zero,
        rate: Float = 1
    ) {
        self.isPlaying = isPlaying
        self.isBuffering = isBuffering
        self.elapsed = elapsed
        self.duration = duration
        self.buffered = buffered
        self.rate = rate
    }
}

/// The playback speeds the player offers.
public enum PlaybackSpeed {
    /// The speeds, slowest first.
    public static let choices: [Float] = [0.75, 1, 1.25, 1.5, 2]

    /// A speed as the player shows it, such as "1.25×".
    public static func label(_ rate: Float, locale: Locale = .current) -> String {
        let number = Double(rate).formatted(.number.precision(.fractionLength(0...2)).locale(locale))
        return String(
            localized: "\(number)×",
            bundle: .module,
            locale: locale,
            comment: "A playback speed, such as 1.25×."
        )
    }
}

/// The player's glass controls, laid over the video: minimize, title, fill, Picture in Picture and AirPlay along the
/// top;
/// skip back, play or pause and skip forward in the middle; the scrubber, the speed and the audio and subtitle
/// button along the bottom.
///
/// All controls share one glass container and always render in dark appearance. The darkening behind them lets
/// taps through, so a tap on the video still reaches the screen underneath. The AirPlay control is a slot, because
/// the real route picker is a UIKit view that SerafinPlayback provides.
///
/// Hidden controls fade out but stay in place, so a menu open on one of them stays usable. The skip pill and its
/// notice sit above the scrubber at the trailing edge, in a glass container of their own, so they stay while the
/// controls are hidden: glass inside the controls' container keeps showing when only its content fades. They
/// materialize as a stretch starts and dissolve as it ends.
///
/// With a hardware keyboard, Space plays and pauses, the left and right arrows skip 10 seconds, and F leaves the
/// full-screen player, as in other video players.
///
/// Play and pause give a light tap, and dragging the scrubber ticks at each tenth of the way through and where the
/// drag began.
public struct PlayerControls<RoutePicker: View>: View {
    private let title: String
    private let subtitle: String?
    private let status: PlayerControlsStatus
    private let showsPictureInPicture: Bool
    private let fillsScreen: Bool?
    private let showsControls: Bool
    private let segmentPrompt: SegmentPrompt?
    private let actions: PlayerControlActions
    private let routePicker: RoutePicker
    @State private var playPauseTaps = 0
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the player controls.
    ///
    /// - Parameters:
    ///   - title: The title of what is playing.
    ///   - subtitle: A second line, such as the series and episode code.
    ///   - status: Where playback is and how it is going.
    ///   - showsPictureInPicture: Whether to offer Picture in Picture, which some devices can't do.
    ///   - fillsScreen: Whether the picture fills the screen, which the fill button shows and switches, or nil for no
    ///     fill button.
    ///   - showsControls: Whether the controls show. Hidden, they fade out, and only the skip pill or its notice
    ///     stays.
    ///   - segmentPrompt: The skip pill or notice to show above the scrubber, or nil for none.
    ///   - actions: What each control does.
    ///   - routePicker: The AirPlay route picker, shown in a glass circle at the top trailing corner.
    public init(
        title: String,
        subtitle: String? = nil,
        status: PlayerControlsStatus,
        showsPictureInPicture: Bool = true,
        fillsScreen: Bool? = nil,
        showsControls: Bool = true,
        segmentPrompt: SegmentPrompt? = nil,
        actions: PlayerControlActions,
        @ViewBuilder routePicker: () -> RoutePicker
    ) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.showsPictureInPicture = showsPictureInPicture
        self.fillsScreen = fillsScreen
        self.showsControls = showsControls
        self.segmentPrompt = segmentPrompt
        self.actions = actions
        self.routePicker = routePicker()
    }

    public var body: some View {
        ZStack {
            controls
                .shown(showsControls)
            GlassEffectContainer {
                prompt
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, Spacing.medium)
            .padding(.bottom, PlayerLayout.bottomBarClearance)
            .animation(Motion.animation(reduceMotion: reduceMotion), value: segmentPrompt)
        }
        .environment(\.colorScheme, .dark)
        // Symbols and text are white over the video, whatever the app's accent.
        .tint(.white)
        // Like the system player, the overlay stops growing at the largest standard size; the buttons offer the
        // Large Content Viewer instead.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// The bars, with the darkening behind them.
    private var controls: some View {
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
            .allowsHitTesting(false)
        }
    }

    /// The skip pill, or the notice that a stretch was skipped, materializing in its glass.
    @ViewBuilder private var prompt: some View {
        switch segmentPrompt {
        case .skip(let kind):
            SkipSegmentButton(kind, skip: actions.skipSegment)
                .glassEffectTransition(.materialize)
                .id(segmentPrompt)
        case .skipped(let kind):
            SkippedNotice(kind)
                .glassEffectTransition(.materialize)
                .id(segmentPrompt)
        case nil:
            EmptyView()
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.small) {
            GlassIconButton(
                systemImage: "chevron.down",
                label: String(
                    localized: "Minimize Player",
                    bundle: .module,
                    comment:
                        "Button that puts the player away; a video that's playing carries on in Picture in Picture."
                ),
                action: actions.minimize
            )
            .keyboardShortcut("f", modifiers: [])
            VStack(spacing: 2) {
                Text(title)
                    .typography(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .typography(.caption)
                        .foregroundStyle(contrast == .increased ? .primary : .secondary)
                        .lineLimit(1)
                }
            }
            // Lifted off bright video, as the hero's title is.
            .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            if let fillsScreen {
                GlassIconButton(
                    systemImage: fillsScreen
                        ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: fillsScreen
                        ? String(
                            localized: "Fit to Screen", bundle: .module,
                            comment: "Button that shrinks the video to fit inside the screen, with black bars.")
                        : String(
                            localized: "Fill Screen", bundle: .module,
                            comment: "Button that enlarges the video to fill the screen, cropping its edges."),
                    action: actions.toggleFill
                )
                .contentTransition(.symbolEffect(.replace))
            }
            if showsPictureInPicture {
                GlassIconButton(
                    systemImage: "pip.enter",
                    label: String(
                        localized: "Picture in Picture",
                        bundle: .module,
                        comment: "Button that moves the video into a floating window."
                    ),
                    action: actions.togglePictureInPicture
                )
            }
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
            .keyboardShortcut(.leftArrow, modifiers: [])
            GlassIconButton(
                systemImage: status.isPlaying ? "pause.fill" : "play.fill",
                size: 80,
                label: status.isPlaying
                    ? String(localized: "Pause", bundle: .module, comment: "Button that pauses playback.")
                    : String(localized: "Play", bundle: .module, comment: "Button that starts playback."),
                isBusy: status.isBuffering
            ) {
                playPauseTaps += 1
                actions.playPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .contentTransition(.symbolEffect(.replace))
            .sensoryFeedback(.impact(weight: .light), trigger: playPauseTaps)
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
            .keyboardShortcut(.rightArrow, modifiers: [])
        }
    }

    private var bottomBar: some View {
        HStack(spacing: Spacing.small) {
            Scrubber(
                elapsed: status.elapsed,
                duration: status.duration,
                buffered: status.buffered,
                seek: actions.seek,
                scrubbingChanged: actions.scrubbingChanged
            )
            SpeedMenu(rate: status.rate, setRate: actions.setRate)
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
        status: PlayerControlsStatus,
        showsPictureInPicture: Bool = true,
        fillsScreen: Bool? = nil,
        showsControls: Bool = true,
        segmentPrompt: SegmentPrompt? = nil,
        actions: PlayerControlActions
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            status: status,
            showsPictureInPicture: showsPictureInPicture,
            fillsScreen: fillsScreen,
            showsControls: showsControls,
            segmentPrompt: segmentPrompt,
            actions: actions
        ) { EmptyView() }
    }
}

extension View {
    /// Fades the view out and takes it out of reach of touch and VoiceOver while `isShown` is false, keeping it in
    /// place, so a menu open on it stays usable. Glass fades with it only when its whole container does.
    fileprivate func shown(_ isShown: Bool) -> some View {
        opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }
}

/// A round glass button holding one symbol, or a spinner while busy.
private struct GlassIconButton: View {
    let systemImage: String
    var size: CGFloat = 44
    let label: String
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isBusy {
                    ProgressView()
                        .controlSize(size >= 60 ? .large : .regular)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: size * 0.4, weight: .semibold))
                }
            }
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

/// The playback speed in a glass capsule, opening a menu of the speeds.
private struct SpeedMenu: View {
    let rate: Float
    let setRate: @MainActor (Float) -> Void

    private var title: String {
        String(localized: "Playback Speed", bundle: .module, comment: "Menu that changes how fast the video plays.")
    }

    var body: some View {
        Menu {
            // A closure rather than the action itself: Xcode 26's compiler crashes converting the function value.
            Picker(selection: Binding(get: { rate }, set: { setRate($0) })) {
                ForEach(PlaybackSpeed.choices, id: \.self) { choice in
                    Text(PlaybackSpeed.label(choice)).tag(choice)
                }
            } label: {
                Text(title)
            }
            .pickerStyle(.inline)
        } label: {
            Text(PlaybackSpeed.label(rate))
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .accessibilityLabel(title)
        .accessibilityValue(PlaybackSpeed.label(rate))
        .accessibilityShowsLargeContentViewer {
            Label(PlaybackSpeed.label(rate), systemImage: "gauge.with.dots.needle.67percent")
        }
    }
}

/// The playback position: elapsed time, a track and time remaining, on one glass capsule. Dragging along the track
/// shows the time under the finger and seeks there on release.
private struct Scrubber: View {
    let elapsed: Duration
    let duration: Duration
    let buffered: Duration
    let seek: (Duration) -> Void
    let scrubbingChanged: (Bool) -> Void
    @State private var scrubbedFraction: Double?
    @State private var scrubStart: Double = 0
    @State private var detentsPassed = 0
    @State private var trackWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isScrubbing: Bool { scrubbedFraction != nil }

    /// The position shown: under the finger while dragging, otherwise where playback is.
    private var shownPosition: Duration {
        scrubbedFraction.map { ScrubberMath.position(at: $0, in: duration) } ?? elapsed
    }

    var body: some View {
        HStack(spacing: Spacing.small) {
            Text(ScrubberMath.timecode(shownPosition))
                .fixedSize()
            track
            Text(verbatim: "-" + ScrubberMath.timecode(max(duration - shownPosition, .zero)))
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
                localized: "\(ScrubberMath.timecode(elapsed)) of \(ScrubberMath.timecode(duration))",
                bundle: .module,
                comment: "Spoken playback position, such as 12:34 of 1:39:00."
            )
        )
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seek(elapsed + .seconds(10))
            case .decrement: seek(max(elapsed - .seconds(10), .zero))
            @unknown default: break
            }
        }
    }

    private var track: some View {
        let fraction = scrubbedFraction ?? ScrubberMath.fraction(of: elapsed, in: duration)
        let loaded = ScrubberMath.fraction(of: buffered, in: duration)
        return Capsule()
            .fill(.white.opacity(0.25))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.3))
                            .frame(width: width * loaded)
                        Capsule()
                            .fill(.white)
                            .frame(width: max(proxy.size.height, width * fraction))
                    }
                }
            }
            .frame(height: isScrubbing ? 10 : 5)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                trackWidth = $0
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard trackWidth > 0 else { return }
                        let previous = scrubbedFraction ?? ScrubberMath.fraction(of: elapsed, in: duration)
                        if scrubbedFraction == nil {
                            scrubStart = previous
                            scrubbingChanged(true)
                        }
                        let fraction = min(max(value.location.x / trackWidth, 0), 1)
                        if ScrubberMath.passesDetent(from: previous, to: fraction, start: scrubStart) {
                            detentsPassed += 1
                        }
                        scrubbedFraction = fraction
                    }
                    .onEnded { _ in
                        if let scrubbedFraction {
                            seek(ScrubberMath.position(at: scrubbedFraction, in: duration))
                        }
                        scrubbedFraction = nil
                        scrubbingChanged(false)
                    }
            )
            .overlay(alignment: .topLeading) {
                if let scrubbedFraction {
                    let thumbOffset = trackWidth * scrubbedFraction
                    Text(ScrubberMath.timecode(ScrubberMath.position(at: scrubbedFraction, in: duration)))
                        .font(.subheadline.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, Spacing.small)
                        .padding(.vertical, Spacing.xSmall)
                        .glassEffect(.regular, in: .capsule)
                        .fixedSize()
                        .alignmentGuide(.leading) { $0.width / 2 - thumbOffset }
                        .alignmentGuide(.top) { $0.height + Spacing.large }
                        .accessibilityHidden(true)
                }
            }
            .animation(Motion.animation(reduceMotion: reduceMotion), value: isScrubbing)
            .sensoryFeedback(.selection, trigger: detentsPassed)
    }
}

/// The arithmetic behind the scrubber.
enum ScrubberMath {
    /// How far `position` is through `duration`, from 0 to 1.
    static func fraction(of position: Duration, in duration: Duration) -> Double {
        guard duration > .zero else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    /// The position `fraction` of the way through `duration`, to the millisecond.
    static func position(at fraction: Double, in duration: Duration) -> Duration {
        let clamped = min(max(fraction, 0), 1)
        let milliseconds =
            Double(duration.components.seconds) * 1000
            + Double(duration.components.attoseconds) / 1e15
        return .milliseconds(Int64((milliseconds * clamped).rounded()))
    }

    /// Whether a drag from `old` to `new`, both fractions of the way through, passes a detent: a tenth of the way, the
    /// very start or end, or `start`, where the drag began, so a person can feel their way back to it.
    static func passesDetent(from old: Double, to new: Double, start: Double) -> Bool {
        guard old != new else { return false }
        // The very start is a section of its own, so arriving at it ticks like arriving at the end does.
        func section(_ fraction: Double) -> Int { fraction <= 0 ? -1 : Int((fraction * 10).rounded(.down)) }
        let crossesStart = (old - start) * (new - start) < 0 || (new == start && old != start)
        return section(old) != section(new) || crossesStart
    }

    /// A time as the scrubber shows it, such as "12:34" or "1:39:00".
    static func timecode(_ duration: Duration) -> String {
        duration.formatted(.time(pattern: duration >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond))
    }
}

#if DEBUG
    private struct PlayerControlsSample: View {
        @State private var isPlaying = true
        @State private var elapsed = Duration.seconds(372)
        @State private var rate: Float = 1
        @State private var fillsScreen = false
        var isBuffering = false
        var showsControls = true
        var segmentPrompt: SegmentPrompt?
        private let card = MockMedia.movies[1]

        var body: some View {
            PlayerControls(
                title: card.title,
                subtitle: card.year.map(String.init),
                status: PlayerControlsStatus(
                    isPlaying: isPlaying,
                    isBuffering: isBuffering,
                    elapsed: elapsed,
                    duration: .seconds(888),
                    buffered: .seconds(520),
                    rate: rate
                ),
                fillsScreen: fillsScreen,
                showsControls: showsControls,
                segmentPrompt: segmentPrompt,
                actions: PlayerControlActions(
                    playPause: { isPlaying.toggle() },
                    seek: { elapsed = $0 },
                    setRate: { rate = $0 },
                    toggleFill: { fillsScreen.toggle() }
                )
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

    #Preview("Buffering", traits: .landscapeLeft) {
        PlayerControlsSample(isBuffering: true)
    }

    #Preview("Largest text") {
        PlayerControlsSample()
            .dynamicTypeSize(.accessibility5)
    }

    #Preview("Skip Intro", traits: .landscapeLeft) {
        PlayerControlsSample(segmentPrompt: .skip(.intro))
    }

    #Preview("Skip Intro, controls hidden", traits: .landscapeLeft) {
        PlayerControlsSample(showsControls: false, segmentPrompt: .skip(.intro))
    }

    #Preview("Skipped notice, controls hidden", traits: .landscapeLeft) {
        PlayerControlsSample(showsControls: false, segmentPrompt: .skipped(.recap))
    }
#endif
