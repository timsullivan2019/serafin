import AVFoundation
import os

/// The app's audio session while something plays: movie playback that keeps going with the screen locked or in
/// Picture in Picture, and lets other apps' audio resume afterwards.
///
/// Starting and ending the session can block while iOS reroutes audio, for example to AirPlay or Bluetooth, so both
/// run on a queue of their own instead of the main thread. The asynchronous activation API needs iOS 27.
enum PlaybackAudioSession {
    private static let logger = Logger(serafinCategory: "audio-session")
    private static let queue = DispatchQueue(label: "app.getserafin.serafin.audio-session", qos: .userInitiated)

    /// Claims audio for movie playback, returning once the session is active or has failed to start.
    static func activate() async {
        #if canImport(UIKit)
            await onSessionQueue {
                let clock = ContinuousClock()
                let started = clock.now
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .moviePlayback)
                    let categorized = clock.now
                    try session.setActive(true)
                    // Only the kinds of output, such as Speaker or AirPlay, never their names.
                    let outputs = session.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ", ")
                    logger.debug(
                        "Audio session started in \((clock.now - started).loggedSeconds, privacy: .public), the category taking \((categorized - started).loggedSeconds, privacy: .public), playing to \(outputs, privacy: .public)"
                    )
                } catch {
                    logger.error("Could not start the audio session: \(error.localizedDescription, privacy: .public)")
                }
            }
        #endif
    }

    /// Gives audio back to other apps, returning once the session has ended or has failed to.
    static func deactivate() async {
        #if canImport(UIKit)
            await onSessionQueue {
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    logger.error("Could not end the audio session: \(error.localizedDescription, privacy: .public)")
                }
            }
        #endif
    }

    /// Runs `work` on the session's own serial queue and waits for its result, so the caller's thread never blocks.
    /// The queue keeps starts and ends in the order they were asked for.
    static func onSessionQueue<Result: Sendable>(_ work: @escaping @Sendable () -> Result) async -> Result {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: work())
            }
        }
    }
}
