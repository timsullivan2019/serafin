import SwiftUI

/// The full-bleed top of a detail screen: the backdrop, the logo or title, a metadata line and a glass play pill.
///
/// The backdrop darkens toward the bottom so white text stays readable, then fades into the screen background so
/// the page continues seamlessly below. The pill reads "Play", or "Resume · 32 min left" when the item is in
/// progress, and is tinted with the screen's accent, typically ``ArtworkTint`` of the backdrop. While the item is in
/// progress, touching and holding the pill offers Start Over.
public struct HeroHeader: View {
    private let card: MediaCard
    private let backdrop: Image?
    private let logo: Image?
    private let tint: Color
    private let playZoomNamespace: Namespace.ID?
    private let startOver: (() -> Void)?
    private let play: () -> Void
    @State private var playCount = 0

    /// Creates a hero header.
    ///
    /// - Parameters:
    ///   - card: The movie, series or episode the screen shows.
    ///   - backdrop: The backdrop image, or nil while it loads.
    ///   - logo: The title logo, drawn instead of the title text when present.
    ///   - tint: The glass tint for the play pill.
    ///   - playZoomNamespace: The namespace in which the play pill is the source of a zoom transition, keyed by
    ///     ``playZoomID(for:)``, so the player can grow out of it. Pass nil for no zoom.
    ///   - startOver: Called when Start Over is chosen from the pill's menu, offered while the item is in progress.
    ///   - play: Called when the play pill is tapped.
    public init(
        card: MediaCard,
        backdrop: Image?,
        logo: Image? = nil,
        tint: Color = .accentFallback,
        playZoomNamespace: Namespace.ID? = nil,
        startOver: (() -> Void)? = nil,
        play: @escaping () -> Void
    ) {
        self.card = card
        self.backdrop = backdrop
        self.logo = logo
        self.tint = tint
        self.playZoomNamespace = playZoomNamespace
        self.startOver = startOver
        self.play = play
    }

    public var body: some View {
        HeroBackdrop(image: backdrop, kind: card.kind)
            .containerRelativeFrame(.vertical) { height, _ in height * 0.68 }
            .overlay(alignment: .bottom) {
                VStack(spacing: Spacing.medium) {
                    titleOrLogo
                    HeroMetadata(card: card)
                    pill
                }
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.xLarge + Spacing.large)
                .environment(\.colorScheme, .dark)
            }
    }

    @ViewBuilder private var titleOrLogo: some View {
        if let logo {
            logo
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280, maxHeight: 100)
                .accessibilityLabel(card.title)
                .accessibilityAddTraits(.isHeader)
        } else {
            Text(card.title)
                .typography(.largeTitle)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// The ID under which the play pill of the hero for `cardID` is a zoom source.
    public static func playZoomID(for cardID: String) -> String {
        "hero-play-\(cardID)"
    }

    /// The play pill, with Start Over in its menu while the item is in progress.
    @ViewBuilder private var pill: some View {
        if card.isInProgress, let startOver {
            let title = String(
                localized: "Start Over",
                bundle: .module,
                comment: "Menu item and action that plays an item from the beginning."
            )
            let playFromStart = {
                playCount += 1
                startOver()
            }
            playPill
                .contextMenu {
                    Button(action: playFromStart) {
                        Label(title, systemImage: "arrow.counterclockwise")
                    }
                }
                .accessibilityAction(named: title, playFromStart)
        } else {
            playPill
        }
    }

    private var playPill: some View {
        Button {
            playCount += 1
            play()
        } label: {
            Label {
                Text(playTitle)
            } icon: {
                Image(systemName: "play.fill")
            }
            .typography(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, Spacing.large)
            .padding(.vertical, Spacing.small)
            .frame(minHeight: 50)
            .glassEffect(.regular.tint(tint).interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .modifier(PlayZoomSource(id: Self.playZoomID(for: card.id), namespace: playZoomNamespace))
        .accessibilityLabel(playAccessibilityLabel)
        .sensoryFeedback(.impact(weight: .medium), trigger: playCount)
    }

    private var playTitle: String {
        guard let remaining = card.remainingText else {
            return String(localized: "Play", bundle: .module, comment: "Button that starts playback.")
        }
        return String(
            localized: "Resume · \(remaining)",
            bundle: .module,
            comment: "Button that resumes playback, such as Resume · 32 min left."
        )
    }

    private var playAccessibilityLabel: String {
        guard let remaining = card.remainingText else { return playTitle }
        return String(
            localized: "Resume, \(remaining)",
            bundle: .module,
            comment: "Spoken label of the resume button, such as Resume, 32 min left."
        )
    }
}

/// Makes the play pill the source of the player's zoom transition, when there is a namespace for it.
private struct PlayZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            // A rounded rectangle as round as the pill is tall: the only shape transition sources accept.
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(.rect(cornerRadius: 25, style: .continuous))
            }
        } else {
            content
        }
    }
}

/// The backdrop, darkened toward the bottom for legible text, then faded into the screen background.
private struct HeroBackdrop: View {
    let image: Image?
    let kind: MediaCard.Kind

    var body: some View {
        Color.clear
            .overlay {
                if let image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    ArtworkPlaceholder(kind: kind)
                }
            }
            .clipped()
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0), location: 0.35),
                        .init(color: .black.opacity(0.55), location: 0.8),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: Color.background.opacity(0), location: 0.88),
                        .init(color: Color.background, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .accessibilityHidden(true)
    }
}

/// Year or episode code, running time and rating, separated by dots.
private struct HeroMetadata: View {
    let card: MediaCard

    var body: some View {
        HStack(spacing: Spacing.xSmall) {
            if let lead = card.episodeCode ?? card.year.map(String.init) {
                Text(lead)
            }
            if let runtime = card.runtimeText {
                Text(verbatim: "·")
                    .accessibilityHidden(true)
                Text(runtime)
            }
            if let rating = card.rating {
                Text(rating)
                    .typography(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, Spacing.xxSmall + 2)
                    .padding(.vertical, 1)
                    .overlay {
                        Capsule()
                            .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                    }
                    .accessibilityLabel(
                        String(
                            localized: "Rated \(rating)", bundle: .module,
                            comment: "Spoken age rating, such as Rated PG.")
                    )
            }
        }
        .typography(.cardTitle)
        .foregroundStyle(.white.opacity(0.85))
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
    private struct HeroHeaderSample: View {
        let card: MediaCard

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    HeroHeader(
                        card: card,
                        backdrop: MockMedia.backdropImage(for: card),
                        tint: MockMedia.tint(for: card)
                    ) {}
                    Text(card.overview ?? "")
                        .typography(.body)
                        .foregroundStyle(.textPrimary)
                        .padding(Spacing.medium)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Color.background)
        }
    }

    #Preview("Light") {
        HeroHeaderSample(card: MockMedia.movies[1])
    }

    #Preview("Dark") {
        HeroHeaderSample(card: MockMedia.movies[7])
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        HeroHeaderSample(card: MockMedia.movies[1])
            .dynamicTypeSize(.accessibility5)
    }
#endif
