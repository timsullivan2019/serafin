#if DEBUG
    import CoreGraphics
    import SwiftUI

    /// Every Serafin design token on one screen, for review in previews and in debug builds of the app.
    public struct TokensPreview: View {
        /// Creates the token overview.
        public init() {}

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xLarge) {
                    Text(verbatim: "Serafin tokens")
                        .typography(.largeTitle)
                    TokenSection(title: "Colour") { ColourSwatches() }
                    TokenSection(title: "Typography") { TypographySamples() }
                    TokenSection(title: "Spacing") { SpacingScale() }
                    TokenSection(title: "Radius") { RadiusScale() }
                    TokenSection(title: "Motion") { MotionSample() }
                    TokenSection(title: "Artwork tint") { ArtworkTintSamples() }
                }
                .foregroundStyle(.textPrimary)
                .padding(Spacing.medium)
            }
            .background { Color.background.ignoresSafeArea() }
        }
    }

    private struct TokenSection<Content: View>: View {
        let title: String
        @ViewBuilder let content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(verbatim: title)
                    .typography(.title)
                content
            }
        }
    }

    private struct ColourSwatches: View {
        @ScaledMetric(relativeTo: .caption) private var columnWidth = 104.0
        private let swatches: [(name: String, colour: Color)] = [
            ("background", .background),
            ("surface", .surface),
            ("textPrimary", .textPrimary),
            ("textSecondary", .textSecondary),
            ("accentFallback", .accentFallback),
        ]

        var body: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: columnWidth), alignment: .top)], spacing: Spacing.medium) {
                ForEach(swatches, id: \.name) { swatch in
                    VStack(spacing: Spacing.xSmall) {
                        RoundedRectangle.rounded(.small)
                            .fill(swatch.colour)
                            .overlay { RoundedRectangle.rounded(.small).strokeBorder(.textSecondary, lineWidth: 0.5) }
                            .frame(height: 64)
                        Text(verbatim: swatch.name)
                            .typography(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
        }
    }

    private struct TypographySamples: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ForEach(Typography.allCases, id: \.self) { style in
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(verbatim: "Big Buck Bunny")
                            .typography(style)
                        Text(verbatim: String(describing: style))
                            .typography(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
        }
    }

    private struct SpacingScale: View {
        private let steps: [(name: String, value: CGFloat)] = [
            ("xxSmall", Spacing.xxSmall),
            ("xSmall", Spacing.xSmall),
            ("small", Spacing.small),
            ("medium", Spacing.medium),
            ("large", Spacing.large),
            ("xLarge", Spacing.xLarge),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                ForEach(steps, id: \.name) { step in
                    HStack(spacing: Spacing.small) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.accentFallback)
                            .frame(width: step.value, height: Spacing.small)
                            .frame(width: Spacing.xLarge, alignment: .leading)
                        Text(verbatim: "\(step.name) · \(Int(step.value)) pt")
                            .typography(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
        }
    }

    private struct RadiusScale: View {
        @ScaledMetric(relativeTo: .caption) private var columnWidth = 88.0

        var body: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: columnWidth), alignment: .top)], spacing: Spacing.medium) {
                ForEach(Radius.allCases, id: \.self) { radius in
                    VStack(spacing: Spacing.xSmall) {
                        RoundedRectangle.rounded(radius)
                            .fill(.surface)
                            .overlay { RoundedRectangle.rounded(radius).strokeBorder(.textSecondary, lineWidth: 0.5) }
                            .frame(width: 80, height: 80)
                        Text(verbatim: "\(radius) · \(Int(radius.rawValue)) pt")
                            .typography(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
            }
        }
    }

    private struct MotionSample: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isOn = false

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Capsule()
                    .fill(.surface)
                    .frame(height: 44)
                    .overlay(alignment: isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.accentFallback)
                            .padding(Spacing.xxSmall)
                    }
                    .serafinAnimation(value: isOn)
                Button {
                    isOn.toggle()
                } label: {
                    Text(verbatim: reduceMotion ? "Animate (Reduce Motion on)" : "Animate")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private struct ArtworkTintSamples: View {
        @ScaledMetric(relativeTo: .headline) private var columnWidth = 140.0
        private let artworks: [(name: String, image: CGImage?)] = [
            ("Crimson", SampleArtwork.gradient(from: (0.55, 0.05, 0.12), to: (0.20, 0.02, 0.15))),
            ("Midnight", SampleArtwork.gradient(from: (0.02, 0.06, 0.22), to: (0.01, 0.15, 0.25))),
            ("Paper", SampleArtwork.gradient(from: (0.98, 0.97, 0.94), to: (0.90, 0.88, 0.84))),
            ("Meadow", SampleArtwork.gradient(from: (0.55, 0.78, 0.35), to: (0.95, 0.85, 0.30))),
        ]

        var body: some View {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: columnWidth), alignment: .top)], spacing: Spacing.medium) {
                ForEach(artworks, id: \.name) { artwork in
                    if let image = artwork.image {
                        TintedArtwork(image: image)
                    }
                }
            }
        }
    }

    private struct TintedArtwork: View {
        let image: CGImage

        var body: some View {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay(alignment: .bottom) {
                    Label {
                        Text(verbatim: "Play")
                    } icon: {
                        Image(systemName: "play.fill")
                    }
                    .typography(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.vertical, Spacing.small)
                    .glassEffect(.regular.tint(ArtworkTint.color(for: image)), in: .capsule)
                    .padding(Spacing.small)
                }
                .clipShape(.rounded(.small))
        }
    }

    /// Generated stand-ins for artwork, so the preview needs no image files.
    private enum SampleArtwork {
        static func gradient(
            from top: (Double, Double, Double),
            to bottom: (Double, Double, Double)
        ) -> CGImage? {
            let width = 200
            let height = 300
            guard
                let space = CGColorSpace(name: CGColorSpace.sRGB),
                let context = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ),
                let gradient = CGGradient(
                    colorSpace: space,
                    colorComponents: [top.0, top.1, top.2, 1, bottom.0, bottom.1, bottom.2, 1].map { CGFloat($0) },
                    locations: [0, 1],
                    count: 2
                )
            else { return nil }
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
            return context.makeImage()
        }
    }

    #Preview("Light") {
        TokensPreview()
    }

    #Preview("Dark") {
        TokensPreview()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TokensPreview()
            .dynamicTypeSize(.accessibility5)
    }
#endif
