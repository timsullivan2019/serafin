/// What the server's policy lets the signed-in user have converted for them, which a download the server converts
/// honours. Jellyfin allows each by default, and its dashboard sets them per user.
public struct ConversionPermissions: Hashable, Sendable {
    /// Whether the server may put the video and audio in another container without converting them: the dashboard's
    /// "Allow video playback that requires conversion without re-encoding".
    public var remuxing: Bool
    /// Whether the server may convert the video: "Allow video playback that requires transcoding".
    public var videoTranscoding: Bool
    /// Whether the server may convert the audio: "Allow audio playback that requires transcoding".
    public var audioTranscoding: Bool

    /// Creates permissions.
    public init(remuxing: Bool = true, videoTranscoding: Bool = true, audioTranscoding: Bool = true) {
        self.remuxing = remuxing
        self.videoTranscoding = videoTranscoding
        self.audioTranscoding = audioTranscoding
    }

    /// Everything allowed, as Jellyfin's default policy has it.
    public static let all = ConversionPermissions()

    /// Whether the policy allows any conversion. Jellyfin offers none when it allows none.
    public var allowsAny: Bool {
        remuxing || videoTranscoding || audioTranscoding
    }
}
