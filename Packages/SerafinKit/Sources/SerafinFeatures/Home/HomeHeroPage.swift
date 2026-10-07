import JellyfinAPI
import SerafinCore
import SerafinDesign
import SwiftUI

/// One featured item's page in Home's hero: its artwork loaded from the server, Play, the detail screen and the
/// item's context menu.
struct HomeHeroPage: View {
    /// The width the logo is asked for, in points, which the next page's prefetch matches.
    static let logoWidth: CGFloat = 320

    let entry: HomeHeroModel.Entry
    @State private var tint: Color?
    /// The page's size, which decides how wide a backdrop to ask for.
    @State private var size: CGSize = .zero
    @Environment(\.artwork) private var artwork
    @Environment(\.media) private var media
    @Environment(\.navigate) private var navigate
    @Environment(\.zoomNamespace) private var zoom
    @Environment(\.playerZoomNamespace) private var playerZoom
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        let usesPoster = !hasBackdrop
        ItemArtwork(
            entry.item, role: usesPoster ? .poster : .backdrop, width: Self.backdropWidth(for: size), onLoad: setTint
        ) { backdrop in
            ItemArtwork(entry.item, role: .logo, width: Self.logoWidth) { logo in
                HeroPage(
                    item: entry.hero,
                    backdrop: backdrop,
                    backdropIsPoster: usesPoster,
                    logo: logo,
                    tint: tint ?? sampleTint,
                    zoomNamespace: zoom,
                    playZoomNamespace: playerZoom,
                    play: play,
                    showDetails: { navigate(.featured(id: entry.id)) }
                ) {
                    CardMenuItems(item: entry.item)
                }
            }
        }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
    }

    /// How wide a backdrop to ask for so that, filling a page of `size`, it isn't enlarged: a 16:9 image filling a
    /// tall page is as wide as 16:9 of the page's height. Zero until the page has a size, which asks for nothing yet.
    static func backdropWidth(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        return max(size.width, size.height * 16 / 9)
    }

    /// Whether the item or its show has a backdrop. The samples always do.
    private var hasBackdrop: Bool {
        guard let artwork, let source = entry.item.source else { return true }
        return Self.hasBackdrop(source, artwork: artwork)
    }

    /// The samples' tint, which have no artwork to measure; the accent for a server's item until its artwork loads.
    private var sampleTint: Color {
        entry.item.source == nil ? MockMedia.tint(for: entry.item.card) : .accentFallback
    }

    private func setTint(_ image: CGImage) {
        tint = ArtworkTint.color(for: image)
    }

    /// Plays the item, or for a show the episode found for it, finding it first when it isn't known yet.
    private func play() {
        let zoomSource = HomeHeroLayout.playZoomID(for: entry.id)
        guard entry.item.card.kind == .series else {
            playback.play(entry.item, zoomSource: zoomSource)
            return
        }
        if let episode = entry.playable {
            playback.play(episode, zoomSource: zoomSource)
            return
        }
        Task {
            if let episode = try? await media.playable(ofSeries: entry.id) {
                playback.play(episode, zoomSource: zoomSource)
            } else {
                // Without its episode, as when the server can't be reached, the show's own screen says why.
                navigate(.featured(id: entry.id))
            }
        }
    }

    /// Whether `source` or its show has a backdrop.
    static func hasBackdrop(_ source: BaseItemDto, artwork: Artwork) -> Bool {
        artwork.urls.url(.backdrop, of: source, maxWidth: 100) != nil
    }

    /// Whether `item` has a backdrop or a poster, which the hero needs one of. The samples always do.
    static func hasArtwork(_ item: MediaItem, artwork: Artwork?) -> Bool {
        guard let artwork, let source = item.source else { return true }
        return hasBackdrop(source, artwork: artwork) || artwork.urls.url(.poster, of: source, maxWidth: 100) != nil
    }
}
