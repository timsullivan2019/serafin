import Foundation

extension MediaCard {
    /// The season and episode code shown on cards, such as "S2 E4", or "Special 1" for one of a show's Specials, or
    /// nil for anything but an episode.
    public var episodeCode: String? {
        episodeCode(locale: .current)
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

    /// The line over an episode's title on its show's page, where the season is already chosen: "Episode 3", or
    /// "Special 1" for one of a show's Specials. Nil for anything but an episode.
    public var episodeCaption: String? {
        episodeCaption(locale: .current)
    }

    /// What VoiceOver says for an episode on its show's page, such as "Episode 3, A Case of Identity, 50 minutes,
    /// Watched": the number, the title, the running time or, part way through, how much is watched and left, and
    /// whether it's watched or a favorite.
    public var episodeAccessibilityLabel: String {
        episodeAccessibilityLabel(locale: .current)
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

    func episodeCode(locale: Locale) -> String? {
        guard let episode else { return nil }
        if episode.seasonNumber == 0 {
            return String(
                localized: "Special \(episode.episodeNumber)",
                bundle: .module,
                locale: locale,
                comment: "Code on cards for one of a show's Specials, which aren't in a season, such as Special 2."
            )
        }
        return String(
            localized: "S\(episode.seasonNumber) E\(episode.episodeNumber)",
            bundle: .module,
            locale: locale,
            comment: "Season and episode code on cards, such as S2 E4."
        )
    }

    func episodeCaption(locale: Locale) -> String? {
        guard let episode else { return nil }
        if episode.seasonNumber == 0 {
            return episodeCode(locale: locale)
        }
        return String(
            localized: "Episode \(episode.episodeNumber)",
            bundle: .module,
            locale: locale,
            comment: "The number over an episode's title on its show's page, such as Episode 3. Shown in capitals."
        )
    }

    func episodeAccessibilityLabel(locale: Locale) -> String {
        var parts = [episodeCaption(locale: locale), title].compactMap { $0 }
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
            if let runtime {
                let remaining = Self.spokenDuration(runtime * (1 - progress), locale: locale)
                parts.append(
                    String(
                        localized: "\(remaining) left",
                        bundle: .module,
                        locale: locale,
                        comment: "Time left to watch, such as 32 min left."
                    )
                )
            }
        } else if let runtime {
            parts.append(Self.spokenDuration(runtime, locale: locale))
        }
        if isWatched {
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
            if episode.seasonNumber == 0 {
                parts.append(
                    String(
                        localized: "Special \(episode.episodeNumber)",
                        bundle: .module,
                        locale: locale,
                        comment:
                            "Code on cards for one of a show's Specials, which aren't in a season, such as Special 2."
                    )
                )
            } else {
                parts.append(
                    String(
                        localized: "Season \(episode.seasonNumber), episode \(episode.episodeNumber)",
                        bundle: .module,
                        locale: locale,
                        comment: "Spoken season and episode number of an episode."
                    )
                )
            }
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
