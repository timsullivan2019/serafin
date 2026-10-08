import Foundation
import JellyfinAPI
import os

/// The Intro Skipper plugin's own endpoints, for servers older than Jellyfin 10.10, which have no media segments.
///
/// From Jellyfin 10.10 the plugin puts what it finds in the server's media segments, which respect what an
/// administrator has hidden, so the repository only asks here when the server has no `/MediaSegments` at all.
/// Builds for Jellyfin 10.8 to 10.10 answer `/Episode/{id}/IntroSkipperSegments` with each kind they found, keyed by
/// name; the original plugin answers only `/Episode/{id}/IntroTimestamps`, with the intro. Times are in seconds.
enum IntroSkipper {
    private static let logger = Logger(serafinCategory: "segments")
    /// The largest answer read. A few segments take a few hundred bytes; this stops a server sending something huge.
    static let responseLimit = 64 * 1024

    /// The segments the plugin found in the episode `itemID`, or none.
    static func segments(of itemID: String, client: JellyfinClient) async -> [PlaybackSegment] {
        switch await answer(at: "/Episode/\(itemID)/IntroSkipperSegments", client: client) {
        case .data(let data):
            return segments(inSegmentsAnswer: data)
        case .missing:
            // The original plugin, before it found credits.
            guard case .data(let data) = await answer(at: "/Episode/\(itemID)/IntroTimestamps", client: client)
            else { return [] }
            return segments(inTimestampsAnswer: data)
        case .failed:
            return []
        }
    }

    /// The segments in an answer from `/Episode/{id}/IntroSkipperSegments`: an object keyed by kind, each with its
    /// start and end in seconds, named `IntroStart` and `IntroEnd` before plugin builds for Jellyfin 10.11 and
    /// `Start` and `End` since. Kinds and entries Serafin can't read are left out.
    static func segments(inSegmentsAnswer data: Data) -> [PlaybackSegment] {
        guard data.count <= responseLimit,
            let entries = try? JSONDecoder().decode([String: LossyEntry].self, from: data)
        else { return [] }
        let found = entries.compactMap { name, entry -> PlaybackSegment? in
            guard let kind = kind(named: name) else { return nil }
            return entry.value?.segment(kind)
        }
        return PlaybackSegment.normalized(found)
    }

    /// The intro in an answer from `/Episode/{id}/IntroTimestamps`.
    static func segments(inTimestampsAnswer data: Data) -> [PlaybackSegment] {
        guard data.count <= responseLimit, let entry = try? JSONDecoder().decode(Entry.self, from: data),
            let intro = entry.segment(.intro)
        else { return [] }
        return [intro]
    }

    /// The kind the plugin calls `name`.
    private static func kind(named name: String) -> PlaybackSegment.Kind? {
        switch name {
        case "Introduction": .intro
        case "Credits": .credits
        case "Recap": .recap
        case "Preview": .preview
        case "Commercial": .advert
        default: nil
        }
    }

    /// How a request went: its body, a 404 for an endpoint the plugin doesn't have, or any other failure.
    private enum Answer {
        case data(Data)
        case missing
        case failed
    }

    private static func answer(at path: String, client: JellyfinClient) async -> Answer {
        // The plugin's endpoints aren't in the SDK, so this is one of the SDK's requests sent to another path.
        var request = Paths.getCurrentUser
        request.url = URL(string: path)
        request.query = nil
        do {
            return .data(try await client.data(for: request).value)
        } catch {
            logger.debug("No answer from Intro Skipper: \(error.localizedDescription, privacy: .private)")
            return HTTPStatus.of(error) == 404 ? .missing : .failed
        }
    }

    /// One segment as the plugin writes it.
    struct Entry: Decodable {
        var start: Double?
        var end: Double?
        var introStart: Double?
        var introEnd: Double?
        var valid: Bool?

        enum CodingKeys: String, CodingKey {
            case start = "Start"
            case end = "End"
            case introStart = "IntroStart"
            case introEnd = "IntroEnd"
            case valid = "Valid"
        }

        /// The segment of `kind` it describes, or nil when the plugin marks it not valid or it has no length.
        func segment(_ kind: PlaybackSegment.Kind) -> PlaybackSegment? {
            guard valid != false, let start = start ?? introStart, let end = end ?? introEnd,
                start.isFinite, end.isFinite, start >= 0, end > start
            else { return nil }
            return PlaybackSegment(kind: kind, start: .seconds(start), end: .seconds(end))
        }
    }

    /// An entry that reads as nil rather than failing the whole answer when it's malformed.
    struct LossyEntry: Decodable {
        let value: Entry?

        init(from decoder: any Decoder) throws {
            value = try? Entry(from: decoder)
        }
    }
}
