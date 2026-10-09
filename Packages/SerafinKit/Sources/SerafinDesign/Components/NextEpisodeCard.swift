import SwiftUI

/// The time left before the next episode plays by itself. It runs while the episode plays and holds while it's paused,
/// so the player can stop it while playback is paused or scrubbed and carry on from where it stopped.
public struct NextEpisodeCountdown: Equatable, Sendable {
    /// How long the whole countdown lasts.
    public let length: Duration
    /// The time left when it last paused or resumed.
    private var leftAtMark: Duration
    /// When it last started or resumed, or nil while it holds.
    public private(set) var runningSince: Date?

    /// Creates a countdown.
    ///
    /// - Parameters:
    ///   - length: How long the whole countdown lasts.
    ///   - left: The time left, or nil for all of `length`.
    ///   - now: When it starts running, or nil for a countdown that holds until ``resume(at:)``.
    public init(length: Duration, left: Duration? = nil, runningFrom now: Date?) {
        self.length = length
        leftAtMark = min(max(left ?? length, .zero), length)
        runningSince = now
    }

    /// Whether it's counting down.
    public var isRunning: Bool {
        runningSince != nil
    }

    /// The time left at `date`, never less than zero.
    public func left(at date: Date) -> Duration {
        guard let runningSince else { return leftAtMark }
        let passed = Duration.seconds(max(date.timeIntervalSince(runningSince), 0))
        return max(leftAtMark - passed, .zero)
    }

    /// How much of the countdown has gone by at `date`, from 0 to 1, which the ring around Play Now fills to.
    public func fractionPassed(at date: Date) -> Double {
        guard length > .zero else { return 1 }
        return min(max(1 - left(at: date) / length, 0), 1)
    }

    /// The seconds left at `date`, counting a part of a second as a whole one: 10 at the start, 1 in the last second
    /// and 0 once it's over.
    public func secondsLeft(at date: Date) -> Int {
        let (seconds, attoseconds) = left(at: date).components
        return Int(seconds) + (attoseconds > 0 ? 1 : 0)
    }

    /// How long from `date` until the seconds left next change, or until the countdown ends.
    public func untilNextSecond(at date: Date) -> Duration {
        let left = left(at: date)
        let (seconds, attoseconds) = left.components
        return attoseconds > 0 ? left - .seconds(seconds) : min(left, .seconds(1))
    }

    /// Holds the countdown at `date`, keeping the time it has left.
    public mutating func pause(at date: Date) {
        guard isRunning else { return }
        leftAtMark = left(at: date)
        runningSince = nil
    }

    /// Runs the countdown again from `date`, with the time it had left.
    public mutating func resume(at date: Date) {
        guard !isRunning else { return }
        runningSince = date
    }
}

/// The next episode as the player offers it on ``NextEpisodeCard``.
public struct NextEpisodePrompt {
    /// The next episode.
    public var card: MediaCard
    /// Its thumbnail, or nil while it loads.
    public var artwork: Image?
    /// The glass tint for Play Now, taken from the thumbnail like every primary pill's from its artwork.
    public var tint: Color
    /// The countdown before it plays by itself, or nil when it waits for Play Now.
    public var countdown: NextEpisodeCountdown?
    /// The whole seconds left on the countdown, as VoiceOver says them, or nil without one.
    public var secondsLeft: Int?

    /// Creates the prompt.
    ///
    /// - Parameters:
    ///   - card: The next episode.
    ///   - artwork: Its thumbnail, or nil while it loads.
    ///   - tint: The glass tint for Play Now.
    ///   - countdown: The countdown before it plays by itself, or nil when it waits for Play Now.
    ///   - secondsLeft: The whole seconds left on the countdown, or nil without one.
    public init(
        card: MediaCard,
        artwork: Image?,
        tint: Color,
        countdown: NextEpisodeCountdown? = nil,
        secondsLeft: Int? = nil
    ) {
        self.card = card
        self.artwork = artwork
        self.tint = tint
        self.countdown = countdown
        self.secondsLeft = secondsLeft
    }
}

/// The next episode, offered over an episode's credits and as it ends, as the TV app offers it: a glass card with the
/// episode's thumbnail, code, title and running time, Play Now, and a close button.
///
/// When the episode plays by itself, a ring around Play Now's symbol fills as the countdown runs, and holds while the
/// countdown does. A tap anywhere on the card but its close button plays the episode now. VoiceOver reads the card as
/// one element, such as "Next episode, Gran Dillama, plays in 8 seconds", with Play Now and Cancel as actions.
///
/// ``PlayerControls`` shows it in the bottom trailing corner, in the glass container it keeps on screen while the other
/// controls hide. Always dark, like the rest of the player.
public struct NextEpisodeCard: View {
    /// The widest the card grows. Narrower spaces get a narrower card, and the title truncates.
    nonisolated public static let maximumWidth: CGFloat = 320
    /// How wide the thumbnail is, for loading it at its size.
    nonisolated public static let thumbnailWidth: CGFloat = 96
    /// The thumbnail's size.
    nonisolated static let thumbnailSize = CGSize(width: thumbnailWidth, height: 54)
    /// The height of Play Now and the close button, glass included.
    nonisolated static let buttonHeight: CGFloat = 44

    private let prompt: NextEpisodePrompt
    private let playNow: () -> Void
    private let cancel: () -> Void
    @State private var plays = 0
    @Environment(\.colorSchemeContrast) private var contrast

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - prompt: The next episode, its thumbnail and tint, and the countdown.
    ///   - playNow: Plays the next episode now.
    ///   - cancel: Puts the card away.
    public init(_ prompt: NextEpisodePrompt, playNow: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.prompt = prompt
        self.playNow = playNow
        self.cancel = cancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                CardArtwork(card: prompt.card, image: prompt.artwork, aspectRatio: 16 / 9, showsPlayedBadge: false)
                    .frame(width: Self.thumbnailSize.width, height: Self.thumbnailSize.height)
                details
            }
            HStack(spacing: Spacing.xSmall) {
                Button(action: play) {
                    PlayNowLabel(countdown: prompt.countdown)
                        .frame(minHeight: Self.buttonHeight - 2 * SkipSegmentButton.glassVerticalPadding)
                }
                .buttonStyle(.glassProminent)
                .tint(prompt.tint)
                Spacer(minLength: 0)
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .frame(
                            width: Self.buttonHeight - 2 * SkipSegmentButton.glassVerticalPadding,
                            height: Self.buttonHeight - 2 * SkipSegmentButton.glassVerticalPadding)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .padding(Spacing.small)
        .frame(maxWidth: Self.maximumWidth, alignment: .leading)
        .glassEffect(.regular, in: .rounded(.medium))
        .contentShape(.rounded(.medium))
        .onTapGesture(perform: play)
        .sensoryFeedback(.impact(weight: .light), trigger: plays)
        .environment(\.colorScheme, .dark)
        .tint(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { play() }
        .accessibilityAction(named: Text(Self.playNowTitle), play)
        .accessibilityAction(named: Text(Self.cancelTitle), cancel)
    }

    /// "Next Episode", the code and title, and the running time.
    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Next Episode", bundle: .module, comment: "Heading over the next episode."))
                .typography(.caption)
                .foregroundStyle(secondary)
            Text(Self.titleLine(for: prompt.card))
                .typography(.headline)
                .foregroundStyle(.primary)
            if let runtime = prompt.card.runtimeText {
                Text(runtime)
                    .typography(.caption)
                    .foregroundStyle(secondary)
            }
        }
        .lineLimit(1)
    }

    /// The style of the lines around the title: secondary, like the player's other second lines, or primary with
    /// Increase Contrast.
    private var secondary: HierarchicalShapeStyle {
        contrast == .increased ? .primary : .secondary
    }

    /// Plays the episode now, with a light tap. When the countdown runs out, nothing taps: nobody touched it.
    private func play() {
        plays += 1
        playNow()
    }

    /// "S1 E2 · Gran Dillama", or the title alone for anything that isn't an episode.
    static func titleLine(for card: MediaCard) -> String {
        guard let code = card.episodeCode else { return card.title }
        return String(
            localized: "\(code) · \(card.title)", bundle: .module,
            comment:
                "Two parts of a line joined by a dot: a series title and episode code above an episode title (Caminandes · S1 E2), or a show's next episode under its details (S2 E4 · The Final Problem)."
        )
    }

    /// What VoiceOver says: "Next episode, Gran Dillama, plays in 8 seconds".
    var accessibilityLabel: String {
        let title = prompt.card.title
        guard let secondsLeft = prompt.secondsLeft else {
            return String(
                localized: "Next episode, \(title)", bundle: .module,
                comment: "Spoken description of the next episode's card, which waits to be played: Next episode, title."
            )
        }
        let seconds = Duration.seconds(max(secondsLeft, 0)).formatted(.units(allowed: [.seconds], width: .wide))
        return String(
            localized: "Next episode, \(title), plays in \(seconds)", bundle: .module,
            comment:
                "Spoken description of the next episode's card while it counts down: Next episode, title, plays in 8 seconds."
        )
    }

    static var playNowTitle: String {
        String(localized: "Play Now", bundle: .module, comment: "Button that plays the next episode.")
    }

    static var cancelTitle: String {
        String(
            localized: "Cancel", bundle: .module,
            comment: "Button that puts away the next episode's card, so it doesn't play by itself.")
    }
}

/// Play Now's label: the play symbol inside the countdown's ring, then the words.
private struct PlayNowLabel: View {
    let countdown: NextEpisodeCountdown?
    @ScaledMetric(relativeTo: .headline) private var ringSide: CGFloat = 24

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            ZStack {
                if let countdown {
                    // Redrawn every frame while the countdown runs, and once when it holds; it moves under Reduce
                    // Motion too, since it's the time left rather than decoration.
                    TimelineView(.animation(paused: !countdown.isRunning)) { context in
                        CountdownRing(fraction: countdown.fractionPassed(at: context.date))
                    }
                }
                Image(systemName: "play.fill")
                    .font(.system(size: ringSide * 0.42, weight: .bold))
            }
            .frame(width: ringSide, height: ringSide)
            Text(NextEpisodeCard.playNowTitle)
                .typography(.headline)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.xxSmall)
    }
}

/// The ring around Play Now's symbol, filled to `fraction` of the way round from the top, clockwise.
private struct CountdownRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.3), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(1.25)
    }
}

#if DEBUG
    /// The card in the player's corner over a frame of video, as ``PlayerControls`` places it with the controls hidden.
    private struct NextEpisodeSample: View {
        var countdown: NextEpisodeCountdown? = NextEpisodeCountdown(
            length: .seconds(10), left: .seconds(7), runningFrom: nil)
        private let playing = MockMedia.episodes[0]
        private let next = MockMedia.episodes[1]

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                (MockMedia.backdropImage(for: playing) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                GlassEffectContainer {
                    NextEpisodeCard(
                        NextEpisodePrompt(
                            card: next,
                            artwork: MockMedia.backdropImage(for: next),
                            tint: MockMedia.tint(for: next),
                            countdown: countdown,
                            secondsLeft: countdown?.secondsLeft(at: .now)
                        ),
                        playNow: {},
                        cancel: {}
                    )
                }
                .padding(.trailing, Spacing.medium)
                .padding(.bottom, PlayerLayout.bottomBarClearance)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    #Preview("iPhone, light", traits: .landscapeLeft) {
        NextEpisodeSample()
    }

    #Preview("iPhone, dark", traits: .landscapeLeft) {
        NextEpisodeSample()
            .preferredColorScheme(.dark)
    }

    #Preview("iPad, light", traits: .fixedLayout(width: 1194, height: 834)) {
        NextEpisodeSample()
    }

    #Preview("iPad, dark", traits: .fixedLayout(width: 1194, height: 834)) {
        NextEpisodeSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text", traits: .landscapeLeft) {
        NextEpisodeSample()
            .dynamicTypeSize(.accessibility5)
    }

    #Preview("Counting down", traits: .landscapeLeft) {
        NextEpisodeSample(countdown: NextEpisodeCountdown(length: .seconds(10), runningFrom: .now))
    }

    #Preview("Without countdown", traits: .landscapeLeft) {
        NextEpisodeSample(countdown: nil)
    }
#endif
