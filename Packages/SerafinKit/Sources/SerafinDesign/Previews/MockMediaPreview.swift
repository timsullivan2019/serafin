#if DEBUG
    import CoreGraphics
    import SwiftUI

    /// The mock fixtures and their generated artwork on one screen, for review in previews and debug builds.
    public struct MockMediaPreview: View {
        /// Creates the fixture overview.
        public init() {}

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xLarge) {
                    Text(verbatim: "Mock media")
                        .typography(.largeTitle)
                    FixtureRow(title: "Continue Watching", cards: MockLibrary.continueWatching)
                    FixtureRow(title: "Next Up", cards: MockLibrary.nextUp)
                    ForEach(MockLibrary.libraries) { library in
                        FixtureGrid(library: library)
                    }
                }
                .foregroundStyle(.textPrimary)
                .padding(Spacing.medium)
            }
            .background { Color.background.ignoresSafeArea() }
        }
    }

    /// A horizontal row of 16:9 artwork with titles and progress.
    private struct FixtureRow: View {
        let title: String
        let cards: [MediaCard]
        @ScaledMetric(relativeTo: .headline) private var width = 240.0

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(verbatim: title)
                    .typography(.title)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Spacing.small) {
                        ForEach(cards) { card in
                            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                                Artwork(image: MockMedia.backdrop(for: card), aspectRatio: 16 / 9)
                                    .overlay(alignment: .bottom) { ProgressLine(progress: card.progress) }
                                    .clipShape(.rounded(.small))
                                Text(verbatim: card.title)
                                    .typography(.headline)
                                    .lineLimit(2)
                                Text(verbatim: subtitle(for: card))
                                    .typography(.caption)
                                    .foregroundStyle(.textSecondary)
                            }
                            .containerRelativeFrame(.horizontal) { length, _ in min(width, length * 0.85) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }

        private func subtitle(for card: MediaCard) -> String {
            guard let episode = card.episode else { return card.year.map(String.init) ?? "" }
            return "\(episode.seriesTitle) · S\(episode.seasonNumber) E\(episode.episodeNumber)"
        }
    }

    /// A library's posters in an adaptive grid.
    private struct FixtureGrid: View {
        let library: MediaLibrary
        @ScaledMetric(relativeTo: .headline) private var columnWidth = 104.0

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(verbatim: library.name)
                    .typography(.title)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: columnWidth), spacing: Spacing.small, alignment: .top)],
                    spacing: Spacing.medium
                ) {
                    ForEach(library.items) { card in
                        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                            Artwork(image: MockMedia.poster(for: card), aspectRatio: 2 / 3)
                                .overlay(alignment: .bottom) { ProgressLine(progress: card.progress) }
                                .clipShape(.rounded(.small))
                            Text(verbatim: card.title)
                                .typography(.caption)
                                .lineLimit(2)
                            Text(verbatim: card.year.map(String.init) ?? "")
                                .typography(.caption)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private struct Artwork: View {
        let image: CGImage?
        let aspectRatio: CGFloat

        var body: some View {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                } else {
                    Rectangle().fill(.surface)
                }
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
        }
    }

    private struct ProgressLine: View {
        let progress: Double

        var body: some View {
            if progress > 0 {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * progress, height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .padding(Spacing.xSmall)
            }
        }
    }

    #Preview("Light") {
        MockMediaPreview()
    }

    #Preview("Dark") {
        MockMediaPreview()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        MockMediaPreview()
            .dynamicTypeSize(.accessibility5)
    }
#endif
