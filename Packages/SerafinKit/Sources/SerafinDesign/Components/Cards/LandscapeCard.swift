import SwiftUI

/// A 16:9 thumbnail with the series and episode code, title and time, for Continue Watching, Next Up and season
/// lists.
///
/// For an episode the line above the title reads "Caminandes · S1 E2"; for a movie it is the year. The line below
/// shows the time left when the item is in progress, otherwise the running time. The card fills the width it is
/// given. Wrap it in a `Button` or `NavigationLink` with `.buttonStyle(.card)` for the press effect.
public struct LandscapeCard<Menu: View>: View {
    private let card: MediaCard
    private let artwork: Image?
    private let menu: Menu

    /// Creates a landscape card with a context menu.
    ///
    /// - Parameters:
    ///   - card: The item to show.
    ///   - artwork: The thumbnail, or nil while it loads.
    ///   - menu: The context menu's items.
    public init(card: MediaCard, artwork: Image?, @ViewBuilder menu: () -> Menu) {
        self.card = card
        self.artwork = artwork
        self.menu = menu()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            CardArtwork(card: card, image: artwork, aspectRatio: 16 / 9)
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
                    .lineLimit(2)
                if let time = card.remainingText ?? card.runtimeText {
                    Text(time)
                        .typography(.caption)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
        .cardContextMenu(menu) {
            CardArtwork(card: card, image: artwork, aspectRatio: 16 / 9)
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
    public init(card: MediaCard, artwork: Image?) {
        self.init(card: card, artwork: artwork) { EmptyView() }
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
