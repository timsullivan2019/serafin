import Foundation

/// Keeps where a downloaded copy is playing on the device, so it resumes there with no server to ask.
///
/// It hears what ``ProgressReporter`` hears, and keeps the position when playback pauses, resumes or stops, and after
/// it has moved ``distance`` since the last keep, rather than at every report, since each keep saves the list of
/// downloads. Keeps happen one at a time, in order, so an older position never lands after a newer one.
actor LocalProgressReporter: PlaybackReporter {
    /// How far playback moves, by playing or seeking, before the position is kept again.
    static let distance = Duration.seconds(30)

    private let keep: @Sendable (Duration) async -> Void
    private var hasStarted = false
    /// The position last kept, or where playback started.
    private var kept = Duration.zero
    private var wasPaused = false
    /// The last keep, done or waiting for the one before it.
    private var lastKeep: Task<Void, Never>?

    /// Creates a reporter that keeps positions with `keep`.
    init(keep: @escaping @Sendable (Duration) async -> Void) {
        self.keep = keep
    }

    func start(at position: Duration, isPaused: Bool) {
        hasStarted = true
        kept = position
        wasPaused = isPaused
    }

    func progress(at position: Duration, isPaused: Bool) async {
        guard hasStarted else { return }
        let moved = position > kept ? position - kept : kept - position
        guard isPaused != wasPaused || moved >= Self.distance else { return }
        wasPaused = isPaused
        await keepPosition(position)
    }

    func stop(at position: Duration) async {
        guard hasStarted else { return }
        hasStarted = false
        await keepPosition(position)
    }

    /// A copy plays one file with the tracks it carries, so a change of tracks changes nothing kept.
    func update(_ plan: PlaybackPlan) {}

    /// A copy plays one file, so it's never renegotiated, and this changes nothing kept.
    func replace(with plan: PlaybackPlan, at position: Duration, isPaused: Bool) {}

    /// Keeps `position` once the keep before it is done, and returns when this one is.
    private func keepPosition(_ position: Duration) async {
        kept = position
        let previous = lastKeep
        let keeping = Task { [keep] in
            await previous?.value
            await keep(position)
        }
        lastKeep = keeping
        await keeping.value
    }
}
