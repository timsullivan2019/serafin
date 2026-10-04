import SerafinDesign
import SwiftUI

/// The media every screen shows.
///
/// Until the server connection arrives in plan task 1.4, it serves the offline fixtures from SerafinDesign, so the
/// whole app can be tapped through without a server.
enum Catalog {
    /// Started movies and episodes, most recent first.
    static var continueWatching: [MediaCard] { MockLibrary.continueWatching }

    /// The next episode of each series the user has started.
    static var nextUp: [MediaCard] { MockLibrary.nextUp }

    /// The user's libraries.
    static var libraries: [MediaLibrary] { MockLibrary.libraries }

    /// The library with `id`, if there is one.
    static func library(id: String) -> MediaLibrary? {
        libraries.first { $0.id == id }
    }

    /// The newest items in `library`, newest first.
    static func latest(in library: MediaLibrary) -> [MediaCard] {
        MockLibrary.latest.filter { library.items.contains($0) }
    }

    /// The movie, series or episode with `id`, if there is one.
    static func item(id: String) -> MediaCard? {
        (MockMedia.movies + MockMedia.series + MockMedia.episodes).first { $0.id == id }
    }

    /// The seasons of a series, in order.
    static func seasons(of series: MediaCard) -> [MediaSeason] {
        MockMedia.seasons(of: series)
    }

    /// The season with `id`, if there is one.
    static func season(id: String) -> MediaSeason? {
        MockMedia.series.lazy.flatMap { MockMedia.seasons(of: $0) }.first { $0.id == id }
    }

    /// The season an episode belongs to.
    static func season(of episode: MediaCard) -> MediaSeason? {
        guard let info = episode.episode, let series = MockMedia.series(of: episode) else { return nil }
        return seasons(of: series).first { $0.number == info.seasonNumber }
    }

    /// The series an episode or season belongs to.
    static func series(id: String) -> MediaCard? {
        MockMedia.series.first { $0.id == id }
    }

    /// Items to suggest after `card`: other movies for a movie, other series for a series.
    static func moreLike(_ card: MediaCard) -> [MediaCard] {
        let pool = card.kind == .series ? MockMedia.series : MockMedia.movies
        return pool.filter { $0.id != card.id }
    }

    /// Movies, series and episodes whose titles contain `term`, ignoring case and accents.
    static func search(_ term: String) -> SearchResults {
        let term = term.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return SearchResults() }
        func matches(_ card: MediaCard) -> Bool { card.title.localizedStandardContains(term) }
        return SearchResults(
            movies: MockMedia.movies.filter(matches),
            shows: MockMedia.series.filter(matches),
            episodes: MockMedia.episodes.filter(matches)
        )
    }

    /// What Play starts for a card: the card itself for a movie or episode, and the episode to watch next for a
    /// series or season.
    static func playable(for card: MediaCard) -> MediaCard {
        let episodes: [MediaCard]
        switch card.kind {
        case .movie, .episode:
            return card
        case .series:
            episodes = seasons(of: card).flatMap(\.episodes)
        case .season:
            episodes = season(id: card.id)?.episodes ?? []
        }
        return episodes.first { !$0.isPlayed } ?? episodes.first ?? card
    }

    /// The poster for a card.
    static func poster(for card: MediaCard) -> Image? {
        MockMedia.posterImage(for: card)
    }

    /// The backdrop or episode thumbnail for a card.
    static func backdrop(for card: MediaCard) -> Image? {
        MockMedia.backdropImage(for: card)
    }

    /// The glass tint for a card's screen, taken from its backdrop.
    static func tint(for card: MediaCard) -> Color {
        MockMedia.tint(for: card)
    }
}

/// Search matches, grouped the way the results screen shows them.
struct SearchResults: Equatable {
    var movies: [MediaCard] = []
    var shows: [MediaCard] = []
    var episodes: [MediaCard] = []

    var isEmpty: Bool { movies.isEmpty && shows.isEmpty && episodes.isEmpty }
}
