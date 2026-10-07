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
    /// The screen's accent, taken from its backdrop once that loads.
    var tint = Color.accentFallback

    init(id: String) {
        self.id = id
    }

    /// The details once they have loaded.
    var details: ItemDetails? {
        if case .loaded(let details) = phase { details } else { nil }
    }

    /// Loads the details. A failed reload keeps the details already showing.
    func load(from media: any MediaSource) async {
        do {
            let details = try await media.details(of: id)
            if details.item.source == nil {
                tint = MockMedia.tint(for: details.item.card)
            }
            phase = .loaded(details)
        } catch is CancellationError {
        } catch {
            if case .loaded = phase { return }
            phase = .failed(UserMessage(error))
        }
    }

    /// Takes the tint from the loaded backdrop.
    func backdropLoaded(_ image: CGImage) {
        tint = ArtworkTint.color(for: image)
    }
}
