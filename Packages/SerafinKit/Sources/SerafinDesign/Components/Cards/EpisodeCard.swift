import SwiftUI

/// An episode on its show's page, as the TV app lays them out: a 16:9 still with a play glyph and the time, "EPISODE 3",
/// the title and a two-line synopsis, with a progress bar while it's part way through and a check once it's watched.
///
/// Tapping the card plays the episode. Touching and holding it, or tapping the ellipsis beside its number, opens its
/// menu. The card fills the width it is given.
public struct EpisodeCard<Menu: View>: View {
    private let card: MediaCard
    private let artwork: Image?
    private let zoomNamespace: Namespace.ID?
    private let playZoomNamespace: Namespace.ID?
    private let reservesSynopsisSpace: Bool
    private let play: () -> Void
    private let menu: Menu
    @State private var playCount = 0

    /// Creates an episode card.
    ///
    /// - Parameters:
    ///   - card: The episode.
    ///   - artwork: The still, or nil while it loads.
    ///   - zoomNamespace: The namespace for a zoom transition into the episode's own screen, keyed by the card's
    ///     ``MediaCard/id``, for when the menu opens it. Pass nil for no zoom.
    ///   - playZoomNamespace: The namespace in which the still is the source of the player's zoom, keyed by
    ///     ``CardPlayZoom/id(for:)``, so the player grows out of it. Pass nil for no zoom.
    ///   - reservesSynopsisSpace: Whether the card keeps room for a full title and synopsis even when its own are
    ///     shorter or missing, so every card in a row or grid is the same height.
    ///   - play: Called when the card is tapped.
    ///   - menu: The items of the card's menu.
    public init(
        card: MediaCard,
        artwork: Image?,
        zoomNamespace: Namespace.ID? = nil,
        playZoomNamespace: Namespace.ID? = nil,
        reservesSynopsisSpace: Bool = false,
        play: @escaping () -> Void,
        @ViewBuilder menu: () -> Menu
    ) {
        self.card = card
        self.artwork = artwork
        self.zoomNamespace = zoomNamespace
        self.playZoomNamespace = playZoomNamespace
        self.reservesSynopsisSpace = reservesSynopsisSpace
        self.play = play
        self.menu = menu()
    }

    public var body: some View {
        Button {
            playCount += 1
            play()
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                EpisodeStill(card: card, image: artwork)
                    .cardZoomSource(id: card.id, in: zoomNamespace)
                    .cardZoomSource(id: CardPlayZoom.id(for: card.id), in: playZoomNamespace)
                    .cardHoverEffect()
                EpisodeText(card: card, reservesSpace: reservesSynopsisSpace)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.card)
        .sensoryFeedback(.impact(weight: .medium), trigger: playCount)
        .accessibilityLabel(card.episodeAccessibilityLabel)
        .accessibilityHint(
            String(
                localized: "Plays the episode", bundle: .module, comment: "Hint on an episode card on a show's page.")
        )
        .modifier(Synopsis(text: card.overview))
        // Beside the number rather than inside the button, so it opens the menu instead of playing.
        .overlay(alignment: Alignment(horizontal: .trailing, vertical: .episodeCaption)) {
            if Menu.self != EmptyView.self {
                SwiftUI.Menu {
                    menu
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        // No wider than its button at any text size, so it never reaches into the next card.
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .modifier(PointerHighlight())
                .alignmentGuide(.episodeCaption) { $0[VerticalAlignment.center] }
                // The glyph's right edge lines up with the still's.
                .padding(.trailing, -Spacing.small)
                .accessibilityLabel(
                    String(
                        localized: "More for \(card.title)", bundle: .module,
                        comment:
                            "Spoken label of the ellipsis button that opens an episode's menu, such as More for Silver Blaze."
                    )
                )
            }
        }
        .cardContextMenu(menu) {
            EpisodeStill(card: card, image: artwork)
                .frame(width: 320)
        }
    }
}

extension EpisodeCard where Menu == EmptyView {
    /// Creates an episode card without a menu.
    ///
    /// - Parameters:
    ///   - card: The episode.
    ///   - artwork: The still, or nil while it loads.
    ///   - play: Called when the card is tapped.
    public init(card: MediaCard, artwork: Image?, play: @escaping () -> Void) {
        self.init(card: card, artwork: artwork, play: play) { EmptyView() }
    }
}

extension VerticalAlignment {
    private enum EpisodeCaption: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.top]
        }
    }

    /// The middle of an episode card's number line, which its menu button sits beside.
    fileprivate static let episodeCaption = VerticalAlignment(EpisodeCaption.self)
}

/// The still with the play glyph and the time along its bottom, the progress bar beside them while part watched, and
/// the check once watched.
private struct EpisodeStill: View {
    let card: MediaCard
    let image: Image?

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtworkPlaceholder(kind: .episode)
                }
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: Spacing.xSmall) {
                    HStack(spacing: Spacing.xxSmall) {
                        Image(systemName: "play.fill")
                            .imageScale(.small)
                        if let time = card.remainingText ?? card.runtimeText {
                            Text(time)
                        }
                    }
                    .typography(.caption)
                    .fontWeight(.semibold)
                    // Large, but leaving room on the still for the progress bar beside it.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
                    if card.isInProgress {
                        CardProgressBar(progress: card.progress)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, Spacing.xSmall)
                .padding(.bottom, Spacing.xSmall)
                .padding(.top, Spacing.large)
                .background {
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                }
            }
            .overlay(alignment: .topTrailing) {
                if card.isWatched {
                    PlayedBadge()
                        .padding(Spacing.xSmall)
                }
            }
            .clipShape(.rounded(.small))
            .accessibilityHidden(true)
    }
}

/// "EPISODE 3", the title and two lines of synopsis.
private struct EpisodeText: View {
    let card: MediaCard
    /// Whether the title and synopsis keep their full height when shorter or missing.
    let reservesSpace: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let caption = card.episodeCaption {
                Text(caption)
                    .typography(.caption)
                    .fontWeight(.semibold)
                    .textCase(.uppercase)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .alignmentGuide(.episodeCaption) { $0[VerticalAlignment.center] }
                    // Clear of the menu button beside it.
                    .padding(.trailing, Spacing.xLarge)
            }
            Text(card.title)
                .typography(.cardTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(isLarge ? 3 : 1, reservesSpace: reservesSpace)
            if card.overview != nil || reservesSpace {
                Text(card.overview ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(isLarge ? 4 : 2, reservesSpace: reservesSpace)
                    .padding(.top, 2)
            }
        }
        // Cards always take their natural height, so a long synopsis never squeezes the still in a row.
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Whether the text is an accessibility size, where titles and synopses get more lines rather than cutting words.
    private var isLarge: Bool {
        dynamicTypeSize.isAccessibilitySize
    }
}

/// Offers the synopsis to VoiceOver as more content, rather than reading it with the card's label every time.
private struct Synopsis: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.accessibilityCustomContent(
                Text(
                    String(
                        localized: "Synopsis", bundle: .module,
                        comment: "Name of the more-content item that holds an episode's synopsis, for VoiceOver.")
                ),
                Text(text)
            )
        } else {
            content
        }
    }
}

#if DEBUG
    private struct EpisodeCardSample: View {
        /// A watched episode with a synopsis, one part way through, one with no synopsis and a special.
        private let cards: [MediaCard] = {
            let sherlock = MockMedia.seasons(of: MockMedia.series[1])
            return [sherlock[0].episodes[0], sherlock[0].episodes[3], sherlock[1].episodes[1], sherlock[2].episodes[1]]
        }()

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    ForEach(cards) { card in
                        EpisodeCard(card: card, artwork: MockMedia.backdropImage(for: card)) {
                        } menu: {
                            PreviewMenuItems()
                        }
                        .frame(width: 300)
                    }
                }
                .padding(Spacing.medium)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        EpisodeCardSample()
    }

    #Preview("Dark") {
        EpisodeCardSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        EpisodeCardSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
