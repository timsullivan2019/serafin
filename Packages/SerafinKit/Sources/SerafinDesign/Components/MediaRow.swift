import SwiftUI

/// How wide the cards in a ``MediaRow`` are.
///
/// A row shows as many whole cards as fit at about the style's comfortable width, with the next one peeking in, so a
/// resized iPad window gains or loses cards instead of stretching or squeezing them.
public enum MediaRowStyle: Sendable {
    /// Posters: a little over three across on iPhone, six on an 11-inch iPad in portrait.
    case posters
    /// Landscape thumbnails: one large card with the next peeking in on iPhone, three on an 11-inch iPad in portrait.
    /// On a phone every style shows the same slice of the next card.
    case landscape
    /// Cast and crew: a little over three across on iPhone, seven on an 11-inch iPad in portrait.
    case people
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
                // An eager stack: rows hold tens of cards, and a lazy stack would size the row from the first few
                // cards and clip a taller title further along.
                HStack(alignment: .top, spacing: Spacing.small) {
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
            .modifier(PointerHighlight())
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

    private func cardWidth(in length: CGFloat) -> CGFloat {
        RowSizing(style: style, isRegular: sizeClass == .regular, isLarge: dynamicTypeSize.isAccessibilitySize)
            .cardWidth(in: length)
    }
}

/// How many cards a ``MediaRow`` fits across: as many whole cards as fit at about a comfortable width, at least one,
/// plus a slice of the next so the row reads as scrollable.
///
/// The comfortable widths keep the familiar counts on iPhone and on an 11-inch iPad in portrait, and let every other window
/// size, such as a Stage Manager window, follow from its width. Accessibility text sizes get fewer, wider cards so
/// titles wrap at word breaks instead of mid-word.
struct RowSizing: Equatable {
    /// The card width the row aims for, in points.
    let comfortableWidth: CGFloat
    /// How much of the next card shows, as a fraction of a card.
    let peek: CGFloat

    init(style: MediaRowStyle, isRegular: Bool, isLarge: Bool) {
        (comfortableWidth, peek) =
            switch (style, isRegular, isLarge) {
            case (.posters, false, false): (92, 0.3)
            case (.posters, false, true): (200, 0.6)
            case (.posters, true, false): (116, 0.3)
            case (.posters, true, true): (220, 0.3)
            // Every row on a phone shows the same slice of its next card, so no row looks unlike the others.
            case (.landscape, false, false): (240, 0.3)
            case (.landscape, false, true): (240, 0.05)
            case (.landscape, true, false): (230, 0.2)
            case (.landscape, true, true): (320, 0.2)
            case (.people, false, false): (92, 0.3)
            case (.people, false, true): (140, 0.1)
            case (.people, true, false): (96, 0.3)
            case (.people, true, true): (200, 0.6)
            }
    }

    /// The number of cards across `length`, the row's visible width, counting the slice of the next card.
    func across(in length: CGFloat) -> CGFloat {
        let whole = ((length - Spacing.medium) / (comfortableWidth + Spacing.small)).rounded(.down)
        return max(whole, 1) + peek
    }

    /// The card width that fits ``across(in:)`` cards, and the gaps between them, in `length`.
    func cardWidth(in length: CGFloat) -> CGFloat {
        let across = across(in: length)
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
