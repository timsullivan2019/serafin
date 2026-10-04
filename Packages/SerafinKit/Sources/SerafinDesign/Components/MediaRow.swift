import SwiftUI

/// How wide the cards in a ``MediaRow`` are.
public enum MediaRowStyle: Sendable {
    /// Posters: a little over three across on iPhone, six on iPad.
    case posters
    /// Landscape thumbnails: one large card with the next peeking in on iPhone, three on iPad.
    case landscape
}

/// A titled row of cards that scrolls sideways and settles on card edges, for the home screen and detail pages.
///
/// When `seeAll` is given, the title becomes a button with a chevron, the pattern Apple's TV and Music apps use
/// for opening the whole collection.
public struct MediaRow<Item: Identifiable, Card: View>: View {
    private let title: String
    private let style: MediaRowStyle
    private let items: [Item]
    private let seeAll: (() -> Void)?
    private let card: (Item) -> Card
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - title: The row's title, already localized.
    ///   - style: How wide the cards are.
    ///   - items: The items to show.
    ///   - seeAll: Called when the title is tapped. Pass nil for a plain title.
    ///   - card: Builds the card for one item, usually a ``PosterCard`` or ``LandscapeCard`` in a button.
    public init(
        _ title: String,
        style: MediaRowStyle,
        items: [Item],
        seeAll: (() -> Void)? = nil,
        @ViewBuilder card: @escaping (Item) -> Card
    ) {
        self.title = title
        self.style = style
        self.items = items
        self.seeAll = seeAll
        self.card = card
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            header
                .padding(.horizontal, Spacing.medium)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Spacing.small) {
                    ForEach(items) { item in
                        card(item)
                            .containerRelativeFrame(.horizontal) { length, _ in cardWidth(in: length) }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, Spacing.medium, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder private var header: some View {
        if let seeAll {
            Button(action: seeAll) {
                HStack(spacing: Spacing.xxSmall) {
                    Text(title)
                        .typography(.title)
                        .foregroundStyle(.textPrimary)
                    Image(systemName: "chevron.right")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.textSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(
                String(localized: "Shows everything in this row", bundle: .module, comment: "Hint on a row title.")
            )
        } else {
            Text(title)
                .typography(.title)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// The width that shows the style's number of cards across, the last one peeking in. Accessibility text
    /// sizes get fewer, wider cards so titles wrap at word breaks instead of mid-word.
    private func cardWidth(in length: CGFloat) -> CGFloat {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let across: CGFloat =
            switch (style, sizeClass == .regular) {
            case (.posters, true): isLarge ? 3.3 : 6.3
            case (.posters, false): isLarge ? 1.6 : 3.3
            case (.landscape, true): isLarge ? 2.2 : 3.2
            case (.landscape, false): isLarge ? 1.05 : 1.15
            }
        let gaps = Spacing.small * across.rounded(.down)
        return (length - Spacing.medium - gaps) / across
    }
}

#if DEBUG
    private struct MediaRowSample: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xLarge) {
                    MediaRow("Continue Watching", style: .landscape, items: MockLibrary.continueWatching) { card in
                        Button {
                        } label: {
                            LandscapeCard(card: card, artwork: MockMedia.backdropImage(for: card))
                        }
                        .buttonStyle(.card)
                    }
                    MediaRow("Movies", style: .posters, items: MockMedia.movies, seeAll: {}) { card in
                        Button {
                        } label: {
                            PosterCard(card: card, artwork: MockMedia.posterImage(for: card))
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.vertical, Spacing.medium)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        MediaRowSample()
    }

    #Preview("Dark") {
        MediaRowSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        MediaRowSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
