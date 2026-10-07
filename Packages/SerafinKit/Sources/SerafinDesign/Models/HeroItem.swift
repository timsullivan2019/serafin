import Foundation

/// One featured item at the top of Home: a movie, a series or an episode, and for a series, the episode its Play
/// button starts.
public struct HeroItem: Identifiable, Hashable, Sendable {
    /// The featured movie, series or episode.
    public var card: MediaCard
    /// For a series, the episode Play starts, once it's known. Nil for anything else.
    public var playable: MediaCard?

    /// The featured card's identifier.
    public var id: String { card.id }

    /// Creates a featured item.
    ///
    /// - Parameters:
    ///   - card: The featured movie, series or episode.
    ///   - playable: For a series, the episode Play starts, or nil while it isn't known.
    public init(card: MediaCard, playable: MediaCard? = nil) {
        self.card = card
        self.playable = playable
    }

    /// The large title: an episode's series, since its logo is the series', otherwise the card's own title.
    public var heading: String {
        card.posterTitle
    }

    /// The line under the title: "Sherlock Holmes · S1 E3 · A Case of Identity" for an episode, "1927 · 1 hr 32 min ·
    /// NR" for a movie, and the year and rating for a series.
    ///
    /// - Parameter includesSeries: Whether an episode's line starts with its series, which the title already says
    ///   when there's no logo.
    public func metadata(includesSeries: Bool) -> String {
        metadata(includesSeries: includesSeries, locale: .current)
    }

    /// The Play button's title: "Resume · 9 min left" for something in progress, "Play S1 E1" for an episode or a
    /// series, "Play" for a movie.
    public var playTitle: String {
        playTitle(locale: .current)
    }

    /// What VoiceOver says for the whole page, such as "Featured: Sherlock Holmes, A Case of Identity, 9 minutes
    /// left".
    public var accessibilityLabel: String {
        accessibilityLabel(locale: .current)
    }

    /// The name of the accessibility action that plays: "Resume", "Play S1 E1" or "Play".
    public var playActionName: String {
        playActionName(locale: .current)
    }

    /// What Play starts: the series' episode once known, otherwise the card itself.
    var playTarget: MediaCard {
        playable ?? card
    }

    func metadata(includesSeries: Bool, locale: Locale) -> String {
        var parts: [String] = []
        switch card.kind {
        case .episode:
            if includesSeries, let series = card.episode?.seriesTitle, !series.isEmpty {
                parts.append(series)
            }
            if let code = card.episodeCode(locale: locale) {
                parts.append(code)
            }
            parts.append(card.title)
        case .movie, .season, .collection:
            if let year = card.year { parts.append(String(year)) }
            if let runtime = card.runtime { parts.append(MediaCard.compactDurationText(runtime, locale: locale)) }
            if let rating = card.rating { parts.append(rating) }
        case .series:
            if let year = card.year { parts.append(String(year)) }
            if let rating = card.rating { parts.append(rating) }
        }
        return parts.joined(separator: " · ")
    }

    func playTitle(locale: Locale) -> String {
        if let remaining = playTarget.remainingText(locale: locale) {
            return String(
                localized: "Resume · \(remaining)",
                bundle: .module,
                locale: locale,
                comment: "Button that resumes playback, such as Resume · 32 min left."
            )
        }
        if let code = playCode(locale: locale) {
            return String(
                localized: "Play \(code)",
                bundle: .module,
                locale: locale,
                comment: "Button on Home's featured show or episode that plays an episode, such as Play S1 E1."
            )
        }
        return String(localized: "Play", bundle: .module, locale: locale, comment: "Button that starts playback.")
    }

    func playActionName(locale: Locale) -> String {
        if playTarget.isInProgress {
            return String(
                localized: "Resume", bundle: .module, locale: locale,
                comment: "Accessibility action that resumes a featured item on Home.")
        }
        return playTitle(locale: locale)
    }

    /// The episode Play starts, as a code: an episode's own, a series' known episode, or the first episode of a
    /// series nobody has started.
    private func playCode(locale: Locale) -> String? {
        switch card.kind {
        case .episode:
            return card.episodeCode(locale: locale)
        case .series:
            if let playable { return playable.episodeCode(locale: locale) }
            guard card.progress == 0, !card.isPlayed else { return nil }
            return String(
                localized: "S\(1) E\(1)",
                bundle: .module,
                locale: locale,
                comment: "Season and episode code on cards, such as S2 E4."
            )
        case .movie, .season, .collection:
            return nil
        }
    }

    func accessibilityLabel(locale: Locale) -> String {
        var parts: [String] = []
        if card.kind == .episode, let series = card.episode?.seriesTitle, !series.isEmpty {
            parts.append(series)
            parts.append(card.title)
        } else {
            parts.append(card.title)
            if let year = card.year { parts.append(String(year)) }
        }
        let target = playTarget
        if target.isInProgress, let runtime = target.runtime {
            let remaining = MediaCard.spokenDuration(runtime * (1 - target.progress), locale: locale)
            parts.append(
                String(
                    localized: "\(remaining) left",
                    bundle: .module,
                    locale: locale,
                    comment: "Time left to watch, such as 32 min left."
                )
            )
        } else if let runtime = card.runtime, card.kind == .movie || card.kind == .episode {
            parts.append(MediaCard.spokenDuration(runtime, locale: locale))
        }
        let description = parts.formatted(.list(type: .and, width: .narrow).locale(locale))
        return String(
            localized: "Featured: \(description)",
            bundle: .module,
            locale: locale,
            comment: "Spoken label of a featured item on Home, such as Featured: Sherlock Holmes, A Case of Identity."
        )
    }
}

extension MediaCard {
    /// The season and episode code in `locale`.
    func episodeCode(locale: Locale) -> String? {
        guard let episode else { return nil }
        return String(
            localized: "S\(episode.seasonNumber) E\(episode.episodeNumber)",
            bundle: .module,
            locale: locale,
            comment: "Season and episode code on cards, such as S2 E4."
        )
    }

    /// A running time as a metadata line shows it, with no comma between the parts, such as "1 hr 32 min".
    static func compactDurationText(_ duration: Duration, locale: Locale) -> String {
        let minutes = Int((duration / .seconds(60)).rounded(.up))
        let hours = minutes / 60
        let rest = minutes % 60
        let style = Duration.UnitsFormatStyle.units(allowed: [.hours, .minutes], width: .abbreviated).locale(locale)
        var parts: [String] = []
        if hours > 0 { parts.append(Duration.seconds(hours * 3600).formatted(style)) }
        if rest > 0 || hours == 0 { parts.append(Duration.seconds(rest * 60).formatted(style)) }
        return parts.joined(separator: " ")
    }
}
