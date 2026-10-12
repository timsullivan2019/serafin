import SerafinCore
import SerafinDesign
import SwiftUI

/// A poster that opens its item, zooms into it, and offers Play, Go to Show, Mark as Watched and Favourite in its
/// context menu.
struct PosterLink: View {
    let item: MediaItem
    /// Sets the card apart from others showing the same item on the screen, such as the row it's in, so the item's
    /// screen zooms out of the card that was tapped. Nil keys the zoom by the item alone.
    var zoomScope: String?
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        let zoomID = zoomScope.map { "\($0)/\(item.id)" }
        NavigationLink(value: zoomID.map(item.route(zoomingFrom:)) ?? item.route) {
            ItemArtwork(item, role: .poster) { image in
                PosterCard(card: item.card, artwork: image, zoomNamespace: zoom, zoomID: zoomID) {
                    CardMenuItems(item: item)
                }
            }
        }
        .buttonStyle(.card)
    }
}

/// A landscape thumbnail that opens its item, zooms into it, and offers the same context menu as a poster.
struct LandscapeLink: View {
    let item: MediaItem
    /// Whether a played item shows its check, which Continue Watching leaves off.
    var showsPlayedBadge = true
    /// Which picture the card shows: an episode's own still in a season, or the show's art in Continue Watching and
    /// Next Up, following the artwork rules in docs/PLAN-2.md.
    var role = ImageRole.landscape
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        NavigationLink(value: item.route) {
            ItemArtwork(item, role: role) { image in
                LandscapeCard(
                    card: item.card, artwork: image, zoomNamespace: zoom, showsPlayedBadge: showsPlayedBadge
                ) {
                    CardMenuItems(item: item)
                }
            }
        }
        .buttonStyle(.card)
    }
}

/// A card in Continue Watching or Next Up. An episode plays when tapped, the player growing out of its artwork, and
/// its menu opens the episode's page or its show's. A movie opens its page, like any other card.
struct WatchingLink: View {
    let item: MediaItem
    /// Whether a played item shows its check, which Continue Watching leaves off.
    var showsPlayedBadge = true
    @State private var playCount = 0
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.zoomNamespace) private var zoom
    @Environment(\.playerZoomNamespace) private var playerZoom

    var body: some View {
        if item.card.kind == .episode {
            Button {
                playCount += 1
                playback.play(item, zoomSource: CardPlayZoom.id(for: item.id))
            } label: {
                ItemArtwork(item, role: .watching) { image in
                    LandscapeCard(
                        card: item.card, artwork: image, zoomNamespace: zoom, playZoomNamespace: playerZoom,
                        showsPlayedBadge: showsPlayedBadge
                    ) {
                        CardMenuItems(item: item, tapPlays: true)
                    }
                }
            }
            .buttonStyle(.card)
            .sensoryFeedback(.impact(weight: .medium), trigger: playCount)
            .accessibilityHint(
                String(
                    localized: "Plays the episode", bundle: .module,
                    comment: "Hint on an episode card that plays when tapped.")
            )
        } else {
            LandscapeLink(item: item, showsPlayedBadge: showsPlayedBadge, role: .watching)
        }
    }
}

/// An episode on its show's page. Tapping plays it, the player growing out of its still; its menu opens the episode's
/// own page, marks it watched or adds it to the favorites.
struct EpisodeLink: View {
    let item: MediaItem
    /// The least height for the card's words, so it's as tall as the others in a row; nil for its own height.
    var textHeight: CGFloat?
    @Environment(PlaybackCoordinator.self) private var playback
    @Environment(\.zoomNamespace) private var zoom
    @Environment(\.playerZoomNamespace) private var playerZoom

    var body: some View {
        ItemArtwork(item, role: .landscape) { image in
            EpisodeCard(
                card: item.card, artwork: image, zoomNamespace: zoom, playZoomNamespace: playerZoom,
                textHeight: textHeight
            ) {
                playback.play(item, zoomSource: CardPlayZoom.id(for: item.id))
            } menu: {
                CardMenuItems(item: item, tapPlays: true, offersShow: false)
            }
        }
    }
}

/// A cast or crew member, or a person search found, that opens their page. A person the server gave no ID for
/// can't have a page, so their card stays still.
struct PersonLink: View {
    let person: CastMember

    var body: some View {
        if person.personID != nil {
            NavigationLink(value: Route.person(person)) {
                card
            }
            .buttonStyle(.card)
        } else {
            card
        }
    }

    private var card: some View {
        PersonPhoto(person: person) { photo in
            PersonCard(name: person.name, role: person.role, photo: photo)
        }
    }
}

extension MediaItem {
    /// The page of the show an episode belongs to, for Go to Show, or nil for anything else.
    var showRoute: Route? {
        guard card.kind == .episode, let seriesID = card.episode?.seriesID, ItemID.isPlain(seriesID) else {
            return nil
        }
        return .item(id: seriesID)
    }

    /// Where tapping this item goes from a card whose zoom is keyed by `zoomID` rather than the item's ID.
    func route(zoomingFrom zoomID: String) -> Route {
        guard case .card = route else { return route }
        return .card(self, zoomID: zoomID)
    }

    /// Where tapping this item goes.
    var route: Route {
        switch card.kind {
        case .season:
            .season(id: id, seriesID: source?.seriesID ?? SampleMediaSource.seriesID(ofSeason: id) ?? "")
        case .collection:
            .collection(id: id, title: card.title)
        case .movie, .series, .episode:
            .card(self)
        }
    }
}
