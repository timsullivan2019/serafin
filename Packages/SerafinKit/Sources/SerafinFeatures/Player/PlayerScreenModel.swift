import Observation
import SerafinDesign

/// The player screen's own state: whether the controls show, the double-tap skip indicator, and the Up Next
/// countdown.
@Observable @MainActor final class PlayerScreenModel {
    /// How long the controls stay up after the last touch while playing.
    static let hideDelay = Duration.seconds(3)
    /// How long Up Next counts down before the next episode plays.
    static let countdownSeconds = 10

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
    /// The seconds before the next episode plays, while Up Next counts down.
    private(set) var countdown: Int?

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
}
