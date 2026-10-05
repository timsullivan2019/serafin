import JellyfinAPI
import SerafinCore

/// A stretch of an item that the server has marked, such as its intro, which the player offers to skip.
public struct PlaybackSegment: Hashable, Sendable {
    /// What the stretch is.
    public enum Kind: Hashable, Sendable {
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
    }

    /// The least time a segment has left for the player to offer skipping it, so the offer never flashes past.
    public static let shortestOffer = Duration.seconds(2)

    /// What the stretch is.
    public let kind: Kind
    /// Where it starts.
    public let start: Duration
    /// Where it ends, which is where skipping it lands.
    public let end: Duration

    /// Creates a segment.
    public init(kind: Kind, start: Duration, end: Duration) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    /// The segment to offer skipping at `position`: the one playing, while it has at least ``shortestOffer`` left.
    public static func skippable(at position: Duration, in segments: [PlaybackSegment]) -> PlaybackSegment? {
        segments.first { $0.start <= position && position < $0.end - shortestOffer }
    }
}

extension PlaybackSegment {
    /// A segment from the server, or nil for a kind Serafin doesn't skip or a stretch without a length.
    init?(_ segment: MediaSegmentDto) {
        let kind: Kind
        switch segment.type {
        case .intro: kind = .intro
        case .recap: kind = .recap
        case .outro: kind = .credits
        case .preview: kind = .preview
        case .commercial: kind = .advert
        case .unknown, nil: return nil
        }
        guard let startTicks = segment.startTicks, let endTicks = segment.endTicks, endTicks > startTicks else {
            return nil
        }
        self.init(kind: kind, start: Ticks.duration(startTicks), end: Ticks.duration(endTicks))
    }
}

/// Finds the segments a server has marked in an item, which plugins such as Intro Skipper add on Jellyfin 10.10 and
/// later.
public struct MediaSegments: Sendable {
    private let client: JellyfinClient

    /// Creates the finder.
    ///
    /// - Parameter client: The signed-in account's client.
    public init(client: JellyfinClient) {
        self.client = client
    }

    /// The item's skippable segments, in order. A server without segments, or too old to have them, has none.
    public func of(_ itemID: String) async throws -> [PlaybackSegment] {
        let request = Paths.getItemSegments(
            itemID: itemID, includeSegmentTypes: [.intro, .recap, .outro, .preview, .commercial])
        let segments: [MediaSegmentDto]
        do {
            segments = try await client.send(request).value.items ?? []
        } catch {
            throw SerafinError.translating(error, statuses: [401: .notSignedIn, 404: .notFound])
        }
        return segments.compactMap(PlaybackSegment.init).sorted { $0.start < $1.start }
    }
}
