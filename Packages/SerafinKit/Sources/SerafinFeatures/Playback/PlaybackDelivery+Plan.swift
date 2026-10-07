import SerafinDesign
import SerafinPlayback

extension PlaybackDelivery {
    /// How a plan's stream reaches the player, in the words the player and Settings show.
    init(_ method: PlaybackPlan.Method) {
        switch method {
        case .directPlay: self = .directPlay
        case .directStream: self = .repackaged
        case .transcode: self = .transcoding
        }
    }
}
