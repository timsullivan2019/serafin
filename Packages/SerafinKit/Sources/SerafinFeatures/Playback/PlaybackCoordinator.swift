import Observation
import SerafinDesign

/// What is playing, shared by the full-screen player and the mini player.
///
/// This is the app shell's stand-in: it tracks what would be playing but plays nothing. SerafinPlayback's engine
/// takes over in plan tasks 1.6 and 1.7.
@Observable @MainActor final class PlaybackCoordinator {
    /// The movie or episode playing, or nil when nothing is.
    private(set) var nowPlaying: MediaItem?
    /// Whether playback is running rather than paused.
    private(set) var isPlaying = false
    /// Whether the full-screen player is showing.
    var isPlayerPresented = false

    /// Starts `item` and shows the full-screen player.
    func play(_ item: MediaItem) {
        nowPlaying = item
        isPlaying = true
        isPlayerPresented = true
    }

    /// Pauses or resumes.
    func togglePlayPause() {
        isPlaying.toggle()
    }

    /// Brings back the full-screen player for what is playing.
    func showPlayer() {
        guard nowPlaying != nil else { return }
        isPlayerPresented = true
    }

    /// Stops playback and hides both players.
    func stop() {
        isPlayerPresented = false
        isPlaying = false
        nowPlaying = nil
    }
}
