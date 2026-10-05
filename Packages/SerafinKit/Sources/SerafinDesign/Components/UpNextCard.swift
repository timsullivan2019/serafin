import SwiftUI

/// What plays next when an episode ends: the next episode's card, a countdown, Play Now and Cancel.
///
/// It floats over the last frame of the video. The player runs the countdown and passes the seconds left; at zero
/// it plays the episode itself. Always dark, like the rest of the player.
public struct UpNextCard: View {
    private let card: MediaCard
    private let artwork: Image?
    private let secondsLeft: Int
    private let playNow: () -> Void
    private let cancel: () -> Void
    @State private var playNowTaps = 0

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - card: The next episode.
    ///   - artwork: Its thumbnail, or nil while it loads.
    ///   - secondsLeft: The seconds before it plays.
    ///   - playNow: Called when Play Now is tapped.
    ///   - cancel: Called when Cancel is tapped.
    public init(
        card: MediaCard,
        artwork: Image?,
        secondsLeft: Int,
        playNow: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        self.card = card
        self.artwork = artwork
        self.secondsLeft = secondsLeft
        self.playNow = playNow
        self.cancel = cancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "Up Next", bundle: .module, comment: "Heading over the next episode."))
                    .typography(.headline)
                    .foregroundStyle(.textPrimary)
                Text(countdown)
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityHidden(true)
            }
            LandscapeCard(card: card, artwork: artwork)
                .frame(width: 280)
            GlassEffectContainer(spacing: Spacing.small) {
                HStack(spacing: Spacing.small) {
                    Button {
                        playNowTaps += 1
                        playNow()
                    } label: {
                        Label(
                            String(
                                localized: "Play Now", bundle: .module, comment: "Button that plays the next episode."),
                            systemImage: "play.fill"
                        )
                        .padding(.horizontal, Spacing.xSmall)
                        .frame(minHeight: 36)
                        .foregroundStyle(.black)
                    }
                    // A white pill, like the system player's play buttons, so it reads over any picture.
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    // The same tap as the hero's Play. When the countdown runs out, nothing taps: nobody touched it.
                    .sensoryFeedback(.impact(weight: .medium), trigger: playNowTaps)
                    Button(action: cancel) {
                        Text(String(localized: "Cancel", bundle: .module, comment: "Button that stops autoplay."))
                            .padding(.horizontal, Spacing.xSmall)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .tint(.white)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// "Plays in 7 seconds".
    private var countdown: String {
        let seconds = Duration.seconds(max(secondsLeft, 0)).formatted(.units(allowed: [.seconds], width: .wide))
        return String(
            localized: "Plays in \(seconds)",
            bundle: .module,
            comment: "Countdown before the next episode plays, such as Plays in 7 seconds."
        )
    }
}

/// The glass circle that flashes on the side of the video a double tap skipped back or forward on.
public struct SkipIndicator: View {
    /// Which way the double tap skipped.
    public enum Direction: Sendable {
        /// Back 10 seconds.
        case backward
        /// Forward 10 seconds.
        case forward
    }

    private let direction: Direction

    /// Creates the indicator.
    public init(_ direction: Direction) {
        self.direction = direction
    }

    public var body: some View {
        Image(systemName: direction == .backward ? "gobackward.10" : "goforward.10")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 84, height: 84)
            .glassEffect(.regular, in: .circle)
            .environment(\.colorScheme, .dark)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    private struct UpNextSample: View {
        private let next = MockMedia.episodes[1]

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                (MockMedia.backdropImage(for: MockMedia.episodes[0]) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.45).ignoresSafeArea())
                HStack {
                    SkipIndicator(.backward)
                    Spacer()
                    UpNextCard(
                        card: next,
                        artwork: MockMedia.backdropImage(for: next),
                        secondsLeft: 7,
                        playNow: {},
                        cancel: {}
                    )
                }
                .padding(Spacing.large)
            }
        }
    }

    #Preview("Light", traits: .landscapeLeft) {
        UpNextSample()
    }

    #Preview("Dark", traits: .landscapeLeft) {
        UpNextSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text", traits: .landscapeLeft) {
        UpNextSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
