import SwiftUI

/// A 16:9 thumbnail with the series and episode code, title and time, for Continue Watching, Next Up and season
/// lists.
///
/// For an episode the line above the title reads "Caminandes · S1 E2"; for a movie it is the year. The line below
/// shows the time left when the item is in progress, otherwise the running time. The card fills the width it is
/// given. Wrap it in a `Button` or `NavigationLink` with `.buttonStyle(.card)` for the press effect: a button that
/// plays, as in Continue Watching, can have the player grow out of the artwork.
public struct LandscapeCard<Menu: View>: View {
    private let card: MediaCard
    private let artwork: Image?
    private let zoomNamespace: Namespace.ID?
    private let playZoomNamespace: Namespace.ID?
    private let showsPlayedBadge: Bool
    private let menu: Menu

    /// Creates a landscape card with a context menu.
    ///
    /// - Parameters:
    ///   - card: The item to show.
    ///   - artwork: The thumbnail, or nil while it loads.
    ///   - zoomNamespace: The namespace for a zoom transition into the item's detail screen, keyed by the
    ///     card's ``MediaCard/id``. Pass nil for no zoom.
    ///   - playZoomNamespace: For a card that plays when tapped, the namespace in which the artwork is the source of
    ///     the player's zoom, keyed by ``CardPlayZoom/id(for:)``. Pass nil for no zoom.
    ///   - showsPlayedBadge: Whether a played item shows its check, which Continue Watching leaves off since its time
    ///     left says the item isn't finished.
    ///   - menu: The context menu's items.
    public init(
        card: MediaCard,
        artwork: Image?,
        zoomNamespace: Namespace.ID? = nil,
        playZoomNamespace: Namespace.ID? = nil,
        showsPlayedBadge: Bool = true,
        @ViewBuilder menu: () -> Menu
    ) {
        self.card = card
        self.artwork = artwork
        self.zoomNamespace = zoomNamespace
        self.playZoomNamespace = playZoomNamespace
        self.showsPlayedBadge = showsPlayedBadge
        self.menu = menu()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            CardArtwork(card: card, image: artwork, aspectRatio: 16 / 9, showsPlayedBadge: showsPlayedBadge)
                .cardZoomSource(id: card.id, in: zoomNamespace)
                .cardZoomSource(id: CardPlayZoom.id(for: card.id), in: playZoomNamespace)
                .cardHoverEffect()
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow = card.eyebrowText {
                    Text(eyebrow)
                        .typography(.caption)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }
                Text(card.title)
                    .typography(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .modifier(CardTitleLines(standard: 2))
                if let time = card.remainingText ?? card.runtimeText {
                    Text(time)
                        .typography(.caption)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        // Cards always take their natural height, so a long title never squeezes the artwork in a row.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        // A card without its played check doesn't say Played either.
        .accessibilityLabel(showsPlayedBadge ? card.accessibilityLabel : card.accessibilityLabelWithoutPlayed)
        .cardContextMenu(menu) {
            CardArtwork(card: card, image: artwork, aspectRatio: 16 / 9, showsPlayedBadge: showsPlayedBadge)
                .frame(width: 320)
        }
    }
}

extension LandscapeCard where Menu == EmptyView {
    /// Creates a landscape card without a context menu.
    ///
    /// - Parameters:
    ///   - card: The item to show.
    ///   - artwork: The thumbnail, or nil while it loads.
    ///   - zoomNamespace: The namespace for a zoom transition into the item's detail screen.
    ///   - showsPlayedBadge: Whether a played item shows its check.
    public init(card: MediaCard, artwork: Image?, zoomNamespace: Namespace.ID? = nil, showsPlayedBadge: Bool = true) {
        self.init(card: card, artwork: artwork, zoomNamespace: zoomNamespace, showsPlayedBadge: showsPlayedBadge) {
            EmptyView()
        }
    }
}

#if DEBUG
    private struct LandscapeCardSample: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.large) {
                ForEach(Array(MockLibrary.continueWatching.prefix(2)) + [MockMedia.episodes[0]]) { card in
                    Button {
                    } label: {
                        LandscapeCard(card: card, artwork: MockMedia.backdropImage(for: card)) {
                            PreviewMenuItems()
                        }
                    }
                    .buttonStyle(.card)
                    .frame(width: 300)
                }
            }
            .padding(Spacing.medium)
            .background(Color.background)
        }
    }

    #Preview("Light") {
        ScrollView { LandscapeCardSample() }
    }

    #Preview("Dark") {
        ScrollView { LandscapeCardSample() }
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        ScrollView { LandscapeCardSample() }
            .dynamicTypeSize(.accessibility5)
    }
#endif
