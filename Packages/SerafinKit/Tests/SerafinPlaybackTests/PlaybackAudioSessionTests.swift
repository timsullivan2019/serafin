import Foundation
import Testing

@testable import SerafinPlayback

#if canImport(UIKit)
    import AVFoundation
#endif

@Suite struct PlaybackAudioSessionTests {
    @MainActor @Test func sessionWorkRunsOffTheMainThread() async {
        let ranOnMainThread = await PlaybackAudioSession.onSessionQueue { Thread.isMainThread }
        #expect(!ranOnMainThread)
    }

    #if canImport(UIKit)
        @MainActor @Test func activatingSetsUpMoviePlayback() async {
            await PlaybackAudioSession.activate()
            let session = AVAudioSession.sharedInstance()
            #expect(session.category == .playback)
            #expect(session.mode == .moviePlayback)
            await PlaybackAudioSession.deactivate()
        }
    #endif
}
