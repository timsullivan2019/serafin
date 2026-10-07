import JellyfinAPI
import SerafinCore
import SerafinDesign
import SwiftUI

/// One featured item's page in Home's hero: its artwork loaded from the server, Play, the detail screen and the
/// item's context menu.
struct HomeHeroPage: View {
    /// The width the logo is asked for, in points, which the next page's prefetch and the detail screen match, so
    /// both find it already loaded.
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
            entry.item, role: usesPoster ? .poster : .backdrop,
            width: ArtworkMemory.backdropWidth(for: entry.item.id, filling: size), onLoad: setTint
        ) { backdrop in
            ItemArtwork(entry.item, role: .logo, width: Self.logoWidth) { logo in
                HeroPage(
                    item: entry.hero,
                    backdrop: backdrop,
                    backdropIsPoster: usesPoster,
                    logo: logo,
                    tint: tint ?? startingTint,
                    zoomNamespace: zoom,
                    playZoomNamespace: playerZoom,
                    play: play,
                    showDetails: { navigate(.featured(entry.item, playable: entry.playable)) }
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

    /// How wide a backdrop to ask for so that, filling a frame of `size`, it isn't enlarged: a 16:9 image filling a
    /// tall frame is as wide as 16:9 of the frame's height. Zero until the frame has a size, which asks for nothing
    /// yet. The detail screen's hero asks the same way, so zooming in from Home finds the same image already loaded.
    static func backdropWidth(for size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return 0 }
        return max(size.width, size.height * 16 / 9)
    }

    /// Whether the item or its show has a backdrop. The samples always do.
    private var hasBackdrop: Bool {
        guard let artwork, let source = entry.item.source else { return true }
        return Self.hasBackdrop(source, artwork: artwork)
    }

    /// The tint before this page has measured its artwork: the samples' own, which have no artwork to measure, or
    /// for a server's item the tint last measured for it, otherwise neutral.
    private var startingTint: Color {
        guard entry.item.source != nil else { return MockMedia.tint(for: entry.item.card) }
        return ArtworkMemory.tint(for: entry.item.id) ?? ArtworkTint.neutral
    }

    /// Takes the tint from the loaded artwork, and remembers it for the item's detail screen.
    private func setTint(_ image: CGImage) {
        let measured = ArtworkTint.color(for: image)
        ArtworkMemory.remember(measured, for: entry.item.id)
        // Fading from neutral, or from an older measurement; nothing to fade when the colour was already right.
        let animation: Animation? = measured == (tint ?? startingTint) ? nil : .easeInOut(duration: 0.3)
        withAnimation(animation) {
            tint = measured
        }
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
                navigate(.featured(entry.item, playable: entry.playable))
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
