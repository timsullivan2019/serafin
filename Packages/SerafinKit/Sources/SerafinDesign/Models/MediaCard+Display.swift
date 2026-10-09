import Foundation

extension MediaCard {
    /// The season and episode code shown on cards, such as "S2 E4", or nil for anything but an episode.
    public var episodeCode: String? {
        guard let episode else { return nil }
        return String(
            localized: "S\(episode.seasonNumber) E\(episode.episodeNumber)",
            bundle: .module,
            comment: "Season and episode code on cards, such as S2 E4."
        )
    }

    /// The line above an episode's title, such as "Caminandes · S1 E2", or the year for anything else.
    public var eyebrowText: String? {
        if let episode, let episodeCode {
            return String(
                localized: "\(episode.seriesTitle) · \(episodeCode)",
                bundle: .module,
                comment:
                    "Two parts of a line joined by a dot: a series title and episode code above an episode title (Caminandes · S1 E2), or a show's next episode under its details (S2 E4 · The Final Problem)."
            )
        }
        return year.map(String.init)
    }

    /// The title under a poster: an episode's series title, since an episode's poster is its series', otherwise the
    /// card's own title.
    public var posterTitle: String {
        guard let seriesTitle = episode?.seriesTitle, !seriesTitle.isEmpty else { return title }
        return seriesTitle
    }

    /// The line under a poster's title: an episode's code, such as "S2 E4", otherwise the year. A collection spans
    /// years, so it has none.
    public var posterCaption: String? {
        guard kind != .collection else { return nil }
        return episodeCode ?? year.map(String.init)
    }

    /// The running time for display, such as "1 hr, 39 min".
    public var runtimeText: String? {
        runtimeText(locale: .current)
    }

    /// The time left to watch, such as "32 min left", or nil unless the item is in progress.
    public var remainingText: String? {
        remainingText(locale: .current)
    }

    /// A description for VoiceOver, such as "Sintel, 2010, 40% watched, 1 hour left".
    public var accessibilityLabel: String {
        accessibilityLabel(locale: .current)
    }

    func runtimeText(locale: Locale) -> String? {
        runtime.map { Self.durationText($0, locale: locale) }
    }

    func remainingText(locale: Locale) -> String? {
        guard isInProgress, let runtime else { return nil }
        let remaining = Self.durationText(runtime * (1 - progress), locale: locale)
        return String(
            localized: "\(remaining) left",
            bundle: .module,
            locale: locale,
            comment: "Time left to watch, such as 32 min left."
        )
    }

    /// The description without "Watched", for a card that leaves off its watched check.
    var accessibilityLabelWithoutPlayed: String {
        accessibilityLabel(locale: .current, includesPlayed: false)
    }

    func accessibilityLabel(locale: Locale, includesPlayed: Bool = true) -> String {
        var parts = [title]
        if let episode {
            parts.append(episode.seriesTitle)
            parts.append(
                String(
                    localized: "Season \(episode.seasonNumber), episode \(episode.episodeNumber)",
                    bundle: .module,
                    locale: locale,
                    comment: "Spoken season and episode number of an episode."
                )
            )
        } else if kind == .collection {
            parts.append(
                String(
                    localized: "Collection", bundle: .module, locale: locale,
                    comment: "Spoken kind of a card that opens a collection of movies.")
            )
        } else if let year {
            parts.append(String(year))
        }
        if isInProgress {
            let percent = progress.formatted(.percent.precision(.fractionLength(0)).locale(locale))
            parts.append(
                String(
                    localized: "\(percent) watched",
                    bundle: .module,
                    locale: locale,
                    comment: "Spoken progress, such as 40% watched."
                )
            )
        }
        // The time the card shows: what's left of a started item, otherwise a movie's or an episode's running time.
        if let runtime, kind == .movie || kind == .episode {
            if isInProgress {
                let remaining = Self.spokenDuration(runtime * (1 - progress), locale: locale)
                parts.append(
                    String(
                        localized: "\(remaining) left",
                        bundle: .module,
                        locale: locale,
                        comment: "Time left to watch, such as 32 min left."
                    )
                )
            } else {
                parts.append(Self.spokenDuration(runtime, locale: locale))
            }
        }
        if isWatched, includesPlayed {
            parts.append(
                String(
                    localized: "Watched", bundle: .module, locale: locale, comment: "Spoken state of a watched item.")
            )
        }
        if isFavourite {
            parts.append(
                String(
                    localized: "Favorite",
                    bundle: .module,
                    locale: locale,
                    comment: "Spoken state of a favorite item."
                )
            )
        }
        return parts.formatted(.list(type: .and, width: .narrow).locale(locale))
    }

    /// Formats a running time in hours and minutes, rounding any part minute up.
    static func durationText(_ duration: Duration, locale: Locale) -> String {
        duration.formatted(
            .units(allowed: [.hours, .minutes], width: .abbreviated, fractionalPart: .hide(rounded: .up))
                .locale(locale)
        )
    }

    /// A running time as VoiceOver says it, in whole words, such as "1 hour, 39 minutes".
    static func spokenDuration(_ duration: Duration, locale: Locale) -> String {
        duration.formatted(
            .units(allowed: [.hours, .minutes], width: .wide, fractionalPart: .hide(rounded: .up)).locale(locale)
        )
    }
}
