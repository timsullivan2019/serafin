import JellyfinAPI

/// One of an item's versions, such as its 4K file or its 1080p one, as the server offers it to this device.
public struct VersionOffer: Sendable, Equatable {
    /// How the server would send a version to this device, from least changed to most.
    public enum Delivery: Int, Comparable, Sendable {
        /// The original file, played as it is.
        case original
        /// The original video and audio, repackaged into HLS.
        case repackaged
        /// The original video, with the audio converted.
        case audioConverted
        /// The video converted, and perhaps the audio too.
        case videoConverted

        /// Whether the picture reaches the device as it is in the file.
        var keepsVideo: Bool {
            self != .videoConverted
        }

        /// The same delivery as a plan's method, which doesn't tell converting the audio from converting the video.
        var method: PlaybackPlan.Method {
            switch self {
            case .original: .directPlay
            case .repackaged: .directStream
            case .audioConverted, .videoConverted: .transcode
            }
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// The version, with its streams.
    public let source: MediaSourceInfo
    /// How the server would send it, under the quality cap it was asked about, or nil when it can't.
    public let delivery: Delivery?

    /// Creates an offer.
    public init(source: MediaSourceInfo, delivery: Delivery?) {
        self.source = source
        self.delivery = delivery
    }

    /// The version's ID.
    public var id: String? {
        source.id
    }
}

/// Which of an item's versions plays when the viewer hasn't picked one, going by how the server would send each to this
/// device under the quality cap.
///
/// Versions whose picture the device shows as it is in the file come first: played directly, repackaged, or with only
/// the audio converted. Among them the sharpest picture plays, since nothing is lost on the way, then the one the server
/// changes least, then the one with the most audio channels. When every version's picture has to be converted, the
/// smallest plays instead: the least work for the server, and the closest to the quality cap, which is usually why it
/// converts. 3D versions come after flat ones, versions the server can't send at all come last, and the server's own
/// order settles anything left.
///
/// The server's own order isn't used as the choice, because it differs between releases: Jellyfin 10.11 lists versions
/// that play directly first, and 12.4 lists the item's own file first whatever the device can play.
public enum VersionRanking {
    /// The version to play among `offers`, which are in the server's order, or nil when there are none.
    public static func preferred(among offers: [VersionOffer]) -> VersionOffer? {
        offers.enumerated()
            .min { key(of: $0.element, at: $0.offset) < key(of: $1.element, at: $1.offset) }?
            .element
    }

    /// What orders `offer`, the `position`th the server listed: the smallest key plays.
    private static func key(of offer: VersionOffer, at position: Int) -> (Int, Int, Int, Int, Int, Int) {
        let pixels = pixelCount(of: offer.source)
        let tier: Int
        let picture: Int
        switch offer.delivery {
        case let delivery? where delivery.keepsVideo:
            tier = 0
            picture = -pixels
        case .some:
            tier = 1
            picture = pixels
        case nil:
            tier = 2
            picture = 0
        }
        let flat = offer.source.video3DFormat == nil ? 0 : 1
        let change = offer.delivery?.rawValue ?? Int.max
        // The server's numbers are untrusted, so a negative count is taken as none rather than negated.
        let channels = -max(defaultAudio(of: offer.source)?.channels ?? 0, 0)
        return (tier, flat, picture, change, channels, position)
    }

    /// How many pixels a version's picture has, or 0 when the server doesn't say.
    ///
    /// Each side is held to ``largestSide``, larger than any video's, so a server's out-of-range size can't overflow.
    static func pixelCount(of source: MediaSourceInfo) -> Int {
        guard let video = source.mediaStreams?.first(where: { $0.type == .video }),
            let width = video.width, let height = video.height, width > 0, height > 0
        else { return 0 }
        return min(width, largestSide) * min(height, largestSide)
    }

    /// The longest side ``pixelCount(of:)`` counts, well beyond any video's.
    static let largestSide = 65_536

    /// The audio a version plays unless another is picked: the server's default for it, or its first.
    static func defaultAudio(of source: MediaSourceInfo) -> MediaStream? {
        let audio = (source.mediaStreams ?? []).filter { $0.type == .audio }
        return audio.first { $0.index == source.defaultAudioStreamIndex } ?? audio.first
    }
}
