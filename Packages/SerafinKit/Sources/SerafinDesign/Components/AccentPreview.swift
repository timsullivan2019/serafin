import SwiftUI

/// The accent colour on the parts of Serafin that take it, for the accent colour screen: the foot of a detail screen
/// with its play pill, and the tab bar floating over it with its selected tab.
///
/// It draws from the environment's ``SwiftUI/EnvironmentValues/accent``, so choosing another colour shows at once.
/// It doesn't respond to touch: it's only there to show the colour.
public struct AccentPreview: View {
    /// A tab in the preview's tab bar.
    public struct TabItem: Hashable, Sendable {
        /// The tab's title, already localized.
        public let title: String
        /// The tab's SF Symbol, such as "house", which shows in its filled variant.
        public let systemImage: String

        /// Creates a tab.
        public init(title: String, systemImage: String) {
            self.title = title
            self.systemImage = systemImage
        }
    }

    private let card: MediaCard
    private let artwork: Image?
    private let tabs: [TabItem]
    private let searchTitle: String
    @Environment(\.accent) private var accent

    /// Creates a preview.
    ///
    /// - Parameters:
    ///   - card: The item whose play pill shows, as ``HeroHeader`` would title it.
    ///   - artwork: The backdrop behind the pill and the tab bar.
    ///   - tabs: The tab bar's tabs, the first of them selected.
    ///   - searchTitle: The search tab's name, for VoiceOver.
    public init(card: MediaCard, artwork: Image?, tabs: [TabItem], searchTitle: String) {
        self.card = card
        self.artwork = artwork
        self.tabs = tabs
        self.searchTitle = searchTitle
    }

    public var body: some View {
        VStack(spacing: Spacing.large) {
            PlayPill(
                title: HeroHeader.playTitle(for: card),
                progress: card.isInProgress ? card.progress : nil,
                tint: accent
            )
            tabBar
        }
        .padding(.top, Spacing.xLarge)
        .padding([.horizontal, .bottom], Spacing.medium)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.surface)
                artwork?
                    .resizable()
                    .scaledToFill()
                LinearGradient(
                    colors: [.black.opacity(0.1), .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            }
        }
        .clipped()
        .allowsHitTesting(false)
    }

    /// The tab bar as iOS draws it: the tabs in one glass capsule, the selected one lit in the accent, and search in
    /// its own glass circle beside them.
    private var tabBar: some View {
        GlassEffectContainer {
            HStack(spacing: Spacing.xSmall) {
                HStack(spacing: 0) {
                    ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                        TabCell(tab: tab, isSelected: index == 0, accent: accent)
                    }
                }
                .padding(Spacing.xxSmall)
                .glassEffect(.regular, in: .capsule)
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.primary)
                    .frame(width: 54, height: 54)
                    .glassEffect(.regular, in: .circle)
                    .accessibilityLabel(searchTitle)
            }
        }
    }
}

/// One tab: its symbol over its title, in the accent when selected.
private struct TabCell: View {
    let tab: AccentPreview.TabItem
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(spacing: 2) {
            // Filled whether or not it's selected, as the tab bar draws its symbols.
            Image(systemName: "\(tab.systemImage).fill")
                .font(.title3.weight(.medium))
            Text(tab.title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(isSelected ? accent : .primary)
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.xxSmall)
        .background {
            if isSelected {
                Capsule().fill(.primary.opacity(0.08))
            }
        }
    }
}

#if DEBUG
    private struct AccentPreviewSample: View {
        var body: some View {
            List {
                Section {
                    AccentPreview(
                        card: MockMedia.movies[1],
                        artwork: MockMedia.backdropImage(for: MockMedia.movies[1]),
                        tabs: [
                            AccentPreview.TabItem(title: "Home", systemImage: "house"),
                            AccentPreview.TabItem(title: "Library", systemImage: "square.grid.2x2"),
                        ],
                        searchTitle: "Search"
                    )
                    .listRowInsets(EdgeInsets())
                }
            }
            .environment(\.accent, Accent.orange.color)
        }
    }

    #Preview("Light") {
        AccentPreviewSample()
    }

    #Preview("Dark") {
        AccentPreviewSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        AccentPreviewSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
