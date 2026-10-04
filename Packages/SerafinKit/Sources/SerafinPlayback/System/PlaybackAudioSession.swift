import AVFoundation
import os

/// The app's audio session while something plays: movie playback that keeps going with the screen locked or in
/// Picture in Picture, and lets other apps' audio resume afterwards.
enum PlaybackAudioSession {
    private static let logger = Logger(serafinCategory: "audio-session")

    /// Claims audio for movie playback.
    static func activate() {
        #if canImport(UIKit)
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .moviePlayback)
                try session.setActive(true)
            } catch {
                logger.error("Could not start the audio session: \(error.localizedDescription, privacy: .public)")
            }
        #endif
    }

    /// Gives audio back to other apps.
    static func deactivate() {
        #if canImport(UIKit)
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                logger.error("Could not end the audio session: \(error.localizedDescription, privacy: .public)")
            }
        #endif
    }
}
