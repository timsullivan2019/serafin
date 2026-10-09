import Foundation
import JellyfinAPI
import os

/// A stretch of an item that the server has marked, such as its intro, which the player offers to skip.
public struct PlaybackSegment: Hashable, Sendable {
    /// What the stretch is.
    public enum Kind: Hashable, Sendable, CaseIterable {
        /// The opening titles.
        case intro
        /// A recap of earlier episodes.
        case recap
        /// The closing credits.
        case credits
        /// A preview of what comes next.
        case preview
        /// An advert, as in a recording from television.
        case advert
        /// A stretch the server marked without saying what it is.
        case unknown
    }

    /// What the stretch is.
    public let kind: Kind
    /// Where it starts.
    public let start: Duration
    /// Where it ends.
    public let end: Duration

    /// Creates a segment.
    public init(kind: Kind, start: Duration, end: Duration) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    /// How long the stretch runs.
    public var length: Duration { end - start }

    /// Whether `position` is within the stretch: from its start up to, but not at, its end.
    public func contains(_ position: Duration) -> Bool {
        start <= position && position < end
    }

    /// The segment playing at `position` among `segments`, which ``normalized(_:)`` has put in order without
    /// overlaps.
    public static func playing(at position: Duration, in segments: [PlaybackSegment]) -> PlaybackSegment? {
        segments.first { $0.contains(position) }
    }

    /// `segments` in order, without any that end before they start or have no length, and without overlaps: a
    /// stretch within an earlier one is dropped, and one that starts inside an earlier one starts where that ends.
    public static func normalized(_ segments: [PlaybackSegment]) -> [PlaybackSegment] {
        let sorted = segments.filter { $0.start >= .zero && $0.end > $0.start }
            .sorted { ($0.start, $0.end) < ($1.start, $1.end) }
        var result: [PlaybackSegment] = []
        for segment in sorted {
            guard let previous = result.last, segment.start < previous.end else {
                result.append(segment)
                continue
            }
            if segment.end > previous.end {
                result.append(PlaybackSegment(kind: segment.kind, start: previous.end, end: segment.end))
            }
        }
        return result
    }
}

extension PlaybackSegment {
    /// A segment from the server's media segments, or nil for one without both ends.
    init?(_ segment: MediaSegmentDto) {
        guard let startTicks = segment.startTicks, let endTicks = segment.endTicks else { return nil }
        let kind: Kind =
            switch segment.type {
            case .intro: .intro
            case .recap: .recap
            case .outro: .credits
            case .preview: .preview
            case .commercial: .advert
            case .unknown, nil: .unknown
            }
        self.init(kind: kind, start: .ticks(startTicks), end: .ticks(endTicks))
    }
}

extension Duration {
    /// A time in Jellyfin's ticks of 100 nanoseconds.
    fileprivate static func ticks(_ ticks: Int) -> Duration {
        .nanoseconds(Int64(ticks) * 100)
    }
}

/// The stretches servers mark in items, such as intros and credits, which the player offers to skip.
///
/// Jellyfin 10.10 and later list them at `/MediaSegments/{itemId}`, where plugins such as Intro Skipper put them, and
/// leave out what an administrator has hidden; their answer stands, even when it's none. An older server has no such
/// endpoint, so for an episode there the repository asks Intro Skipper's own endpoints instead. Each item is asked
/// about once and remembered for as long as the repository lasts. Nothing here fails: a server without segments, or
/// one that can't say, has none, and the player then shows nothing.
public actor SegmentRepository {
    private static let logger = Logger(serafinCategory: "segments")

    private let client: JellyfinClient
    /// What each item asked about has, or the request on its way.
    private var segments: [String: Task<[PlaybackSegment], Never>] = [:]

    /// Creates the repository for the signed-in account's client.
    public init(client: JellyfinClient) {
        self.client = client
    }

    /// The segments marked in the item `itemID`, in order and without overlaps, or none.
    ///
    /// - Parameters:
    ///   - itemID: The movie or episode.
    ///   - isEpisode: Whether it's an episode, which Intro Skipper's own endpoints can answer for.
    public func segments(of itemID: String, isEpisode: Bool) async -> [PlaybackSegment] {
        if let known = segments[itemID] {
            return await known.value
        }
        let client = client
        let request = Task {
            await Self.fetch(itemID, isEpisode: isEpisode, client: client)
        }
        segments[itemID] = request
        return await request.value
    }

    /// Asks the server's media segments, then, on a server without them, Intro Skipper for an episode.
    private static func fetch(_ itemID: String, isEpisode: Bool, client: JellyfinClient) async -> [PlaybackSegment] {
        guard ItemID.isPlain(itemID) else { return [] }
        guard let marked = await mediaSegments(of: itemID, client: client) else {
            return isEpisode ? await IntroSkipper.segments(of: itemID, client: client) : []
        }
        return marked
    }

    /// The item's segments at `/MediaSegments/{itemId}`: none when the server lists none or can't answer, and nil
    /// when it has no such endpoint, as before Jellyfin 10.10.
    private static func mediaSegments(of itemID: String, client: JellyfinClient) async -> [PlaybackSegment]? {
        let request = Paths.getItemSegments(
            itemID: itemID, includeSegmentTypes: [.intro, .recap, .outro, .preview, .commercial, .unknown])
        do {
            let items = try await client.send(request).value.items ?? []
            return PlaybackSegment.normalized(items.compactMap(PlaybackSegment.init))
        } catch {
            // Nothing to show either way, so nothing to report.
            logger.debug("No media segments: \(error.localizedDescription, privacy: .private)")
            return HTTPStatus.of(error) == 404 ? nil : []
        }
    }
}
