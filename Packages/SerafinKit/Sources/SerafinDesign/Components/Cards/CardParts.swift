import SwiftUI

/// The press effect for cards: a gentle scale down while pressed.
///
/// Apply it to the `Button` or `NavigationLink` that wraps a ``PosterCard`` or ``LandscapeCard``. The scale is
/// small, so it stays under Reduce Motion, but the spring gives way to ``Motion/reduced``.
public struct CardButtonStyle: ButtonStyle {
    /// Creates the card button style.
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .serafinAnimation(value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardButtonStyle {
    /// Serafin's card press effect: a gentle scale down while pressed.
    public static var card: CardButtonStyle { CardButtonStyle() }
}

/// A card's artwork at a fixed aspect ratio, with the progress bar and played badge drawn over it.
struct CardArtwork: View {
    let card: MediaCard
    let image: Image?
    let aspectRatio: CGFloat

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtworkPlaceholder(kind: card.kind)
                }
            }
            .overlay(alignment: .bottom) {
                if card.isInProgress {
                    CardProgressBar(progress: card.progress)
                        .padding(.horizontal, Spacing.xSmall)
                        .padding(.bottom, Spacing.xSmall)
                        .padding(.top, Spacing.large)
                        .background {
                            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                        }
                }
            }
            .overlay(alignment: .topTrailing) {
                if card.isPlayed {
                    PlayedBadge()
                        .padding(Spacing.xSmall)
                }
            }
            .clipShape(.rounded(.small))
    }
}

/// What a card shows while its artwork loads, or when there is none.
struct ArtworkPlaceholder: View {
    let kind: MediaCard.Kind

    var body: some View {
        Rectangle()
            .fill(.surface)
            .overlay {
                Image(systemName: kind == .movie ? "film" : "tv")
                    .font(.system(size: 24))
                    .foregroundStyle(.textSecondary)
            }
            .accessibilityHidden(true)
    }
}

/// The thin bar along the bottom of a card's artwork that shows how much has been watched.
struct CardProgressBar: View {
    let progress: Double

    var body: some View {
        Capsule()
            .fill(.white.opacity(0.35))
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(.white)
                        .frame(width: max(proxy.size.height, proxy.size.width * progress))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}

/// The checkmark in the corner of a played item's artwork.
struct PlayedBadge: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(.black.opacity(0.55), in: .circle)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Lifts the artwork under an iPad pointer. Other platforms have no hover effect.
    func cardHoverEffect() -> some View {
        #if os(iOS)
            contentShape(.hoverEffect, .rounded(.small))
                .hoverEffect(.lift)
        #else
            self
        #endif
    }

    /// Attaches `menu` as a context menu whose preview is a larger copy of the artwork, unless the menu is empty.
    func cardContextMenu<Menu: View, Preview: View>(
        _ menu: Menu,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        modifier(CardContextMenu(menu: menu, preview: preview()))
    }
}

private struct CardContextMenu<Menu: View, Preview: View>: ViewModifier {
    let menu: Menu
    let preview: Preview

    func body(content: Content) -> some View {
        // The menu type never changes for a given card, so this branch keeps a stable identity.
        if Menu.self == EmptyView.self {
            content
        } else {
            content.contextMenu {
                menu
            } preview: {
                preview
            }
        }
    }
}
