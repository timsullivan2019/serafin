import Foundation

/// Rewrites the server's HLS playlists so the text subtitles in its stream show in time with the picture.
///
/// Jellyfin starts each WebVTT segment in its HLS stream with `X-TIMESTAMP-MAP=MPEGTS:900000,LOCAL:00:00:00.000`,
/// which tells the player that cue times run ten seconds behind the video's. That's true of MPEG-TS segments, whose
/// clock the server's muxer starts ten seconds in, but Serafin asks for fragmented MP4 segments, which keep the
/// file's own times, as the cues do. So AVPlayer showed every subtitle ten seconds late. Without the map, it takes cue
/// times as the video's own.
///
/// The master playlist and the subtitle playlists come through ``StreamLoader`` under schemes of Serafin's own, which
/// AVPlayer leaves to the loader. In the master, the subtitle renditions point back at the loader and everything else
/// at the server, so video, audio and the subtitles themselves still come straight from the server. Each subtitle
/// playlist becomes a single segment for the whole track, asked for without the map. A single segment, because the
/// server sends thirty seconds without cues as a bare `WEBVTT`, which AVPlayer can't read without the map after it,
/// and after one segment it can't read, it shows nothing more from that track.
enum SubtitlePlaylists {
    /// The loader's scheme for a server's scheme.
    private static let loaderSchemes = ["https": "serafin-https", "http": "serafin-http"]

    /// Whether the server's stream at `url` is made of fragmented MP4 segments, whose subtitles need putting in time.
    /// Jellyfin sends MPEG-TS segments unless asked otherwise, and its subtitles are in time with those.
    static func isFragmentedMP4(_ url: URL) -> Bool {
        let query = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems ?? []
        return query.contains {
            $0.name.caseInsensitiveCompare("SegmentContainer") == .orderedSame
                && $0.value?.caseInsensitiveCompare("mp4") == .orderedSame
        }
    }

    /// `url` under the loader's scheme, or nil unless it's an HTTP or HTTPS address.
    static func loaderURL(for url: URL) -> URL? {
        replacingScheme(of: url, from: loaderSchemes)
    }

    /// The server's address for `url`, a playlist under the loader's scheme, or nil when it isn't one.
    static func serverURL(for url: URL) -> URL? {
        replacingScheme(of: url, from: Dictionary(uniqueKeysWithValues: loaderSchemes.map { ($1, $0) }))
    }

    /// `playlist`, fetched from `url`, rewritten for AVPlayer: a master playlist with ``master(_:from:)``, and any
    /// other with ``subtitles(_:from:)``, since the master only sends subtitle playlists to the loader.
    static func rewrite(_ playlist: String, from url: URL) -> String {
        let isMaster = lines(of: playlist).contains { $0.hasPrefix("#EXT-X-STREAM-INF:") }
        return isMaster ? master(playlist, from: url) : subtitles(playlist, from: url)
    }

    /// A master playlist fetched from `url`, with its subtitle renditions under the loader's scheme, so their playlists
    /// come through the loader too, and every other address made absolute, since AVPlayer would otherwise resolve
    /// them against the loader's address.
    static func master(_ playlist: String, from url: URL) -> String {
        lines(of: playlist).map { line in
            guard line.hasPrefix("#") else { return absolute(line, from: url) }
            guard let match = line.firstMatch(of: /URI="([^"]*)"/),
                let address = URL(string: String(match.output.1), relativeTo: url)?.absoluteURL
            else { return line }
            let isSubtitles = line.hasPrefix("#EXT-X-MEDIA:") && line.contains(/[:,]TYPE=SUBTITLES(,|$)/)
            let replacement = isSubtitles ? loaderURL(for: address) ?? address : address
            return line.replacingCharacters(in: match.range, with: "URI=\"\(replacement.absoluteString)\"")
        }
        .joined(separator: "\n")
    }

    /// A subtitle playlist fetched from `url`, as one segment for the whole track, asked for without Jellyfin's time
    /// map. A playlist that isn't Jellyfin's, or that's still growing, keeps its segments, with their addresses made
    /// absolute.
    static func subtitles(_ playlist: String, from url: URL) -> String {
        let lines = lines(of: playlist)
        let segments = lines.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.contains("#EXT-X-ENDLIST"),
            let first = segments.first.flatMap({ URL(string: $0, relativeTo: url)?.absoluteURL }),
            let last = segments.last.flatMap({ URL(string: $0, relativeTo: url)?.absoluteURL }),
            let track = wholeTrack(from: first, to: last)
        else {
            return lines.map { $0.hasPrefix("#") ? $0 : absolute($0, from: url) }.joined(separator: "\n")
        }
        let seconds = lines.compactMap(segmentDuration).reduce(0, +)
        return [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:\(Int(seconds.rounded(.up)))",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
            "#EXTINF:\(String(format: "%.3f", seconds)),",
            track.absoluteString,
            "#EXT-X-ENDLIST",
            "",
        ]
        .joined(separator: "\n")
    }

    /// The address of a WebVTT file with every cue from Jellyfin's segments `first` to `last`, at their own times and
    /// without a time map, or nil when `first` isn't Jellyfin's.
    private static func wholeTrack(from first: URL, to last: URL) -> URL? {
        guard var parts = URLComponents(url: first, resolvingAgainstBaseURL: true),
            let query = parts.percentEncodedQueryItems,
            query.contains(where: { $0.name.caseInsensitiveCompare("AddVttTimeMap") == .orderedSame })
        else { return nil }
        let end = URLComponents(url: last, resolvingAgainstBaseURL: true)?.percentEncodedQueryItems?
            .first { $0.name.caseInsensitiveCompare("EndPositionTicks") == .orderedSame }?.value
        parts.percentEncodedQueryItems = query.compactMap { item -> URLQueryItem? in
            switch item.name.lowercased() {
            case "addvtttimemap": URLQueryItem(name: item.name, value: "false")
            case "startpositionticks": URLQueryItem(name: item.name, value: "0")
            case "endpositionticks": end.map { URLQueryItem(name: item.name, value: $0) }
            default: item
            }
        }
        return parts.url
    }

    /// The duration an `#EXTINF` line gives its segment, in seconds, or nil for any other line.
    private static func segmentDuration(_ line: String) -> Double? {
        guard line.hasPrefix("#EXTINF:") else { return nil }
        return Double(line.dropFirst("#EXTINF:".count).prefix { $0 != "," }.trimmingCharacters(in: .whitespaces))
    }

    /// A playlist's lines, without the spaces around them, whichever line breaks it uses.
    private static func lines(of playlist: String) -> [String] {
        playlist.split(separator: /\r\n|\n|\r/, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// A playlist line naming an address, made absolute against `url`. An empty line stays empty.
    private static func absolute(_ line: String, from url: URL) -> String {
        guard !line.isEmpty, let address = URL(string: line, relativeTo: url) else { return line }
        return address.absoluteURL.absoluteString
    }

    private static func replacingScheme(of url: URL, from schemes: [String: String]) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
            let scheme = parts.scheme.flatMap({ schemes[$0.lowercased()] })
        else { return nil }
        parts.scheme = scheme
        return parts.url
    }
}
