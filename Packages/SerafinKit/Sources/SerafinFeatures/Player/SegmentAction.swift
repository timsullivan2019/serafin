import Foundation
import SerafinCore
import SerafinDesign

/// What the player does about the stretch the server marked at the playback position, such as the intro.
enum SegmentAction: Equatable {
    /// Nothing that plays now has anything offered for it.
    case none
    /// Offers the pill that skips the segment.
    case offer(PlaybackSegment)
    /// Skips the segment by itself, as Settings say, with a brief notice.
    case skip(PlaybackSegment)

    /// What to do at `position` among `segments`.
    ///
    /// Credits with an episode after them offer nothing here: the next episode's card takes their place, as in the TV
    /// app. A film's or a last episode's credits offer a pill. A segment of a kind Settings say to skip by itself is
    /// skipped the first time playback reaches it, and offers the pill if playback goes back into it.
    ///
    /// - Parameters:
    ///   - position: Where playback is.
    ///   - segments: The segments marked in what's playing, in order and without overlaps.
    ///   - dismissed: A segment whose pill or episode was used or put away, which offers nothing more until playback
    ///     leaves it.
    ///   - skippedBefore: Segments already skipped by themselves.
    ///   - automatic: The kinds Settings say to skip by themselves.
    ///   - hasNextEpisode: Whether an episode follows what's playing.
    static func at(
        _ position: Duration,
        in segments: [PlaybackSegment],
        dismissed: PlaybackSegment?,
        skippedBefore: Set<PlaybackSegment>,
        automatic: Set<PlaybackSegment.Kind>,
        hasNextEpisode: Bool
    ) -> SegmentAction {
        guard let segment = PlaybackSegment.playing(at: position, in: segments), segment != dismissed else {
            return .none
        }
        if segment.kind == .credits {
            return hasNextEpisode ? .none : .offer(segment)
        }
        if automatic.contains(segment.kind), !skippedBefore.contains(segment) {
            return .skip(segment)
        }
        return .offer(segment)
    }
}

/// Which kinds of segments skip by themselves, from Settings › Playback › Skip Segments. All are off at first, so the
/// player offers a pill instead. Credits are left out: with an episode after them the next episode's card offers it,
/// playing it by itself when the account's Play Next Episode Automatically setting is on.
enum AutomaticSkips {
    /// The kinds that can skip by themselves, in the order Settings lists them.
    static let kinds: [PlaybackSegment.Kind] = [.intro, .recap, .preview, .advert]

    /// Where the switch for `kind` is saved, or nil for a kind that can't skip by itself.
    static func key(for kind: PlaybackSegment.Kind) -> String? {
        switch kind {
        case .intro: "skipsIntrosAutomatically"
        case .recap: "skipsRecapsAutomatically"
        case .preview: "skipsPreviewsAutomatically"
        case .advert: "skipsAdvertsAutomatically"
        case .credits, .unknown: nil
        }
    }

    /// The kinds Settings say to skip by themselves.
    static func kinds(in defaults: UserDefaults) -> Set<PlaybackSegment.Kind> {
        Set(kinds.filter { kind in key(for: kind).map(defaults.bool(forKey:)) ?? false })
    }
}

extension PlaybackSegment {
    /// Where skipping the segment lands: half a second before its end, so nothing after it is missed.
    var skipTarget: Duration {
        max(start, end - .milliseconds(500))
    }
}

extension SkipSegmentButton.Kind {
    /// The pill for a segment of `kind`.
    init(_ kind: PlaybackSegment.Kind) {
        switch kind {
        case .intro: self = .intro
        case .recap: self = .recap
        case .credits: self = .credits
        case .preview: self = .preview
        case .advert: self = .advert
        case .unknown: self = .unknown
        }
    }
}
