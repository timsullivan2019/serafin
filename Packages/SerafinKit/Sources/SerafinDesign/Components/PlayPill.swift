import SwiftUI

/// The play pill on a detail screen's hero: "Play", "Play S2 E4" or "Resume · 32 min left" in white on tinted glass,
/// with a thin progress line inside while the item is in progress.
///
/// ``HeroHeader`` wraps it in its play button, tinted from the artwork; the accent colour screen shows it tinted with
/// each accent.
public struct PlayPill: View {
    private let title: String
    private let progress: Double?
    private let tint: Color

    /// Creates a pill.
    ///
    /// - Parameters:
    ///   - title: What it says, such as ``HeroHeader/playTitle(for:nextEpisode:)`` gives.
    ///   - progress: How far in the item is, from 0 to 1, for the line inside the pill, or nil for none.
    ///   - tint: The glass tint.
    public init(title: String, progress: Double? = nil, tint: Color) {
        self.title = title
        self.progress = progress
        self.tint = tint
    }

    public var body: some View {
        // An HStack rather than a Label, whose icon a list row would recolour.
        HStack(spacing: Spacing.xSmall) {
            Image(systemName: "play.fill")
            Text(title)
        }
        .typography(.headline)
        .foregroundStyle(.white)
        .padding(.horizontal, Spacing.large)
        .padding(.vertical, Spacing.small)
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) {
            if let progress {
                // How far in, as a thin line inside the pill.
                Capsule()
                    .fill(.white.opacity(0.3))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule().fill(.white).frame(width: proxy.size.width * min(max(progress, 0), 1))
                        }
                    }
                    .frame(height: 3)
                    .padding(.horizontal, Spacing.large)
                    .padding(.bottom, 7)
                    .accessibilityHidden(true)
            }
        }
        .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        .contentShape(.capsule)
    }
}

#if DEBUG
    private struct PlayPillSample: View {
        var body: some View {
            VStack(spacing: Spacing.medium) {
                PlayPill(title: "Play", tint: MockMedia.tint(for: MockMedia.movies[1]))
                PlayPill(title: "Resume · 32 min left", progress: 0.4, tint: MockMedia.tint(for: MockMedia.movies[2]))
                PlayPill(title: "Play S1 E2", tint: ArtworkTint.neutral)
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity)
            .background {
                MockMedia.backdropImage(for: MockMedia.movies[1])?
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
        }
    }

    #Preview("Light") {
        PlayPillSample()
    }

    #Preview("Dark") {
        PlayPillSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        PlayPillSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
