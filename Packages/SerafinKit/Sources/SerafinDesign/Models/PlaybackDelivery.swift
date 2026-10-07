import Foundation

/// How a video reaches the player: the original file, repackaged by the server, or converted by it.
///
/// The player and Settings both describe it in these exact words, so the wording lives here once.
public enum PlaybackDelivery: CaseIterable, Hashable, Sendable {
    /// The original file plays as it is.
    case directPlay
    /// The server moves the original video and audio into a stream the player can read, without changing them.
    case repackaged
    /// The server converts the video, the audio or both.
    case transcoding

    /// The name of the delivery, such as "Direct play".
    public var title: String {
        switch self {
        case .directPlay:
            String(localized: "Direct play", bundle: .module, comment: "How a video plays: the original file as it is.")
        case .repackaged:
            String(
                localized: "Repackaged on server (no quality loss)",
                bundle: .module,
                comment: "How a video plays: the server moves the original video and audio into a new container."
            )
        case .transcoding:
            String(
                localized: "Transcoding on server",
                bundle: .module,
                comment: "How a video plays: the server converts the video or audio."
            )
        }
    }

    /// One sentence on what the delivery means, for Settings.
    public var explanation: String {
        switch self {
        case .directPlay:
            String(
                localized: "The original file plays as it is.",
                bundle: .module,
                comment: "Settings explanation of direct play."
            )
        case .repackaged:
            String(
                localized:
                    "The server moves the original video and audio into a format this device plays, without converting them.",
                bundle: .module,
                comment: "Settings explanation of repackaging on the server."
            )
        case .transcoding:
            String(
                localized:
                    "The server converts the video or audio, which takes more of its power and can lower the quality.",
                bundle: .module,
                comment: "Settings explanation of transcoding on the server."
            )
        }
    }

    /// The SF Symbol shown beside the delivery.
    public var systemImage: String {
        switch self {
        case .directPlay: "play.rectangle"
        case .repackaged: "shippingbox"
        case .transcoding: "gearshape.2"
        }
    }
}
