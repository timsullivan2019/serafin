import SwiftUI

/// The glass pill that offers to skip the intro, a recap, the credits, a preview or an advert while it plays, like
/// Skip Intro in the TV app.
///
/// The player shows it above its bottom bar for as long as the stretch plays, whether or not the other controls are
/// showing. It materializes when the stretch starts and dissolves when it ends or is skipped. Always dark, like the
/// rest of the player.
public struct SkipPill: View {
    /// What the pill skips.
    public enum Kind: Hashable, Sendable {
        /// The opening titles.
        case intro
        /// A recap of earlier episodes.
        case recap
        /// The closing credits.
        case credits
        /// A preview of what comes next.
        case preview
        /// An advert.
        case advert

        /// The pill's words, such as "Skip Intro".
        public var title: String {
            switch self {
            case .intro: String(localized: "Skip Intro", bundle: .module, comment: "Button that skips the intro.")
            case .recap: String(localized: "Skip Recap", bundle: .module, comment: "Button that skips a recap.")
            case .credits:
                String(localized: "Skip Credits", bundle: .module, comment: "Button that skips the closing credits.")
            case .preview:
                String(localized: "Skip Preview", bundle: .module, comment: "Button that skips a preview.")
            case .advert: String(localized: "Skip Ad", bundle: .module, comment: "Button that skips an advert.")
            }
        }
    }

    private let kind: Kind?
    private let skip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the pill.
    ///
    /// - Parameters:
    ///   - kind: What is playing that can be skipped, or nil to show nothing.
    ///   - skip: Called when the pill is tapped, to jump to the end of the stretch.
    public init(_ kind: Kind?, skip: @escaping () -> Void) {
        self.kind = kind
        self.skip = skip
    }

    public var body: some View {
        GlassEffectContainer {
            if let kind {
                Button(action: skip) {
                    Label(kind.title, systemImage: "forward.end.fill")
                        .typography(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, Spacing.medium)
                        .frame(minHeight: 44)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                // White glass, like the system player's play buttons, so it reads over any picture.
                .glassEffect(.regular.tint(.white).interactive(), in: .capsule)
                .glassEffectTransition(.materialize)
            }
        }
        .animation(Motion.animation(reduceMotion: reduceMotion), value: kind)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

/// Measurements the player's overlays share with its controls.
public enum PlayerLayout {
    /// How far above the bottom of the safe area the controls' bottom bar reaches, so an overlay such as the skip
    /// pill can sit just above it.
    public static let bottomBarClearance: CGFloat = Spacing.medium + 44 + Spacing.medium
}

#if DEBUG
    private struct SkipPillSample: View {
        @State private var kind: SkipPill.Kind? = .intro
        private let card = MockMedia.episodes[1]

        var body: some View {
            ZStack(alignment: .bottomTrailing) {
                (MockMedia.backdropImage(for: card) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .onTapGesture { kind = kind == nil ? .credits : nil }
                SkipPill(kind) { kind = nil }
                    .padding(.trailing, Spacing.medium)
                    .padding(.bottom, PlayerLayout.bottomBarClearance)
            }
        }
    }

    #Preview("Light", traits: .landscapeLeft) {
        SkipPillSample()
    }

    #Preview("Dark", traits: .landscapeLeft) {
        SkipPillSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text", traits: .landscapeLeft) {
        SkipPillSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
