import SwiftUI

/// The compact now-playing bar for the tab bar's bottom accessory: thumbnail, title, play or pause, and close.
///
/// Place it in `tabViewBottomAccessory`, which supplies the glass around it. Tapping the thumbnail or title opens
/// the full player. When the tab bar minimizes and the accessory moves inline, the bar drops its subtitle and
/// close button to fit.
public struct MiniPlayer: View {
    private let title: String
    private let subtitle: String?
    private let artwork: Image?
    private let isPlaying: Bool
    private let playPause: () -> Void
    private let close: () -> Void
    private let open: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    /// Creates the mini player.
    ///
    /// - Parameters:
    ///   - title: The title of what is playing.
    ///   - subtitle: A second line, such as the series and episode code.
    ///   - artwork: A 16:9 thumbnail, or nil while it loads.
    ///   - isPlaying: Whether playback is running.
    ///   - playPause: Called when the play or pause button is tapped.
    ///   - close: Called when the close button is tapped.
    ///   - open: Called when the thumbnail or title is tapped, to bring back the full player.
    public init(
        title: String,
        subtitle: String? = nil,
        artwork: Image?,
        isPlaying: Bool,
        playPause: @escaping () -> Void,
        close: @escaping () -> Void,
        open: @escaping () -> Void = {}
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.isPlaying = isPlaying
        self.playPause = playPause
        self.close = close
        self.open = open
    }

    private var isInline: Bool { placement == .inline }

    public var body: some View {
        HStack(spacing: Spacing.small) {
            Button(action: open) {
                HStack(spacing: Spacing.small) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if let subtitle, !isInline {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .modifier(PointerHighlight())
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                String(localized: "Opens the player", bundle: .module, comment: "Hint on the mini player's title.")
            )
            Button(action: playPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .modifier(PointerHighlight())
            .accessibilityLabel(
                isPlaying
                    ? String(localized: "Pause", bundle: .module, comment: "Button that pauses playback.")
                    : String(localized: "Play", bundle: .module, comment: "Button that starts playback.")
            )
            if !isInline {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .modifier(PointerHighlight())
                .accessibilityLabel(
                    String(
                        localized: "Close Player", bundle: .module,
                        comment: "Button that stops and hides the mini player.")
                )
            }
        }
        .buttonStyle(.plain)
        .padding(.leading, Spacing.xSmall)
        .padding(.trailing, Spacing.xxSmall)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityShowsLargeContentViewer()
    }

    private var thumbnail: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .frame(height: 32)
            .overlay {
                if let artwork {
                    artwork
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(.surface)
                }
            }
            .clipShape(ConcentricRectangle(corners: .concentric(minimum: .fixed(6)), isUniform: true))
            .accessibilityHidden(true)
    }
}

#if DEBUG && os(iOS)
    // The tab bar accessory exists on iOS only.
    private struct MiniPlayerSample: View {
        @State private var isPlaying = true
        private let episode = MockLibrary.continueWatching.first { $0.kind == .episode } ?? MockMedia.episodes[0]

        var body: some View {
            TabView {
                Tab {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))]) {
                            ForEach(MockMedia.movies) { card in
                                PosterCard(card: card, artwork: MockMedia.posterImage(for: card))
                            }
                        }
                        .padding(Spacing.medium)
                    }
                } label: {
                    Label {
                        Text(verbatim: "Home")
                    } icon: {
                        Image(systemName: "house")
                    }
                }
                Tab {
                    Color.background
                } label: {
                    Label {
                        Text(verbatim: "Library")
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
                }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            .tabViewBottomAccessory {
                MiniPlayer(
                    title: episode.title,
                    subtitle: episode.eyebrowText,
                    artwork: MockMedia.backdropImage(for: episode),
                    isPlaying: isPlaying,
                    playPause: { isPlaying.toggle() },
                    close: {}
                )
            }
        }
    }

    #Preview("Light") {
        MiniPlayerSample()
    }

    #Preview("Dark") {
        MiniPlayerSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        MiniPlayerSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
