import Foundation
import JellyfinAPI

/// Puts the closest titles first in search results: an exact title, then titles that start with what was typed,
/// then the rest in the server's order.
///
/// A title matches with or without a leading article, through the server's sort name, so "godfather" finds
/// "The Godfather" before "The Godfather Part II". Case, accents and character widths don't matter.
enum SearchRanking {
    /// `items` with the closest titles to `term` first, otherwise in their order.
    static func ranked(_ items: [BaseItemDto], for term: String) -> [BaseItemDto] {
        let term = normalised(term)
        guard !term.isEmpty else { return items }
        return items.enumerated()
            .map { (rank: rank(of: $0.element, for: term), position: $0.offset, item: $0.element) }
            .sorted { ($0.rank, $0.position) < ($1.rank, $1.position) }
            .map(\.item)
    }

    /// 0 for an exact title, 1 for a title that starts with `term`, 2 for anything else.
    private static func rank(of item: BaseItemDto, for term: String) -> Int {
        let titles = [item.name, item.sortName].compactMap { $0 }.map(normalised)
        if titles.contains(term) { return 0 }
        if titles.contains(where: { $0.hasPrefix(term) }) { return 1 }
        return 2
    }

    private static func normalised(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
