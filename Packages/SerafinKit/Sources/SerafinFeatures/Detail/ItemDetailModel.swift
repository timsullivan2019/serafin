import Observation
import SerafinDesign
import SwiftUI

/// What a movie, series or episode detail screen shows.
@Observable @MainActor final class ItemDetailModel {
    let id: String
    let card: MediaCard?
    /// The seasons of a series.
    let seasons: [MediaSeason]
    /// The other episodes of an episode's season.
    let seasonEpisodes: [MediaCard]
    /// Suggestions after a movie or series.
    let moreLike: [MediaCard]
    /// The screen's accent, taken from the backdrop.
    let tint: Color

    init(id: String) {
        self.id = id
        let card = Catalog.item(id: id)
        self.card = card
        switch card?.kind {
        case .series:
            seasons = card.map(Catalog.seasons(of:)) ?? []
            seasonEpisodes = []
            moreLike = card.map(Catalog.moreLike) ?? []
        case .episode:
            seasons = []
            seasonEpisodes = card.flatMap(Catalog.season(of:))?.episodes.filter { $0.id != id } ?? []
            moreLike = []
        default:
            seasons = []
            seasonEpisodes = []
            moreLike = card.map(Catalog.moreLike) ?? []
        }
        tint = card.map(Catalog.tint(for:)) ?? .accentFallback
    }

    /// The overview to show: the item's own, or its series' when an episode has none.
    var overview: String? {
        guard let card else { return nil }
        if let overview = card.overview { return overview }
        return card.episode.flatMap { Catalog.series(id: $0.seriesID)?.overview }
    }
}
