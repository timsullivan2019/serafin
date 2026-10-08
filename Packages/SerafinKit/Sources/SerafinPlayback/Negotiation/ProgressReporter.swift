import Foundation
import JellyfinAPI
import SerafinCore
import os

/// Tells the server where playback is, so Continue Watching, played marks and the server's dashboard stay current.
///
/// The player calls ``start(at:isPaused:)`` once, ``progress(at:isPaused:)`` every ``interval`` and whenever it
/// pauses, resumes or seeks, and ``stop(at:)`` when playback ends for any reason. A report that fails is logged
/// and dropped: it never interrupts playback.
public actor ProgressReporter {
    /// How often the player reports progress while playing.
    public static let interval: Duration = .seconds(10)

    private let client: JellyfinClient
    private var plan: PlaybackPlan
    private var hasStarted = false

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
    public func stop(at position: Duration) async {
        guard hasStarted else { return }
        hasStarted = false
        let info = PlaybackStopInfo(
            itemID: plan.itemID,
            mediaSourceID: plan.mediaSourceID,
            playSessionID: plan.playSessionID,
            positionTicks: Ticks.from(position)
        )
        await send("stop") { [client] in try await client.send(Paths.reportPlaybackStopped(info)) }
    }

    /// Takes in a change the player made without a new stream, such as other subtitles, for the next report.
    public func update(_ plan: PlaybackPlan) {
        self.plan = plan
    }

    /// Switches to a new plan after the player renegotiated, such as for another audio track. The server sees the
    /// old playback stop and the new one start.
    public func replace(with plan: PlaybackPlan, at position: Duration, isPaused: Bool) async {
        await stop(at: position)
        self.plan = plan
        await start(at: position, isPaused: isPaused)
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

    private func send(_ report: String, _ request: () async throws -> Void) async {
        do {
            try await request()
        } catch {
            Logger.playback.error(
                "Could not report playback \(report, privacy: .public): \(error.localizedDescription, privacy: .private)"
            )
        }
    }
}
