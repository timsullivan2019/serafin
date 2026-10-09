import SwiftUI

/// The glass circle that flashes on the side of the video a double tap skipped back or forward on.
///
/// Show it inside a `GlassEffectContainer`, so it materializes as it appears and dissolves as it goes.
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
            // Glass arrives by materializing in place rather than fading or growing, which also suits Reduce Motion.
            .glassEffectTransition(.materialize)
            .environment(\.colorScheme, .dark)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    private struct SkipIndicatorSample: View {
        var body: some View {
            ZStack {
                (MockMedia.backdropImage(for: MockMedia.episodes[0]) ?? Image(systemName: "film"))
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                GlassEffectContainer {
                    HStack {
                        SkipIndicator(.backward)
                        Spacer()
                        SkipIndicator(.forward)
                    }
                }
                .padding(.horizontal, Spacing.xLarge * 2)
            }
        }
    }

    #Preview("Light", traits: .landscapeLeft) {
        SkipIndicatorSample()
    }

    #Preview("Dark", traits: .landscapeLeft) {
        SkipIndicatorSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text", traits: .landscapeLeft) {
        SkipIndicatorSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
