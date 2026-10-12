import SwiftUI

/// A 2:3 poster with the title and year beneath, for library grids and home rows.
///
/// An episode shows its series' poster, so the card names the series and gives the episode's code, such as
/// "S2 E4", in place of the year.
///
/// The card fills the width it is given. Wrap it in a `Button` or `NavigationLink` with `.buttonStyle(.card)` for
/// the press effect. Pass menu items for a context menu whose preview is a larger copy of the poster.
public struct PosterCard<Menu: View>: View {
    private let card: MediaCard
    private let artwork: Image?
    private let zoomNamespace: Namespace.ID?
    private let zoomID: String?
    private let menu: Menu

    /// Creates a poster card with a context menu.
    ///
    /// - Parameters:
    ///   - card: The item to show.
    ///   - artwork: The poster, or nil while it loads.
    ///   - zoomNamespace: The namespace for a zoom transition into the item's detail screen, keyed by `zoomID`. Pass
    ///     nil for no zoom.
    ///   - zoomID: What the zoom is keyed by: the card's ``MediaCard/id`` when nil. A screen that can show the same
    ///     item in more than one row gives each card its own, so the screen zooms out of the card that was tapped.
    ///   - menu: The context menu's items, such as play, mark played and favourite.
    public init(
        card: MediaCard,
        artwork: Image?,
        zoomNamespace: Namespace.ID? = nil,
        zoomID: String? = nil,
        @ViewBuilder menu: () -> Menu
    ) {
        self.card = card
        self.artwork = artwork
        self.zoomNamespace = zoomNamespace
        self.zoomID = zoomID
        self.menu = menu()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            CardArtwork(card: card, image: artwork, aspectRatio: 2 / 3)
                .cardZoomSource(id: zoomID ?? card.id, in: zoomNamespace)
                .cardHoverEffect()
            VStack(alignment: .leading, spacing: 2) {
                // Always as tall as two lines, so the years line up across a row whatever each title's length.
                Text(card.posterTitle)
                    .typography(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .modifier(CardTitleLines(standard: 2, reservesSpace: true))
                if let caption = card.posterCaption {
                    Text(caption)
                        .typography(.caption)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        // Cards always take their natural height, so a long title never squeezes the artwork in a row.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .cardContextMenu(menu) {
            CardArtwork(card: card, image: artwork, aspectRatio: 2 / 3)
                .frame(width: 240)
        }
    }
}

extension PosterCard where Menu == EmptyView {
    /// Creates a poster card without a context menu.
    ///
    /// - Parameters:
    ///   - card: The item to show.
    ///   - artwork: The poster, or nil while it loads.
    ///   - zoomNamespace: The namespace for a zoom transition into the item's detail screen.
    public init(card: MediaCard, artwork: Image?, zoomNamespace: Namespace.ID? = nil) {
        self.init(card: card, artwork: artwork, zoomNamespace: zoomNamespace) { EmptyView() }
    }
}

#if DEBUG
    private struct PosterCardSample: View {
        var body: some View {
            HStack(alignment: .top, spacing: Spacing.small) {
                ForEach([MockMedia.movies[1], MockMedia.movies[7], MockMedia.movies[0]]) { card in
                    Button {
                    } label: {
                        PosterCard(card: card, artwork: MockMedia.posterImage(for: card)) {
                            PreviewMenuItems()
                        }
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(Spacing.medium)
            .background(Color.background)
        }
    }

    #Preview("Light") {
        PosterCardSample()
    }

    #Preview("Dark") {
        PosterCardSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        PosterCardSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
