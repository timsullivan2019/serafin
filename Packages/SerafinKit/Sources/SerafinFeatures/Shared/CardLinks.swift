import SerafinCore
import SerafinDesign
import SwiftUI

/// A poster that opens its item, zooms into it, and offers Play, Mark as Played and Favourite in its context menu.
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
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        NavigationLink(value: item.route) {
            ItemArtwork(item, role: .landscape) { image in
                LandscapeCard(card: item.card, artwork: image, zoomNamespace: zoom) {
                    CardMenuItems(item: item)
                }
            }
        }
        .buttonStyle(.card)
    }
}

extension MediaItem {
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
