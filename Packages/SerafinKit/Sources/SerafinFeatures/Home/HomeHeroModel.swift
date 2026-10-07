import Foundation
import Nuke
import SerafinCore
import SerafinDesign

/// What Home's hero features: up to five items picked from Home's rows, the episode each show's Play button starts,
/// and the page showing.
@Observable @MainActor final class HomeHeroModel {
    /// One featured item, with the episode Play starts when it's a show.
    struct Entry: Identifiable, Sendable {
        /// The featured movie, show or episode.
        let item: MediaItem
        /// For a show, the episode Play starts, once it's known.
        var playable: MediaItem?

        var id: String { item.id }

        /// The item as the hero draws it.
        var hero: HeroItem { HeroItem(card: item.card, playable: playable?.card) }
    }

    /// The most items the hero features.
    nonisolated static let limit = 5

    /// The featured items, in order.
    private(set) var entries: [Entry] = []
    /// The page showing, or nil for the first.
    var selection: String?
    /// Keeps the next page's artwork loading. Letting it go cancels what it's loading.
    private var prefetcher: ImagePrefetcher?

    /// The featured items as the hero draws them.
    var items: [HeroItem] { entries.map(\.hero) }

    /// The featured item with `id`.
    func entry(_ id: String) -> Entry? {
        entries.first { $0.id == id }
    }

    /// Picks the featured items from Home's rows. Shows keep the episode already found for them, and the page
    /// showing stays when its item is still featured.
    ///
    /// - Parameters:
    ///   - home: Home's rows.
    ///   - hasArtwork: Whether an item has a backdrop or a poster, since the hero needs one or the other.
    func update(from home: HomeContent, hasArtwork: (MediaItem) -> Bool) {
        let known = Dictionary(entries.map { ($0.id, $0.playable) }, uniquingKeysWith: { first, _ in first })
        entries = Self.candidates(from: home, hasArtwork: hasArtwork).map { item in
            Entry(item: item, playable: known[item.id] ?? nil)
        }
        if let selection, entry(selection) == nil {
            self.selection = nil
        }
    }

    /// Finds the episode each featured show's Play button starts. A show whose episode can't be found plays what
    /// its detail screen would, once tapped.
    func findEpisodes(from media: any MediaSource) async {
        let shows = entries.filter { $0.item.card.kind == .series && $0.playable == nil }.map(\.id)
        guard !shows.isEmpty else { return }
        let found = await withTaskGroup(of: (String, MediaItem?).self) { group in
            for id in shows {
                group.addTask { (id, try? await media.playable(ofSeries: id)) }
            }
            var found: [String: MediaItem] = [:]
            for await (id, episode) in group {
                if let episode { found[id] = episode }
            }
            return found
        }
        for index in entries.indices {
            if let episode = found[entries[index].id] {
                entries[index].playable = episode
            }
        }
    }

    /// Starts loading the artwork of the page after `selection`, so swiping to it never shows it arriving.
    ///
    /// The requests match the page's own: the backdrop, or the poster standing in for it, at the page's width, and
    /// the logo at ``HomeHeroPage/logoWidth``.
    func prefetchPage(after selection: String?, width: CGFloat, scale: CGFloat, artwork: Artwork?) {
        guard let artwork, width > 0, !entries.isEmpty else { return }
        let current = entries.firstIndex { $0.id == selection } ?? 0
        let next = current + 1
        guard entries.indices.contains(next), let source = entries[next].item.source else { return }
        let backdropRole: ImageRole = HomeHeroPage.hasBackdrop(source, artwork: artwork) ? .backdrop : .poster
        let requests = [
            artwork.request(backdropRole, of: source, width: width, scale: scale),
            artwork.request(.logo, of: source, width: HomeHeroPage.logoWidth, scale: scale),
        ]
        .compactMap { $0 }
        if prefetcher == nil {
            prefetcher = ImagePrefetcher(pipeline: artwork.pipeline)
        }
        prefetcher?.startPrefetching(with: requests)
    }

    /// The items to feature, in order: the most recently played item in progress, the first Next Up episode, then
    /// the newest additions across the libraries, up to ``limit``.
    ///
    /// An item already featured isn't featured again, and neither is a show whose episode is, or an episode whose
    /// show is. Items with neither a backdrop nor a poster are skipped, as are seasons and collections.
    nonisolated static func candidates(from home: HomeContent, hasArtwork: (MediaItem) -> Bool) -> [MediaItem] {
        var picked: [MediaItem] = []
        var featured: Set<String> = []

        func feature(_ item: MediaItem) -> Bool {
            guard picked.count < limit, [.movie, .series, .episode].contains(item.card.kind), hasArtwork(item) else {
                return false
            }
            let ids = [item.id] + [item.card.episode?.seriesID].compactMap { $0 }
            guard featured.isDisjoint(with: ids) else { return false }
            featured.formUnion(ids)
            picked.append(item)
            return true
        }

        for item in mostRecentlyPlayed(home.continueWatching.filter(\.card.isInProgress)) {
            if feature(item) { break }
        }
        for item in home.nextUp {
            if feature(item) { break }
        }
        for item in newest(home.latest.map(\.items)) {
            _ = feature(item)
        }
        return picked
    }

    /// Started items, the most recently played first. Items the server gives no date keep their order, after the
    /// dated ones.
    nonisolated static func mostRecentlyPlayed(_ items: [MediaItem]) -> [MediaItem] {
        items.enumerated()
            .sorted { first, second in
                let firstDate = first.element.source?.userData?.lastPlayedDate ?? .distantPast
                let secondDate = second.element.source?.userData?.lastPlayedDate ?? .distantPast
                return firstDate != secondDate ? firstDate > secondDate : first.offset < second.offset
            }
            .map(\.element)
    }

    /// The libraries' newest items merged, newest first by the date each was added. Items with no date take turns
    /// from each library, in each library's order, after the dated ones.
    nonisolated static func newest(_ rows: [[MediaItem]]) -> [MediaItem] {
        let turns = rows.enumerated().flatMap { row, items in
            items.enumerated().map { position, item in (item: item, turn: position * rows.count + row) }
        }
        return
            turns
            .sorted { first, second in
                let firstDate = first.item.source?.dateCreated ?? .distantPast
                let secondDate = second.item.source?.dateCreated ?? .distantPast
                return firstDate != secondDate ? firstDate > secondDate : first.turn < second.turn
            }
            .map(\.item)
    }
}
