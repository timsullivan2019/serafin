import SerafinCore
import SerafinDesign
import SwiftUI

/// A poster that opens its item, zooms into it, and offers Play, Go to Show, Mark as Played and Favourite in its
/// context menu.
struct PosterLink: View {
    let item: MediaItem
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        NavigationLink(value: item.route) {
            ItemArtwork(item, role: .poster) { image in
                PosterCard(card: item.card, artwork: image, zoomNamespace: zoom) {
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

extension MediaItem {
    /// The page of the show an episode belongs to, for Go to Show, or nil for anything else.
    var showRoute: Route? {
        guard card.kind == .episode, let seriesID = card.episode?.seriesID, ItemID.isPlain(seriesID) else {
            return nil
        }
        return .item(id: seriesID)
    }

    /// Where tapping this item goes.
    var route: Route {
        switch card.kind {
        case .season:
            .season(id: id, seriesID: source?.seriesID ?? SampleMediaSource.seriesID(ofSeason: id) ?? "")
        case .collection:
            .collection(id: id, title: card.title)
        case .movie, .series, .episode:
            .item(id: id)
        }
    }
}
