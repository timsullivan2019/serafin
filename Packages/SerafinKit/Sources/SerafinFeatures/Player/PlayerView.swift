import SerafinDesign
import SwiftUI

/// The full-screen player. In the app shell it shows the glass controls over black; video arrives with plan
/// tasks 1.6 and 1.7.
struct PlayerView: View {
    @Environment(PlaybackCoordinator.self) private var playback

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            if let card = playback.nowPlaying {
                PlayerControls(
                    title: card.title,
                    subtitle: card.eyebrowText,
                    isPlaying: playback.isPlaying,
                    elapsed: (card.runtime ?? .zero) * card.progress,
                    duration: card.runtime ?? .zero,
                    actions: PlayerControlActions(
                        close: { playback.isPlayerPresented = false },
                        playPause: { playback.togglePlayPause() }
                    )
                )
            }
        }
        .persistentSystemOverlays(.hidden)
        #if os(iOS)
            .statusBarHidden()
        #endif
    }
}

#Preview {
    let playback = PlaybackCoordinator()
    playback.play(MockMedia.movies[1])
    return PlayerView()
        .environment(playback)
}
