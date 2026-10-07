import Foundation
import JellyfinAPI
import SerafinDesign

/// The facts at the foot of a detail screen, in three columns: when it came out and how long it runs, its languages,
/// and the format of its video and audio.
enum ItemInformation {
    /// The columns for `item`, whose card is `card`. Rows with nothing to say are left out, and columns without any
    /// rows are dropped by the view.
    static func columns(for item: BaseItemDto, card: MediaCard, locale: Locale = .current)
        -> [InformationColumns.Column]
    {
        let streams = item.mediaSources?.first?.mediaStreams ?? item.mediaStreams ?? []
        let columns = [
            InformationColumns.Column(
                title: String(localized: "Information", bundle: .module, comment: "Detail screen column heading."),
                rows: facts(of: item, card: card, locale: locale)
            ),
            InformationColumns.Column(
                title: String(
                    localized: "Languages", bundle: .module,
                    comment:
                        "Languages: a detail screen's column heading, and the Settings section for preferred languages."
                ),
                rows: languages(in: streams, locale: locale)
            ),
            InformationColumns.Column(
                title: String(localized: "Format", bundle: .module, comment: "Detail screen column heading."),
                rows: format(of: streams, defaultAudio: item.mediaSources?.first?.defaultAudioStreamIndex)
            ),
        ]
        return columns.map { column in
            var column = column
            column.rows.removeAll { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return column
        }
    }

    /// Release date, running time, rating, genres and studio.
    static func facts(of item: BaseItemDto, card: MediaCard, locale: Locale) -> [InformationColumns.Row] {
        var rows: [InformationColumns.Row] = []
        let released =
            card.kind == .series
            ? String(localized: "First Aired", bundle: .module, comment: "Detail fact: when a show started.")
            : String(localized: "Released", bundle: .module, comment: "Detail fact: release date.")
        if let date = item.premiereDate {
            // Servers store release dates as midnight UTC, so they're read in UTC to land on the right day.
            let style = Date.FormatStyle(date: .long, time: .omitted, locale: locale, timeZone: .gmt)
            rows.append(InformationColumns.Row(label: released, value: date.formatted(style)))
        } else if let year = card.year {
            rows.append(InformationColumns.Row(label: released, value: String(year)))
        }
        // A server that never measured a file says zero, which isn't worth a row. A show's run time is how long its
        // episodes run, which the server gives as their average.
        if let runtime = card.runtime, runtime > .zero, let text = card.runtimeText {
            rows.append(
                InformationColumns.Row(
                    label: String(localized: "Run Time", bundle: .module, comment: "Detail fact: running time."),
                    value: card.kind == .series
                        ? String(
                            localized: "\(text) per episode", bundle: .module,
                            comment:
                                "A show's run time: how long its episodes run on average, such as 45 min per episode.")
                        : text
                )
            )
        }
        if let rating = item.officialRating, !rating.isEmpty {
            rows.append(
                InformationColumns.Row(
                    label: String(localized: "Rated", bundle: .module, comment: "Detail fact: age rating."),
                    value: rating
                )
            )
        }
        if let genres = item.genres?.filter({ !$0.isEmpty }), !genres.isEmpty {
            rows.append(
                InformationColumns.Row(
                    label: String(localized: "Genres", bundle: .module, comment: "Genres, as a heading or a label."),
                    value: genres.formatted(.list(type: .and, width: .narrow).locale(locale))
                )
            )
        }
        if let studios = item.studios?.compactMap(\.name).filter({ !$0.isEmpty }), !studios.isEmpty {
            rows.append(
                InformationColumns.Row(
                    label: String(localized: "Studio", bundle: .module, comment: "Detail fact: studio or network."),
                    value: studios.formatted(.list(type: .and, width: .narrow).locale(locale))
                )
            )
        }
        return rows
    }

    /// The languages of the audio and subtitle tracks, each once, in the file's order.
    static func languages(in streams: [MediaStream], locale: Locale) -> [InformationColumns.Row] {
        func names(_ type: MediaStreamType) -> [String] {
            var seen: Set<String> = []
            return streams.filter { $0.type == type }.compactMap { stream in
                guard let code = stream.language, code != "und",
                    let name = locale.localizedString(forLanguageCode: code), seen.insert(name).inserted
                else { return nil }
                return name
            }
        }
        var rows: [InformationColumns.Row] = []
        let audio = names(.audio)
        if !audio.isEmpty {
            rows.append(
                InformationColumns.Row(
                    label: String(
                        localized: "Audio", bundle: .module, comment: "Detail fact: the audio's languages or format."),
                    items: audio,
                    locale: locale
                )
            )
        }
        let subtitles = names(.subtitle)
        if !subtitles.isEmpty {
            rows.append(
                InformationColumns.Row(
                    label: String(
                        localized: "Subtitles", bundle: .module,
                        comment:
                            "Subtitles: a detail fact listing subtitle languages, and the Settings row for when subtitles show."
                    ),
                    items: subtitles,
                    locale: locale
                )
            )
        }
        return rows
    }

    /// The video's resolution and dynamic range, and the default audio's format and channels.
    static func format(of streams: [MediaStream], defaultAudio: Int?) -> [InformationColumns.Row] {
        var rows: [InformationColumns.Row] = []
        if let video = streams.first(where: { $0.type == .video }), let resolution = resolution(of: video) {
            let parts = [resolution, video.videoRangeType.flatMap(rangeName)].compactMap { $0 }
            rows.append(
                InformationColumns.Row(
                    label: String(localized: "Video", bundle: .module, comment: "Detail fact: video format."),
                    value: parts.joined(separator: " · ")
                )
            )
        }
        let audio =
            streams.first { $0.type == .audio && $0.index == defaultAudio }
            ?? streams.first { $0.type == .audio }
        if let audio, let codec = audio.codec, !codec.isEmpty {
            let parts = [TrackChoices.formatName(codec), audio.channelLayout.map(TrackChoices.channelsName)]
                .compactMap { $0 }
            rows.append(
                InformationColumns.Row(
                    label: String(
                        localized: "Audio", bundle: .module, comment: "Detail fact: the audio's languages or format."),
                    value: parts.joined(separator: " · ")
                )
            )
        }
        return rows
    }

    /// A video's resolution as people say it, such as "4K" or "1080p".
    static func resolution(of video: MediaStream) -> String? {
        guard let width = video.width, let height = video.height, width > 0, height > 0 else { return nil }
        // Widescreen films are short for their width, so the width decides as much as the height.
        return switch (width, height) {
        case (3800..., _), (_, 2100...): "4K"
        case (1900..., _), (_, 1060...): "1080p"
        case (1200..., _), (_, 700...): "720p"
        default: String(localized: "SD", bundle: .module, comment: "Standard definition video.")
        }
    }

    /// A dynamic range's name, or nil for standard range.
    static func rangeName(_ range: VideoRangeType) -> String? {
        switch range {
        case .dovi, .doviWithHDR10, .doviWithHLG, .doviWithSDR, .doviWithEL, .doviWithHDR10Plus, .doviWithELHDR10Plus:
            "Dolby Vision"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .hlg: "HLG"
        case .sdr, .unknown, .doviInvalid: nil
        }
    }
}
