import SwiftUI

/// The glass pill that skips a stretch the server marked while it plays, like Skip Intro in the TV app: the intro, a
/// recap, a preview, an advert, a stretch of no named kind, or the credits of a film or a last episode.
///
/// ``PlayerControls`` shows it at the trailing edge above the scrubber, in its glass container, for as long as the
/// stretch plays, whether or not the other controls show. A tap gives a light tap of feedback. Always dark, like the
/// rest of the player.
public struct SkipSegmentButton: View {
    /// What the pill skips.
    public enum Kind: Hashable, Sendable, CaseIterable {
        /// The opening titles.
        case intro
        /// A recap of earlier episodes.
        case recap
        /// A preview of what comes next.
        case preview
        /// An advert.
        case advert
        /// The closing credits of a film or a last episode. Credits with an episode after them offer that episode
        /// instead.
        case credits
        /// A stretch the server marked without saying what it is.
        case unknown

        /// The pill's words, such as "Skip Intro".
        public var title: String {
            switch self {
            case .intro: String(localized: "Skip Intro", bundle: .module, comment: "Button that skips the intro.")
            case .recap: String(localized: "Skip Recap", bundle: .module, comment: "Button that skips a recap.")
            case .preview:
                String(localized: "Skip Preview", bundle: .module, comment: "Button that skips a preview.")
            case .advert: String(localized: "Skip Ad", bundle: .module, comment: "Button that skips an advert.")
            case .credits:
                String(localized: "Skip Credits", bundle: .module, comment: "Button that skips the closing credits.")
            case .unknown:
                String(
                    localized: "Skip", bundle: .module,
                    comment: "Button that skips a stretch of the video the server marked without naming it.")
            }
        }

        /// What the notice says once Serafin has skipped the stretch by itself, such as "Skipped intro".
        public var skippedTitle: String {
            switch self {
            case .intro:
                String(localized: "Skipped intro", bundle: .module, comment: "Notice once the intro was skipped.")
            case .recap:
                String(localized: "Skipped recap", bundle: .module, comment: "Notice once a recap was skipped.")
            case .preview:
                String(localized: "Skipped preview", bundle: .module, comment: "Notice once a preview was skipped.")
            case .advert:
                String(localized: "Skipped ad", bundle: .module, comment: "Notice once an advert was skipped.")
            case .credits:
                String(
                    localized: "Skipped credits", bundle: .module,
                    comment: "Notice once the closing credits were skipped.")
            case .unknown:
                String(
                    localized: "Skipped", bundle: .module,
                    comment: "Notice once a stretch of the video the server marked without naming it was skipped.")
            }
        }
    }

    /// The height of the pill, and of the notice that takes its place.
    nonisolated public static let height: CGFloat = 44
    /// What `.buttonStyle(.glass)` adds above and below a label.
    nonisolated static let glassVerticalPadding: CGFloat = 7

    private let kind: Kind
    private let skip: () -> Void
    @State private var taps = 0

    /// Creates the pill.
    ///
    /// - Parameters:
    ///   - kind: What it skips.
    ///   - skip: Called when it's tapped, to jump past the stretch.
    public init(_ kind: Kind, skip: @escaping () -> Void) {
        self.kind = kind
        self.skip = skip
    }

    public var body: some View {
        Button {
            taps += 1
            skip()
        } label: {
            Label(kind.title, systemImage: "forward.end.fill")
                .typography(.headline)
                .frame(minHeight: Self.height - 2 * Self.glassVerticalPadding)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .accessibilityShowsLargeContentViewer()
        .environment(\.colorScheme, .dark)
        .tint(.white)
    }
}

/// The brief glass notice that Serafin skipped a stretch by itself, such as "Skipped intro", which shows where the
/// skip pill would have.
public struct SkippedNotice: View {
    private let kind: SkipSegmentButton.Kind

    /// Creates the notice for a stretch of `kind`.
    public init(_ kind: SkipSegmentButton.Kind) {
        self.kind = kind
    }

    public var body: some View {
        Label(kind.skippedTitle, systemImage: "forward.end.fill")
            .typography(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.small)
            .frame(minHeight: SkipSegmentButton.height)
            .glassEffect(.regular, in: .capsule)
            .environment(\.colorScheme, .dark)
            .accessibilityElement(children: .combine)
    }
}

/// Measurements the player's overlays share with its controls.
public enum PlayerLayout {
    /// How far above the bottom of the safe area the skip pill and the next episode's card sit: 16 points above the
    /// scrubber. Under them are the controls' margin and the scrubber's 44 points, in the middle of a bottom bar that
    /// the glass buttons beside it make 58 points tall.
    public static let bottomBarClearance: CGFloat = Spacing.medium + (58 + 44) / 2 + Spacing.medium
}

#if DEBUG
    private struct SkipSegmentSample: View {
        private let card = MockMedia.episodes[1]

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                (MockMedia.backdropImage(for: card) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                GlassEffectContainer(spacing: Spacing.medium) {
                    VStack(alignment: .trailing, spacing: Spacing.large) {
                        ForEach(SkipSegmentButton.Kind.allCases, id: \.self) { kind in
                            SkipSegmentButton(kind) {}
                        }
                        SkippedNotice(.intro)
                    }
                }
                .padding(Spacing.medium)
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    #Preview("Light", traits: .landscapeLeft) {
        SkipSegmentSample()
    }

    #Preview("Dark", traits: .landscapeLeft) {
        SkipSegmentSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text", traits: .landscapeLeft) {
        SkipSegmentSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
