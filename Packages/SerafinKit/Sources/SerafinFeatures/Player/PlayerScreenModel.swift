import Foundation
import Observation
import SerafinCore
import SerafinDesign

/// The player screen's own state: whether the controls show, the double-tap skip indicator, what's offered for the
/// stretch the server marked at the playback position, and the next episode's countdown.
@Observable @MainActor final class PlayerScreenModel {
    /// How long the controls stay up after the last touch while playing.
    static let hideDelay = Duration.seconds(3)
    /// How long the next episode's card counts down before it plays.
    static let countdownSeconds = 10
    /// How long the notice that a stretch was skipped by itself shows.
    static let noticeDuration = Duration.seconds(2)

    /// Whether the glass controls are showing.
    private(set) var controlsVisible = true
    /// Goes up with every touch, restarting the wait before the controls hide.
    private(set) var interaction = 0
    /// Whether a finger is dragging the scrubber.
    private(set) var isScrubbing = false
    /// The side a double tap last skipped on, shown for a moment.
    private(set) var skip: SkipIndicator.Direction?
    /// Goes up with every double tap, restarting the indicator's moment on screen.
    private(set) var skipCount = 0
    /// The seconds before the next episode plays, while its card counts down.
    private(set) var countdown: Int?
    /// What's offered for the segment at the playback position.
    private(set) var segmentAction = SegmentAction.none
    /// The notice that a segment was skipped by itself, while it shows.
    private(set) var skippedNotice: SkipSegmentButton.Kind?
    /// Goes up with every notice, restarting its moment on screen.
    private(set) var noticeCount = 0
    /// The segment whose pill or episode was used or put away, which offers nothing more until playback leaves it.
    private var dismissedSegment: PlaybackSegment?
    /// The segments skipped by themselves in the video playing.
    private var skippedSegments: Set<PlaybackSegment> = []
    /// The video the segment state is for.
    private var segmentItemID: String?

    /// Shows the controls and restarts the wait before they hide.
    func touched() {
        controlsVisible = true
        interaction += 1
    }

    /// Hides the controls when they show, and shows them when they don't.
    func toggleControls() {
        controlsVisible.toggle()
        interaction += 1
    }

    /// Notes a drag on the scrubber starting or ending. The controls stay up meanwhile.
    func scrubbingChanged(_ isScrubbing: Bool) {
        self.isScrubbing = isScrubbing
        touched()
    }

    /// Waits, then hides the controls, unless playback has stopped running, a finger is on the scrubber, or the wait
    /// was cancelled by another touch.
    func hideControlsLater(whilePlaying isPlaying: Bool, after delay: Duration = hideDelay) async {
        guard isPlaying else { return }
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled, !isScrubbing else { return }
        controlsVisible = false
    }

    /// Notes a double tap that skipped, for the indicator on that side.
    func skipped(_ direction: SkipIndicator.Direction) {
        skip = direction
        skipCount += 1
    }

    /// Takes the skip indicator away after a moment, unless another double tap cancelled the wait.
    func clearSkipLater(after delay: Duration = .milliseconds(600)) async {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        skip = nil
    }

    /// Counts down from ``countdownSeconds`` a second at a time, then calls `finish`. Cancelling the task stops the
    /// countdown without finishing.
    func runCountdown(tick: Duration = .seconds(1), finish: () -> Void) async {
        countdown = Self.countdownSeconds
        while let left = countdown, left > 0 {
            try? await Task.sleep(for: tick)
            guard !Task.isCancelled else {
                countdown = nil
                return
            }
            countdown = left - 1
        }
        countdown = nil
        finish()
    }

    /// Stops the countdown.
    func cancelCountdown() {
        countdown = nil
    }

    /// Works out what to offer for the segment at `position`, and returns a segment to skip by itself now, if any,
    /// showing the notice that says so.
    ///
    /// - Parameters:
    ///   - position: Where playback is.
    ///   - segments: The segments marked in the video playing, in order and without overlaps.
    ///   - itemID: The video playing, so what was skipped or put away in another one doesn't count.
    ///   - automatic: The kinds Settings say to skip by themselves.
    ///   - hasNextEpisode: Whether an episode follows the one playing.
    func updateSegment(
        at position: Duration,
        in segments: [PlaybackSegment],
        itemID: String?,
        automatic: Set<PlaybackSegment.Kind>,
        hasNextEpisode: Bool
    ) -> PlaybackSegment? {
        if itemID != segmentItemID {
            segmentItemID = itemID
            dismissedSegment = nil
            skippedSegments = []
        }
        if let dismissedSegment, !dismissedSegment.contains(position) {
            self.dismissedSegment = nil
        }
        let action = SegmentAction.at(
            position, in: segments, dismissed: dismissedSegment, skippedBefore: skippedSegments,
            automatic: automatic, hasNextEpisode: hasNextEpisode)
        guard case .skip(let segment) = action else {
            if segmentAction != action {
                segmentAction = action
            }
            return nil
        }
        skippedSegments.insert(segment)
        dismissedSegment = segment
        segmentAction = .none
        skippedNotice = SkipSegmentButton.Kind(segment.kind)
        noticeCount += 1
        return segment
    }

    /// Puts away what's offered for `segment` until playback leaves it, as after skipping it or putting away the
    /// next episode.
    func dismiss(_ segment: PlaybackSegment) {
        dismissedSegment = segment
        segmentAction = .none
    }

    /// Takes the skipped notice away after ``noticeDuration``, unless another notice cancelled the wait.
    func clearNoticeLater(after delay: Duration = noticeDuration) async {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled else { return }
        skippedNotice = nil
    }
}
