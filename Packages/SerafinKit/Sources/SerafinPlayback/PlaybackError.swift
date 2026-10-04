import JellyfinAPI

/// Failures from SerafinPlayback. SerafinFeatures maps each case to a message for the user. Network and sign-in
/// failures arrive as SerafinCore's `SerafinError`.
public enum PlaybackError: Error, Equatable, Sendable {
    /// The server has no version of the item the player can play, even by converting it.
    case notPlayable
    /// The user's account isn't allowed to play this item.
    case notAllowed
    /// The server is already running as many streams as it allows.
    case tooManyStreams
    /// The player couldn't play the stream it was given.
    case playerFailed

    /// The failure for an error code the server reports in its playback info.
    init(_ code: PlaybackErrorCode) {
        switch code {
        case .notAllowed: self = .notAllowed
        case .noCompatibleStream: self = .notPlayable
        case .rateLimitExceeded: self = .tooManyStreams
        }
    }
}
