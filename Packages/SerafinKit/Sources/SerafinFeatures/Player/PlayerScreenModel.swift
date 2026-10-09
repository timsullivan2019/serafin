import Foundation
import Observation
import SerafinCore
import SerafinDesign

/// The player screen's own state: whether the controls show, the double-tap skip indicator, what's offered for the
/// stretch the server marked at the playback position, and the next episode's card with its countdown.
@Observable @MainActor final class PlayerScreenModel {
    /// How long the controls stay up after the last touch while playing.
    static let hideDelay = Duration.seconds(3)
    /// How long the next episode's card counts down before it plays, and how long before an episode's end the card
    /// comes when the server marked no credits.
    static let countdownLength = Duration.seconds(10)
    /// How long the notice that a stretch was skipped by itself shows.
    static let noticeDuration = Duration.seconds(2)

    /// How long the countdown runs, which tests shorten.
    private let countdownLength: Duration

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
    /// The episode playing that the next one is offered after, while its card shows.
    private(set) var nextEpisodeOffer: String?
    /// The time left before the next episode plays by itself, while its card counts down.
    private(set) var countdown: NextEpisodeCountdown?
    /// The whole seconds left on the countdown, for VoiceOver, while it counts down.
    private(set) var secondsLeft: Int?
    /// The episode whose next episode's card was put away, which offers it again only once playback has gone back
    /// before the card's place and reached it again.
    private var cancelledNextEpisode: String?
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

    /// Creates the screen's state.
    ///
    /// - Parameter countdownLength: How long the next episode's card counts down, which tests shorten.
    init(countdownLength: Duration = PlayerScreenModel.countdownLength) {
        self.countdownLength = countdownLength
    }

    // MARK: - Next episode

    /// Where the next episode is offered in an episode: at the start of its credits, or ``countdownLength`` before
    /// its end when the server marked none, so a countdown that runs through ends as the episode does. Nil when
    /// neither is known yet.
    static func nextEpisodePlace(
        in segments: [PlaybackSegment],
        duration: Duration,
        countdownLength: Duration = PlayerScreenModel.countdownLength
    ) -> Duration? {
        if let credits = segments.last(where: { $0.kind == .credits }) {
            return credits.start
        }
        guard duration > countdownLength else { return nil }
        return duration - countdownLength
    }

    /// Works out whether the next episode's card shows at `position`: from its place in the episode, as
    /// ``nextEpisodePlace(in:duration:countdownLength:)`` finds it, and once the episode has ended. Going back before
    /// its place takes the card away, as does putting it away, until playback reaches it again.
    ///
    /// - Parameters:
    ///   - position: Where playback is.
    ///   - duration: How long the episode is.
    ///   - segments: The segments marked in the episode.
    ///   - itemID: The episode playing.
    ///   - hasNextEpisode: Whether an episode follows it.
    ///   - hasEnded: Whether it has played to its end.
    ///   - countsDown: Whether the next episode plays by itself, as the account's setting says, after a countdown.
    ///   - countdownRuns: Whether a new countdown starts running, as while playback runs, or holds.
    ///   - now: The time, which tests set.
    func updateNextEpisode(
        at position: Duration,
        duration: Duration,
        segments: [PlaybackSegment],
        itemID: String?,
        hasNextEpisode: Bool,
        hasEnded: Bool,
        countsDown: Bool,
        countdownRuns: Bool,
        now: Date = .now
    ) {
        guard let itemID, hasNextEpisode else {
            cancelledNextEpisode = nil
            withdrawNextEpisode()
            return
        }
        let place = Self.nextEpisodePlace(in: segments, duration: duration, countdownLength: countdownLength)
        let isPast = hasEnded || place.map { position >= $0 } ?? false
        if cancelledNextEpisode != nil, cancelledNextEpisode != itemID || !isPast {
            cancelledNextEpisode = nil
        }
        guard isPast, cancelledNextEpisode == nil else {
            withdrawNextEpisode()
            return
        }
        guard nextEpisodeOffer != itemID else { return }
        nextEpisodeOffer = itemID
        countdown =
            countsDown ? NextEpisodeCountdown(length: countdownLength, runningFrom: countdownRuns ? now : nil) : nil
        secondsLeft = countdown?.secondsLeft(at: now)
    }

    /// Runs the countdown while playback runs, and holds it while playback is paused or a finger is on the scrubber.
    func setCountdownRunning(_ runs: Bool, now: Date = .now) {
        guard var countdown, countdown.isRunning != runs else { return }
        if runs {
            countdown.resume(at: now)
        } else {
            countdown.pause(at: now)
        }
        self.countdown = countdown
        secondsLeft = countdown.secondsLeft(at: now)
    }

    /// Keeps ``secondsLeft`` up to date while the countdown runs, and calls `finish` when it reaches zero. Returns once
    /// the countdown holds or goes, or when the task is cancelled, without finishing.
    func tickCountdown(finish: () -> Void) async {
        while !Task.isCancelled, let countdown, countdown.isRunning {
            let now = Date.now
            secondsLeft = countdown.secondsLeft(at: now)
            guard countdown.left(at: now) > .zero else {
                finish()
                return
            }
            try? await Task.sleep(for: countdown.untilNextSecond(at: now))
        }
    }

    /// Takes the card away as the next episode starts, in the same update that shows its title.
    func handOff() {
        withdrawNextEpisode()
    }

    /// Puts the next episode's card away until playback goes back before its place and reaches it again.
    func cancelNextEpisode() {
        cancelledNextEpisode = nextEpisodeOffer
        withdrawNextEpisode()
    }

    /// Whether the card was put away for the episode `itemID`, which then closes the player as it ends.
    func hasCancelledNextEpisode(after itemID: String?) -> Bool {
        itemID != nil && cancelledNextEpisode == itemID
    }

    private func withdrawNextEpisode() {
        if nextEpisodeOffer != nil {
            nextEpisodeOffer = nil
        }
        if countdown != nil {
            countdown = nil
        }
        if secondsLeft != nil {
            secondsLeft = nil
        }
    }

    // MARK: - Segments

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

    /// Puts away what's offered for `segment` until playback leaves it, as after skipping it.
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
