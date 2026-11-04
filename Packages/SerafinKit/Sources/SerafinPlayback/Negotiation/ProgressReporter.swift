import Foundation
import JellyfinAPI
import SerafinCore
import os

/// Hears where playback is, so the viewer's place is kept: by the server for a stream, through ``ProgressReporter``,
/// and on the device for a downloaded copy, through ``LocalProgressReporter``.
protocol PlaybackReporter: Actor {
    /// Playback started at `position`.
    func start(at position: Duration, isPaused: Bool) async
    /// Playback is at `position`, as every few seconds and after a pause, resume or seek.
    func progress(at position: Duration, isPaused: Bool) async
    /// Playback stopped at `position`, for any reason.
    func stop(at position: Duration) async
    /// The player made a change without a new stream, such as other subtitles.
    func update(_ plan: PlaybackPlan) async
    /// The player renegotiated, and plays `plan` from `position`.
    func replace(with plan: PlaybackPlan, at position: Duration, isPaused: Bool) async
}

extension ProgressReporter: PlaybackReporter {}

/// Tells the server where playback is, so Continue Watching, played marks and the server's dashboard stay current.
///
/// The player calls ``start(at:isPaused:)`` once, ``progress(at:isPaused:)`` every ``interval`` and whenever it
/// pauses, resumes or seeks, and ``stop(at:)`` when playback ends for any reason. A report that fails is logged
/// and dropped: it never interrupts playback.
///
/// Reports go to the server one at a time, in the order they were made, so a progress report still on its way can't
/// land after the stop. That matters because Jellyfin's stop clears the device's Now Playing and transcoding details
/// whichever item it names.
public actor ProgressReporter {
    /// How often the player reports progress while playing.
    public static let interval: Duration = .seconds(10)

    private let client: JellyfinClient
    private var plan: PlaybackPlan
    private var hasStarted = false
    /// The last report made, sent or waiting for the one before it.
    private var lastReport: Task<Void, Never>?
    /// How many times ``stop(at:)`` has been called, so a switch to a new plan that a stop overtakes doesn't start
    /// the reports again.
    private(set) var stopCount = 0

    /// Creates a reporter for one playback.
    public init(client: JellyfinClient, plan: PlaybackPlan) {
        self.client = client
        self.plan = plan
    }

    /// Reports that playback started at `position`.
    public func start(at position: Duration, isPaused: Bool) async {
        hasStarted = true
        let state = state(at: position, isPaused: isPaused)
        await send("start") { [client] in try await client.send(Paths.reportPlaybackStart(state)) }
    }

    /// Reports where playback is.
    public func progress(at position: Duration, isPaused: Bool) async {
        guard hasStarted else { return }
        let state = state(at: position, isPaused: isPaused)
        await send("progress") { [client] in try await client.send(Paths.reportPlaybackProgress(state)) }
    }

    /// Reports that playback stopped at `position`. Later reports are ignored until the next ``start(at:isPaused:)``.
    ///
    /// Returns once the server has answered or the report has failed, so whatever the caller reports next, such as
    /// another video starting, reaches the server after it. Called again while the stop is on its way, it waits for
    /// that report rather than sending another.
    public func stop(at position: Duration) async {
        stopCount += 1
        await reportStop(at: position)
    }

    /// Takes in a change the player made without a new stream, such as other subtitles, for the next report.
    public func update(_ plan: PlaybackPlan) {
        self.plan = plan
    }

    /// Switches to a new plan after the player renegotiated, such as for another audio track. The server sees the
    /// old playback stop and the new one start, unless playback stops for good while the old one's stop is on its
    /// way.
    public func replace(with plan: PlaybackPlan, at position: Duration, isPaused: Bool) async {
        let stops = stopCount
        await reportStop(at: position)
        guard stops == stopCount else { return }
        self.plan = plan
        await start(at: position, isPaused: isPaused)
    }

    /// Reports that playback stopped at `position`, or waits for a stop already on its way.
    private func reportStop(at position: Duration) async {
        guard hasStarted else {
            await lastReport?.value
            return
        }
        hasStarted = false
        let info = PlaybackStopInfo(
            itemID: plan.itemID,
            mediaSourceID: plan.mediaSourceID,
            playSessionID: plan.playSessionID,
            positionTicks: Ticks.from(position)
        )
        await send("stop") { [client] in try await client.send(Paths.reportPlaybackStopped(info)) }
    }

    private func state(at position: Duration, isPaused: Bool) -> PlaybackStateInfo {
        PlaybackStateInfo(
            audioStreamIndex: plan.audioStreamIndex,
            canSeek: true,
            isMuted: false,
            isPaused: isPaused,
            itemID: plan.itemID,
            mediaSourceID: plan.mediaSourceID,
            playMethod: plan.method.playMethod,
            playSessionID: plan.playSessionID,
            positionTicks: Ticks.from(position),
            subtitleStreamIndex: plan.subtitleStreamIndex
        )
    }

    /// Sends a report once the one before it has been answered or has failed, and returns when this one has.
    private func send(_ report: String, _ request: @escaping @Sendable () async throws -> Void) async {
        let previous = lastReport
        let sending = Task {
            await previous?.value
            do {
                try await request()
            } catch {
                Logger.playback.error(
                    "Could not report playback \(report, privacy: .public): \(error.localizedDescription, privacy: .private)"
                )
            }
        }
        lastReport = sending
        await sending.value
    }
}
