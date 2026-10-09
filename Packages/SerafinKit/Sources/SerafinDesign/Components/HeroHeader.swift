import SwiftUI

/// The full-bleed top of a detail screen: the backdrop, the logo or title, a metadata line, the media badges and a
/// glass play pill.
///
/// The backdrop darkens toward the bottom so white text stays readable, then fades into the screen background so
/// the page continues seamlessly below. The pill reads "Play", "Play S2 E4" for an episode or a show's next one, or
/// "Resume · 32 min left" with a thin progress line when the item is in progress ("Resume S2 E2 · 23 min left" for
/// a show), and is tinted with the screen's accent, typically ``ArtworkTint`` of the backdrop. While the item is in
/// progress, touching and holding the pill offers Play from Beginning.
///
/// When the artwork changes identity, as when a show's page follows its season menu, the new artwork crossfades in
/// over the old, settling from a slight zoom, and the pill, the episode line and the badges crossfade with it, all in
/// the animation of the change. Under Reduce Motion it only crossfades.
public struct HeroHeader: View {
    private let card: MediaCard
    private let backdrop: Image?
    private let logo: Image?
    private let tint: Color
    private let playZoomNamespace: Namespace.ID?
    private let startOver: (() -> Void)?
    private let play: () -> Void
    private let arrivesFromHomeHero: Bool
    private let badges: [String]
    private let nextEpisode: MediaCard?
    private let artworkID: String?
    private let artworkAnchor: Alignment
    @State private var playCount = 0
    /// How much of Home's hero fade still shows, from 1 as the screen zooms in from the hero to 0 once it has.
    @State private var arrivalFade: Double
    @Environment(\.isPresented) private var isPresented
    @Environment(\.heroSafeAreaTop) private var safeAreaTop

    /// Creates a hero header.
    ///
    /// - Parameters:
    ///   - card: The movie, series or episode the screen shows.
    ///   - backdrop: The backdrop image, or nil while it loads.
    ///   - logo: The title logo, drawn instead of the title text when present.
    ///   - tint: The glass tint for the play pill.
    ///   - playZoomNamespace: The namespace in which the play pill is the source of a zoom transition, keyed by
    ///     ``playZoomID(for:)``, so the player can grow out of it. Pass nil for no zoom.
    ///   - startOver: Called when Play from Beginning is chosen from the pill's menu, offered while the item is in
    ///     progress.
    ///   - arrivesFromHomeHero: Whether the screen zooms in from Home's hero. The hero's fade then starts over the
    ///     backdrop and fades away as the screen opens, and returns as it closes, so the two read as one movement.
    ///   - badges: The media badges, such as 4K and Dolby Atmos, in the order ``MediaBadgeRow`` shows them.
    ///   - nextEpisode: For a show, the episode Play starts, named under the metadata line and on the pill.
    ///   - artworkID: Identifies the artwork, so that new artwork crossfades in over the old, or nil when the backdrop
    ///     stays the same picture.
    ///   - artworkAnchor: Which part of the artwork stays in view when it's cropped to fill the header: the top for a
    ///     poster, whose title and faces sit high, otherwise the centre.
    ///   - play: Called when the play pill is tapped.
    public init(
        card: MediaCard,
        backdrop: Image?,
        logo: Image? = nil,
        tint: Color = .accentFallback,
        playZoomNamespace: Namespace.ID? = nil,
        startOver: (() -> Void)? = nil,
        arrivesFromHomeHero: Bool = false,
        badges: [String] = [],
        nextEpisode: MediaCard? = nil,
        artworkID: String? = nil,
        artworkAnchor: Alignment = .center,
        play: @escaping () -> Void
    ) {
        self.card = card
        self.backdrop = backdrop
        self.logo = logo
        self.tint = tint
        self.playZoomNamespace = playZoomNamespace
        self.startOver = startOver
        self.play = play
        self.arrivesFromHomeHero = arrivesFromHomeHero
        self.badges = badges
        self.nextEpisode = nextEpisode
        self.artworkID = artworkID
        self.artworkAnchor = artworkAnchor
        _arrivalFade = State(initialValue: arrivesFromHomeHero ? 1 : 0)
    }

    public var body: some View {
        HeroBackdrop(image: backdrop, kind: card.kind, id: artworkID, anchor: artworkAnchor)
            .overlay {
                if arrivesFromHomeHero {
                    HeroFade().opacity(arrivalFade)
                }
            }
            // As tall as Home's hero, so zooming in from it keeps the artwork the same size and place.
            .heroFrame()
            .onAppear {
                guard arrivesFromHomeHero else { return }
                withAnimation(.easeOut(duration: 0.45)) { arrivalFade = 0 }
            }
            .onChange(of: isPresented) { _, presented in
                // Closing, the fade returns as the screen shrinks back into the hero.
                guard arrivesFromHomeHero, !presented else { return }
                withAnimation(.easeIn(duration: 0.3)) { arrivalFade = 1 }
            }
            .overlay(alignment: .bottom) {
                // Each piece fades out on its own as it nears the navigation bar, so none of it sits under the clock.
                VStack(spacing: Spacing.medium) {
                    titleOrLogo
                        .fadesBeforeTopSafeArea(safeAreaTop)
                    // Keyed by the episode it describes, so a show's details crossfade, in place, to another episode's.
                    ZStack {
                        details
                            .id(nextEpisode?.id)
                            .transition(.opacity)
                    }
                    .fadesBeforeTopSafeArea(safeAreaTop)
                    pill
                        .fadesBeforeTopSafeArea(safeAreaTop)
                }
                .padding(.horizontal, Spacing.large)
                .padding(.bottom, Spacing.xLarge + Spacing.large)
                .environment(\.colorScheme, .dark)
            }
    }

    /// The metadata line, a show's next episode and the media badges.
    private var details: some View {
        VStack(spacing: Spacing.xSmall) {
            HeroMetadata(card: card)
            if let nextEpisode, let code = nextEpisode.episodeCode {
                Text(
                    String(
                        localized: "\(code) · \(nextEpisode.title)", bundle: .module,
                        comment:
                            "Two parts of a line joined by a dot: a series title and episode code above an episode title (Caminandes · S1 E2), or a show's next episode under its details (S2 E4 · The Final Problem)."
                    )
                )
                .typography(.cardTitle)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
            }
            if !badges.isEmpty {
                MediaBadgeRow(badges: badges)
            }
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

    /// The play pill, with Play from Beginning in its menu while the item is in progress.
    ///
    /// One pill either way, with the menu's item coming and going inside it, so a change between Resume and Play, as
    /// when a show's page follows another season, morphs the glass and crossfades the words rather than fading one
    /// pill out and another in.
    private var pill: some View {
        playPill
            .contextMenu {
                if offersStartOver {
                    Button(action: playFromStart) {
                        Label(Self.playFromBeginning, systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .accessibilityActions {
                if offersStartOver {
                    Button(Self.playFromBeginning, action: playFromStart)
                }
            }
    }

    /// Whether the pill offers Play from Beginning: while the item is in progress.
    private var offersStartOver: Bool {
        card.isInProgress && startOver != nil
    }

    private static var playFromBeginning: String {
        String(
            localized: "Play from Beginning",
            bundle: .module,
            comment: "Menu item and action that plays an item from the beginning."
        )
    }

    private func playFromStart() {
        playCount += 1
        startOver?()
    }

    private var playPill: some View {
        Button {
            playCount += 1
            play()
        } label: {
            PlayPill(
                title: Self.playTitle(for: card, nextEpisode: nextEpisode),
                progress: card.isInProgress ? card.progress : nil,
                tint: tint
            )
            // The glass stays put while its words crossfade, since glass itself never fades.
            .contentTransition(.opacity)
        }
        .buttonStyle(.plain)
        .modifier(PlayZoomSource(id: Self.playZoomID(for: card.id), namespace: playZoomNamespace))
        .accessibilityLabel(playAccessibilityLabel)
        .sensoryFeedback(.impact(weight: .medium), trigger: playCount)
    }

    /// What the play pill says for `card`: "Resume · 32 min left" while it's in progress, "Play S2 E4" for an episode
    /// or, given `nextEpisode`, a show's next one, and otherwise "Play". A show resuming its episode names it:
    /// "Resume S2 E2 · 23 min left".
    public static func playTitle(for card: MediaCard, nextEpisode: MediaCard? = nil) -> String {
        guard let remaining = card.remainingText else {
            if let code = (nextEpisode ?? card).episodeCode {
                return String(
                    localized: "Play \(code)", bundle: .module,
                    comment:
                        "Button that plays an episode, such as Play S1 E1: on Home's featured item and on a detail screen."
                )
            }
            return String(localized: "Play", bundle: .module, comment: "Button that starts playback.")
        }
        if let code = nextEpisode?.episodeCode {
            return String(
                localized: "Resume \(code) · \(remaining)",
                bundle: .module,
                comment: "Button on a show's page that resumes its episode, such as Resume S2 E2 · 23 min left."
            )
        }
        return String(
            localized: "Resume · \(remaining)",
            bundle: .module,
            comment: "Button that resumes playback, such as Resume · 32 min left."
        )
    }

    private var playAccessibilityLabel: String {
        guard let remaining = card.remainingText else { return Self.playTitle(for: card, nextEpisode: nextEpisode) }
        if let code = nextEpisode?.episodeCode {
            return String(
                localized: "Resume \(code), \(remaining)",
                bundle: .module,
                comment: "Spoken label of a show's resume button, such as Resume S2 E2, 23 min left."
            )
        }
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

/// The backdrop, darkened toward the bottom for legible text, then faded into the screen background. New artwork
/// crossfades in over the old, settling from a slight zoom.
private struct HeroBackdrop: View {
    let image: Image?
    let kind: MediaCard.Kind
    let id: String?
    let anchor: Alignment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let image {
                // Each picture fills the header on its own, so two can overlap while they crossfade.
                Color.clear
                    .overlay(alignment: anchor) {
                        image
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .id(id)
                    .transition(arrival)
            } else {
                ArtworkPlaceholder(kind: kind)
            }
        }
        // Arriving artwork starts 2% larger; it never spills past the header while it settles.
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

    /// How new artwork arrives: fading in from 2% larger, or only fading under Reduce Motion. The old picture fades
    /// out where it is.
    private var arrival: AnyTransition {
        let fadeIn: AnyTransition = reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.02))
        return .asymmetric(insertion: fadeIn, removal: .opacity)
    }
}

/// Year or episode code, running time and rating, separated by dots.
private struct HeroMetadata: View {
    let card: MediaCard
    @Environment(\.colorSchemeContrast) private var contrast

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
        .foregroundStyle(.white.opacity(contrast == .increased ? 1 : 0.85))
        // The same lift as the title, for artwork that's bright where the line sits.
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
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
