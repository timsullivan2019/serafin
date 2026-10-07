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
    /// The screen's accent, taken from its backdrop once that loads, or nil until then.
    var tint: Color?
    /// Whether the user can ask the server to refresh the item's metadata, which administrators can.
    private(set) var canRefreshMetadata = false

    init(id: String) {
        self.id = id
    }

    /// Starts with `item` showing, and for a show the episode its Play button starts, while the full details load.
    init(showing item: MediaItem, playable: MediaItem?) {
        id = item.id
        phase = .loaded(ItemDetails(item: item, playable: playable ?? item))
        if item.source == nil {
            tint = MockMedia.tint(for: item.card)
        }
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

    /// Takes the tint from the loaded backdrop.
    func backdropLoaded(_ image: CGImage) {
        tint = ArtworkTint.color(for: image)
    }
}
