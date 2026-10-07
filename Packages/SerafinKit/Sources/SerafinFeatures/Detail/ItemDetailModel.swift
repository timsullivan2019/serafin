import Observation
import SerafinDesign
import SwiftUI

/// What a movie, show or episode detail screen shows.
@Observable @MainActor final class ItemDetailModel {
    enum Phase {
        case loading
        case loaded(ItemDetails)
        case failed(UserMessage)
    }

    let id: String
    private(set) var phase = Phase.loading
    /// The screen's accent, taken from its backdrop, or nil until that loads. An item whose backdrop was measured
    /// moments ago, as in Home's hero, starts with its tint.
    var tint: Color?
    /// Whether the user can ask the server to refresh the item's metadata, which administrators can.
    private(set) var canRefreshMetadata = false

    init(id: String) {
        self.id = id
        tint = ArtworkMemory.tint(for: id)
    }

    /// Starts with `item` showing, and for a show the episode its Play button starts, while the full details load.
    init(showing item: MediaItem, playable: MediaItem?) {
        id = item.id
        phase = .loaded(ItemDetails(item: item, playable: playable ?? item))
        tint = item.source == nil ? MockMedia.tint(for: item.card) : ArtworkMemory.tint(for: item.id)
    }

    /// The details once they have loaded.
    var details: ItemDetails? {
        if case .loaded(let details) = phase { details } else { nil }
    }

    /// Loads the details, and whether the user may refresh their metadata. A failed reload keeps the details
    /// already showing.
    func load(from media: any MediaSource) async {
        async let canRefresh = media.canRefreshMetadata()
        do {
            let details = try await media.details(of: id)
            if details.item.source == nil {
                tint = MockMedia.tint(for: details.item.card)
            }
            phase = .loaded(details)
        } catch is CancellationError {
        } catch {
            if case .loaded = phase {} else { phase = .failed(UserMessage(error)) }
        }
        canRefreshMetadata = await canRefresh
    }

    /// Takes the tint from the loaded backdrop, fading to it from the neutral tint the screen starts with when it
    /// didn't know the colour yet.
    func backdropLoaded(_ image: CGImage) {
        let measured = ArtworkTint.color(for: image)
        ArtworkMemory.remember(measured, for: id)
        guard measured != tint else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            tint = measured
        }
    }
}
