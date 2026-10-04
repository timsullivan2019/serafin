import SerafinDesign
import SwiftUI

/// A poster that opens its item, zooms into it, and offers Play in its context menu.
struct PosterLink: View {
    let card: MediaCard
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        NavigationLink(value: card.route) {
            PosterCard(card: card, artwork: Catalog.poster(for: card), zoomNamespace: zoom) {
                PlayMenuItem(card: card)
            }
        }
        .buttonStyle(.card)
    }
}

/// A landscape thumbnail that opens its item, zooms into it, and offers Play in its context menu.
struct LandscapeLink: View {
    let card: MediaCard
    @Environment(\.zoomNamespace) private var zoom

    var body: some View {
        NavigationLink(value: card.route) {
            LandscapeCard(card: card, artwork: Catalog.backdrop(for: card), zoomNamespace: zoom) {
                PlayMenuItem(card: card)
            }
        }
        .buttonStyle(.card)
    }
}

/// The Play item in a card's context menu.
struct PlayMenuItem: View {
    let card: MediaCard
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        Button {
            playback.play(Catalog.playable(for: card))
        } label: {
            Label(
                String(localized: "Play", bundle: .module, comment: "Menu item that starts playback."),
                systemImage: "play.fill")
        }
    }
}

extension MediaCard {
    /// Where tapping this card goes.
    var route: Route {
        kind == .season ? .season(id: id) : .item(id: id)
    }
}
