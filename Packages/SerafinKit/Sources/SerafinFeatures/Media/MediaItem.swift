import Foundation
import JellyfinAPI
import SerafinDesign

/// An item as screens show it: the card to draw, and the server's item behind it.
struct MediaItem: Identifiable, Hashable, Sendable {
    /// What cards and headers draw.
    var card: MediaCard
    /// The server's item, for its artwork. Nil for the built-in samples, which draw generated art instead.
    var source: BaseItemDto?

    var id: String { card.id }
}

extension MediaItem {
    /// The server's item as a card, or nil when it is a kind Serafin doesn't show, or has no ID.
    init?(_ item: BaseItemDto) {
        guard let id = item.id, !id.isEmpty, let kind = MediaCard.Kind(item.type) else { return nil }
        let userData = item.userData
        var progress = (userData?.playedPercentage ?? 0) / 100
        if progress == 0, let position = userData?.playbackPositionTicks, let length = item.runTimeTicks, length > 0 {
            progress = Double(position) / Double(length)
        }
        var episode: MediaCard.EpisodeInfo?
        if kind == .episode, let seriesID = item.seriesID {
            episode = MediaCard.EpisodeInfo(
                seriesID: seriesID,
                seriesTitle: item.seriesName ?? "",
                seasonNumber: item.parentIndexNumber ?? 0,
                episodeNumber: item.indexNumber ?? 0
            )
        }
        card = MediaCard(
            id: id,
            kind: kind,
            title: item.name ?? "",
            year: item.productionYear,
            runtime: item.runTimeTicks.map { .milliseconds($0 / 10_000) },
            rating: item.officialRating,
            progress: progress,
            isPlayed: userData?.isPlayed ?? false,
            isFavourite: userData?.isFavorite ?? false,
            overview: item.overview.map(PlainText.init).flatMap(\.text),
            episode: episode
        )
        source = item
    }

    /// The server's items as cards, leaving out kinds Serafin doesn't show.
    static func from(_ items: [BaseItemDto]) -> [MediaItem] {
        items.compactMap(MediaItem.init)
    }

    /// What's new in a library, as cards for Home's latest row.
    ///
    /// The server gathers several new episodes of one season into that season. "Season 2" alone doesn't say which
    /// show is new, so the season stands for its series. Each item appears once.
    static func latest(_ items: [BaseItemDto]) -> [MediaItem] {
        var seen: Set<String> = []
        return items.compactMap { item in
            let shown = item.type == .season ? series(of: item) ?? item : item
            guard let mediaItem = MediaItem(shown), seen.insert(mediaItem.id).inserted else { return nil }
            return mediaItem
        }
    }

    /// The series a season belongs to, made from what the season says about it, or nil when that leaves it without
    /// a name or poster.
    private static func series(of season: BaseItemDto) -> BaseItemDto? {
        guard let id = season.seriesID, let name = season.seriesName, let poster = season.seriesPrimaryImageTag else {
            return nil
        }
        return BaseItemDto(id: id, imageTags: [ImageType.primary.rawValue: poster], name: name, type: .series)
    }
}

extension MediaCard.Kind {
    /// The card kind for a server item kind, or nil for kinds Serafin doesn't show, such as music or folders.
    init?(_ type: BaseItemKind?) {
        switch type {
        case .movie: self = .movie
        case .series: self = .series
        case .season: self = .season
        case .episode: self = .episode
        case .boxSet: self = .collection
        default: return nil
        }
    }
}

/// A server's description as plain text.
///
/// Overviews come from metadata providers and sometimes carry HTML. Serafin never renders it: tags are dropped,
/// the few common entities are decoded, and line breaks are kept.
struct PlainText {
    /// The text, or nil when nothing is left.
    let text: String?

    init(_ html: String) {
        var text = html.replacingOccurrences(
            of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
        // Ampersands go last, so "&amp;lt;" becomes "&lt;" rather than "<".
        let entities = [
            ("&nbsp;", " "), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
            ("&amp;", "&"),
        ]
        for (entity, character) in entities {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = trimmed.isEmpty ? nil : trimmed
    }
}

extension Genre {
    /// A genre from the server's list, or nil without an ID or a name.
    init?(_ item: BaseItemDto) {
        guard let id = item.id, !id.isEmpty, let name = item.name, !name.isEmpty else { return nil }
        let counts = [item.movieCount, item.seriesCount].compactMap { $0 }
        self.init(id: id, name: name, count: counts.isEmpty ? nil : counts.reduce(0, +))
    }
}
