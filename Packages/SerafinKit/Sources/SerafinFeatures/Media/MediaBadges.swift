import Foundation
import JellyfinAPI
import SerafinDesign

/// The badges a detail screen shows for a movie's or an episode's file, following `docs/PLAN-2.md` §0.3: resolution,
/// then range, then audio, then accessibility.
enum MediaBadges {
    /// The badges for `item`'s first version, or none when the server lists no streams.
    static func badges(for item: BaseItemDto) -> [String] {
        let source = item.mediaSources?.first
        let streams = source?.mediaStreams ?? item.mediaStreams ?? []
        let video = streams.first { $0.type == .video }
        let audio =
            streams.first { $0.type == .audio && $0.index == source?.defaultAudioStreamIndex }
            ?? streams.first { $0.type == .audio }
        let subtitles = streams.filter { $0.type == .subtitle }
        return [resolution(of: video), range(of: video)].compactMap { $0 } + audioBadges(of: audio)
            + accessibility(of: subtitles)
    }

    /// 4K or HD. A wide film can be 4K at well under 2160 lines, so its width counts too.
    static func resolution(of video: MediaStream?) -> String? {
        let width = video?.width ?? 0
        let height = video?.height ?? 0
        if height >= 2160 || width >= 3800 { return "4K" }
        if height >= 720 || width >= 1260 { return "HD" }
        return nil
    }

    /// Dolby Vision, HDR10+ or HDR.
    static func range(of video: MediaStream?) -> String? {
        switch video?.videoRangeType {
        case .dovi, .doviWithHDR10, .doviWithHLG, .doviWithSDR, .doviWithEL, .doviWithHDR10Plus, .doviWithELHDR10Plus:
            "Dolby Vision"
        case .hdr10Plus: "HDR10+"
        case .hdr10, .hlg: "HDR"
        case .sdr, .unknown, .doviInvalid, nil: nil
        }
    }

    /// Dolby Atmos, then 5.1 or 7.1, then Lossless, for the audio that plays by default.
    static func audioBadges(of audio: MediaStream?) -> [String] {
        guard let audio else { return [] }
        let codec = audio.codec?.lowercased() ?? ""
        let described = [audio.profile, audio.title, audio.displayTitle].compactMap { $0 }.joined(separator: " ")
        var badges: [String] = []
        // The server names Atmos in the stream's profile, as for E-AC-3 JOC and TrueHD with Atmos.
        if described.localizedCaseInsensitiveContains("atmos") {
            badges.append("Dolby Atmos")
        }
        switch audio.channels {
        case 6: badges.append("5.1")
        case 8: badges.append("7.1")
        default: break
        }
        if ["flac", "alac", "truehd"].contains(codec) {
            badges.append("Lossless")
        }
        return badges
    }

    /// SDH when a subtitle track is for the deaf and hard of hearing, otherwise CC when there are subtitles at all.
    static func accessibility(of subtitles: [MediaStream]) -> [String] {
        if subtitles.contains(where: { $0.isHearingImpaired == true }) { return ["SDH"] }
        if subtitles.contains(where: { $0.isForced != true }) { return ["CC"] }
        return []
    }
}

/// A trailer on a detail screen: a link the server lists, such as on YouTube, or a file stored with the item.
struct Trailer: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// A web page, opened in Safari inside the app. Always `https`.
        case web(URL)
        /// A file on the server, played in the normal player.
        case local(MediaItem)
    }

    let id: String
    /// The trailer's name, as the server gives it.
    let name: String
    let source: Source

    /// The trailers the server lists for `item`: its web links, keeping only `https` ones, then `local`.
    static func trailers(for item: BaseItemDto, local: [BaseItemDto]) -> [Trailer] {
        let fallbackName = String(localized: "Trailer", bundle: .module, comment: "The name of a trailer with none.")
        let web: [Trailer] = (item.remoteTrailers ?? []).enumerated().compactMap { index, trailer in
            guard let text = trailer.url, let url = URL(string: text), url.scheme?.lowercased() == "https",
                url.host() != nil
            else { return nil }
            let name = trailer.name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
            return Trailer(id: "web-\(index)", name: name, source: .web(url))
        }
        let files: [Trailer] = local.compactMap { trailer in
            guard let id = trailer.id else { return nil }
            let name = trailer.name.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackName
            let card = MediaCard(
                id: id, kind: .movie, title: name,
                runtime: trailer.runTimeTicks.flatMap { $0 > 0 ? .milliseconds($0 / 10_000) : nil })
            return Trailer(id: "local-\(id)", name: name, source: .local(MediaItem(card: card, source: trailer)))
        }
        return files + web
    }
}

/// A chapter of a movie or episode, for its detail screen's Chapters row.
struct Chapter: Identifiable, Hashable, Sendable {
    /// The chapter's place among the item's chapters, from 0, which its picture's address uses.
    let index: Int
    /// The chapter's name.
    let name: String
    /// Where it starts.
    let start: Duration
    /// Its picture's tag, or nil when the server hasn't made one.
    let imageTag: String?

    var id: Int { index }

    /// The chapters the server lists for `item`, in order.
    static func chapters(of item: BaseItemDto) -> [Chapter] {
        (item.chapters ?? []).enumerated().map { index, chapter in
            let name =
                chapter.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? String(
                    localized: "Chapter \(index + 1)", bundle: .module,
                    comment: "The name of a chapter the file doesn't name, such as Chapter 3.")
            return Chapter(
                index: index,
                name: name,
                start: .milliseconds((chapter.startPositionTicks ?? 0) / 10_000),
                imageTag: chapter.imageTag
            )
        }
    }

    /// Where the chapter starts, as its card says it, such as "1:02:40" or "12:40".
    var startText: String {
        start.formatted(.time(pattern: start >= .seconds(3600) ? .hourMinuteSecond : .minuteSecond))
    }
}
