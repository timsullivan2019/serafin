import NukeUI
import SerafinCore
import SerafinDesign
import SwiftUI

/// A movie, show or episode: the hero header, the overview and cast, then seasons, episodes or similar titles.
struct ItemDetailView: View {
    @State private var model: ItemDetailModel
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions
    @Environment(\.zoomNamespace) private var zoom
    @Environment(AppSession.self) private var session: AppSession?
    private let zoomSource: String
    private let arrivesFromHomeHero: Bool

    /// Creates the screen.
    ///
    /// - Parameter id: The movie, series or episode.
    init(id: String) {
        _model = State(initialValue: ItemDetailModel(id: id))
        zoomSource = id
        arrivesFromHomeHero = false
    }

    /// Creates the screen for an item featured in Home's hero, which it zooms in from, showing the item at once.
    ///
    /// - Parameters:
    ///   - item: The featured movie, show or episode.
    ///   - playable: For a show, the episode its Play button starts, when the hero knows it.
    init(featured item: MediaItem, playable: MediaItem?) {
        _model = State(initialValue: ItemDetailModel(showing: item, playable: playable))
        zoomSource = HomeHeroLayout.zoomID(for: item.id)
        arrivesFromHomeHero = true
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                Skeleton(.detail)
            case .failed(let message):
                FailureState(message: message) { Task { await model.load(from: media) } }
            case .loaded(let details):
                DetailContent(details: details, model: model, arrivesFromHomeHero: arrivesFromHomeHero)
            }
        }
        .background(Color.background)
        .zoomTransition(from: zoomSource, in: zoom)
        .task(id: actions.revision) { await model.load(from: media) }
        .toolbar {
            if let item = model.details?.item {
                DetailToolbar(
                    item: item,
                    canRefreshMetadata: model.canRefreshMetadata,
                    shareURL: session?.account.flatMap { item.webLink(on: $0.server.url) }
                )
            }
        }
        // The artwork's colour once it's known, neutral until then: never the chosen accent, which would show for a
        // moment and then change.
        .tint(model.tint ?? ArtworkTint.neutral)
    }
}

/// The scrolling page under the hero.
private struct DetailContent: View {
    let details: ItemDetails
    let model: ItemDetailModel
    let arrivesFromHomeHero: Bool
    /// The hero's size, which decides how wide a backdrop to ask for.
    @State private var heroSize: CGSize = .zero
    /// Whether the page has been scrolled at all, which brings the top edge's blur over what passes under the
    /// navigation bar.
    @State private var isScrolled = false
    /// Where the top safe area ends, below the navigation bar, which the hero's text and pill fade out before
    /// reaching.
    @State private var safeAreaTop: CGFloat = 0
    /// A trailer's web page, showing in Safari inside the app.
    @State private var webTrailer: WebPage?
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.playerZoomNamespace) private var playerZoom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                hero
                about
                if !details.trailers.isEmpty {
                    MediaRow(
                        String(localized: "Trailers", bundle: .module, comment: "Row of an item's trailers."),
                        style: .landscape,
                        items: details.trailers
                    ) { trailer in
                        TrailerLink(trailer: trailer, item: details.item) { webTrailer = WebPage(url: $0) }
                    }
                }
                if !details.chapters.isEmpty {
                    MediaRow(
                        String(
                            localized: "Chapters", bundle: .module, comment: "Row of a movie's or episode's chapters."),
                        style: .landscape,
                        items: details.chapters
                    ) { chapter in
                        ChapterLink(chapter: chapter, item: details.item)
                    }
                }
                if !details.cast.isEmpty {
                    MediaRow(
                        String(localized: "Cast & Crew", bundle: .module, comment: "Row of an item's cast and crew."),
                        style: .people,
                        items: details.cast
                    ) { person in
                        PersonLink(person: person)
                    }
                }
                if !details.seasons.isEmpty {
                    MediaRow(
                        String(localized: "Seasons", bundle: .module, comment: "Row of a show's seasons."),
                        style: .posters,
                        items: details.seasons
                    ) { PosterLink(item: $0) }
                }
                if !details.seasonEpisodes.isEmpty {
                    MediaRow(
                        String(localized: "More Episodes", bundle: .module, comment: "Row of other episodes."),
                        style: .landscape,
                        items: details.seasonEpisodes
                    ) { LandscapeLink(item: $0) }
                }
                if !details.similar.isEmpty {
                    MediaRow(
                        String(localized: "More Like This", bundle: .module, comment: "Row of similar titles."),
                        style: .posters,
                        items: details.similar
                    ) { PosterLink(item: $0) }
                }
                InformationColumns(columns: details.information)
                    .padding(.horizontal, Spacing.medium)
            }
            .padding(.bottom, Spacing.xLarge)
        }
        // The hero runs under the navigation bar, whose glass back button floats over the artwork.
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            let scrolled = HomeHeroLayout.isScrolled(offset: offset, wasScrolled: isScrolled)
            if scrolled != isScrolled {
                isScrolled = scrolled
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.top
        } action: {
            safeAreaTop = $0
        }
        .environment(\.heroSafeAreaTop, safeAreaTop)
        // Anything scrolling up under the navigation bar softens into it, as on Home. At rest the artwork runs clear to
        // the top, and while the screen zooms in the effect would show as a band across the top, so it stays hidden.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(!isScrolled, for: .top)
        .sheet(item: $webTrailer) { page in
            WebPageView(url: page.url)
                .ignoresSafeArea()
        }
    }

    private var hero: some View {
        ItemArtwork(
            details.item, role: .backdrop, width: ArtworkMemory.backdropWidth(for: details.item.id, filling: heroSize),
            onLoad: { [model] in model.backdropLoaded($0) }
        ) { backdrop in
            ItemArtwork(details.item, role: .logo, width: HomeHeroPage.logoWidth) { logo in
                HeroHeader(
                    card: playCard,
                    backdrop: backdrop,
                    logo: logo,
                    tint: model.tint ?? ArtworkTint.neutral,
                    playZoomNamespace: playerZoom,
                    startOver: {
                        playback.play(details.playable ?? details.item, from: .beginning, zoomSource: pillZoom)
                    },
                    arrivesFromHomeHero: arrivesFromHomeHero,
                    badges: details.badges,
                    nextEpisode: details.item.card.kind == .series ? details.playable?.card : nil
                ) {
                    playback.play(details.playable ?? details.item, zoomSource: pillZoom)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            heroSize = $0
        }
    }

    /// The play pill's zoom source, so the player grows out of it.
    private var pillZoom: String {
        HeroHeader.playZoomID(for: playCard.id)
    }

    /// The card the hero describes. A show's pill resumes or starts the episode Play opens, so it shows that
    /// episode's progress.
    private var playCard: MediaCard {
        var card = details.item.card
        if card.kind == .series, let next = details.playable?.card {
            card.progress = next.progress
            card.runtime = next.runtime
        }
        return card
    }

    /// The overview, kept to a readable line length on wide screens. Genres are listed under Information.
    @ViewBuilder private var about: some View {
        if let overview = details.item.card.overview {
            Text(overview)
                .typography(.body)
                .foregroundStyle(.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, Spacing.medium)
        }
    }
}

/// A trailer's card: the item's art with the trailer's name. A web trailer opens in Safari inside the app; one stored
/// with the item plays in the normal player.
private struct TrailerLink: View {
    let trailer: Trailer
    let item: MediaItem
    let openWeb: (URL) -> Void
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        Button {
            switch trailer.source {
            case .web(let url): openWeb(url)
            case .local(let file): playback.play(file)
            }
        } label: {
            ItemArtwork(item, role: .watching) { image in
                ThumbnailCard(title: trailer.name, caption: caption, image: image)
            }
        }
        .buttonStyle(.card)
    }

    private var caption: String? {
        guard case .web(let url) = trailer.source else { return nil }
        // Where it opens, such as youtube.com.
        return url.host()?.replacing(/^www\./, with: "")
    }
}

/// A chapter's card, which plays the item from the chapter's start.
private struct ChapterLink: View {
    let chapter: Chapter
    let item: MediaItem
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.artwork) private var artwork
    @Environment(\.displayScale) private var scale
    @State private var width: CGFloat = 0

    var body: some View {
        Button {
            playback.play(item, from: .position(chapter.start))
        } label: {
            picture { image in
                ThumbnailCard(
                    title: chapter.name, caption: chapter.startText, image: image,
                    // A chapter the file has no picture for shows its number instead.
                    number: chapter.imageTag == nil ? chapter.index + 1 : nil)
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
        }
        .buttonStyle(.card)
        .accessibilityHint(
            String(
                localized: "Plays from this chapter", bundle: .module,
                comment: "Hint on a chapter card, which plays the movie or episode from the chapter's start."))
    }

    @ViewBuilder private func picture(@ViewBuilder content: @escaping (Image?) -> some View) -> some View {
        if let artwork, width > 0,
            let request = artwork.request(
                chapter: chapter.index, of: item.id, tag: chapter.imageTag, width: width, scale: scale)
        {
            LazyImage(request: request) { state in content(state.image) }
                .pipeline(artwork.pipeline)
        } else {
            content(nil)
        }
    }
}

/// A web address shown in a sheet, for a trailer.
private struct WebPage: Identifiable {
    let url: URL
    var id: URL { url }
}

/// Mark as Watched and Favourite as glass buttons in the navigation bar, then a More menu with Mark as Unwatched,
/// Refresh Metadata for administrators, and Share.
private struct DetailToolbar: ToolbarContent {
    let item: MediaItem
    let canRefreshMetadata: Bool
    let shareURL: URL?
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await actions.setPlayed(!item.card.isWatched, for: item, in: media) }
            } label: {
                Label(
                    item.card.isWatched ? Self.markUnwatched : Self.markWatched,
                    // Filled only once it's watched: a film started again shows as in progress.
                    systemImage: item.card.isWatched ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
            Button {
                Task { await actions.setFavourite(!item.card.isFavourite, for: item, in: media) }
            } label: {
                Label(
                    item.card.isFavourite
                        ? String(
                            localized: "Remove from Favourites", bundle: .module,
                            comment: "Button and menu item that takes an item out of the favourites.")
                        : String(
                            localized: "Add to Favourites", bundle: .module,
                            comment: "Button and menu item that adds an item to the favourites."),
                    systemImage: item.card.isFavourite ? "heart.fill" : "heart"
                )
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                // Played, or part watched: either way, back to unwatched.
                if item.card.isPlayed || item.card.isInProgress {
                    Button {
                        Task { await actions.setPlayed(false, for: item, in: media) }
                    } label: {
                        Label(Self.markUnwatched, systemImage: "circle")
                    }
                }
                if canRefreshMetadata {
                    Button {
                        Task { await actions.refreshMetadata(of: item, in: media) }
                    } label: {
                        Label(
                            String(
                                localized: "Refresh Metadata", bundle: .module,
                                comment: "Menu item that asks the server to look up an item's details again."),
                            systemImage: "arrow.clockwise"
                        )
                    }
                }
                if let shareURL {
                    ShareLink(item: shareURL, subject: Text(item.card.title)) {
                        Label(
                            String(localized: "Share", bundle: .module, comment: "Menu item that shares a link."),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                }
            } label: {
                Label(
                    String(localized: "More", bundle: .module, comment: "Menu of more things to do with an item."),
                    systemImage: "ellipsis")
            }
        }
    }

    static var markWatched: String {
        String(
            localized: "Mark as Watched", bundle: .module, comment: "Button and menu item that marks an item watched.")
    }

    static var markUnwatched: String {
        String(
            localized: "Mark as Unwatched", bundle: .module,
            comment: "Button and menu item that marks an item not watched.")
    }
}

extension MediaItem {
    /// The item's page in the Jellyfin web app on `server`, for sharing, or nil when the item isn't from a server.
    func webLink(on serverURL: URL) -> URL? {
        guard let source, let id = source.id, ItemID.isPlain(id), let serverID = source.serverID,
            ItemID.isPlain(serverID)
        else { return nil }
        // The web app routes after the fragment, which a URL's own path and query can't carry.
        return URL(string: serverURL.appending(path: "web/").absoluteString + "#/details?id=\(id)&serverId=\(serverID)")
    }
}

#if DEBUG
    #Preview("Movie") {
        TabStack { ItemDetailView(id: "movie-the-general") }
            .previewEnvironment()
    }

    #Preview("Series, dark") {
        TabStack { ItemDetailView(id: "series-sherlock-holmes") }
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }

    #Preview("Episode, largest text") {
        TabStack { ItemDetailView(id: "series-caminandes-s1e2") }
            .previewEnvironment()
            .dynamicTypeSize(.accessibility5)
    }
#endif
