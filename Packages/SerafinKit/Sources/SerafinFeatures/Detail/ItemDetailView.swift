import SerafinDesign
import SwiftUI

/// A movie, show or episode: the hero header, the overview and cast, then seasons, episodes or similar titles.
struct ItemDetailView: View {
    @State private var model: ItemDetailModel
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions
    @Environment(\.zoomNamespace) private var zoom
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
                DetailToolbar(item: item)
            }
        }
        .tint(model.tint)
    }
}

/// The scrolling page under the hero.
private struct DetailContent: View {
    let details: ItemDetails
    let model: ItemDetailModel
    let arrivesFromHomeHero: Bool
    /// The hero's size, which decides how wide a backdrop to ask for.
    @State private var heroSize: CGSize = .zero
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.playerZoomNamespace) private var playerZoom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                hero
                about
                if !details.cast.isEmpty {
                    MediaRow(
                        String(localized: "Cast & Crew", bundle: .module, comment: "Row of an item's cast and crew."),
                        style: .people,
                        items: details.cast
                    ) { person in
                        PersonPhoto(person: person) { photo in
                            PersonCard(name: person.name, role: person.role, photo: photo)
                        }
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
    }

    private var hero: some View {
        ItemArtwork(
            details.item, role: .backdrop, width: HomeHeroPage.backdropWidth(for: heroSize),
            onLoad: { [model] in model.backdropLoaded($0) }
        ) { backdrop in
            ItemArtwork(details.item, role: .logo, width: 280) { logo in
                HeroHeader(
                    card: playCard,
                    backdrop: backdrop,
                    logo: logo,
                    tint: model.tint,
                    playZoomNamespace: playerZoom,
                    startOver: {
                        playback.play(details.playable ?? details.item, from: .beginning, zoomSource: pillZoom)
                    },
                    arrivesFromHomeHero: arrivesFromHomeHero
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

/// Mark as Played and Favourite, as glass buttons in the navigation bar.
private struct DetailToolbar: ToolbarContent {
    let item: MediaItem
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await actions.setPlayed(!item.card.isPlayed, for: item, in: media) }
            } label: {
                Label(
                    item.card.isPlayed
                        ? String(
                            localized: "Mark as Unplayed", bundle: .module,
                            comment: "Button and menu item that marks an item not played.")
                        : String(
                            localized: "Mark as Played", bundle: .module,
                            comment: "Button and menu item that marks an item played."),
                    systemImage: item.card.isPlayed ? "checkmark.circle.fill" : "checkmark.circle"
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
