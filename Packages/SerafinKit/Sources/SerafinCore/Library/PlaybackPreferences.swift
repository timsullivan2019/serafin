import JellyfinAPI

/// What a user's Jellyfin account says about playback: the languages for audio and subtitles, and whether the next
/// episode plays by itself when one ends.
///
/// They're saved on the server with the user's other settings, so every Jellyfin app the user signs in to follows
/// them.
public struct PlaybackPreferences: Hashable, Sendable {
    /// The audio and subtitle languages, and when subtitles show unasked.
    public var languages: LanguagePreferences
    /// Whether the next episode plays by itself after a countdown, as the account's Play Next Episode Automatically
    /// setting says. On unless turned off, as in Jellyfin.
    public var playsNextEpisodeAutomatically: Bool

    /// Creates preferences.
    public init(languages: LanguagePreferences = LanguagePreferences(), playsNextEpisodeAutomatically: Bool = true) {
        self.languages = languages
        self.playsNextEpisodeAutomatically = playsNextEpisodeAutomatically
    }

    /// The preferences in a user's settings as the server sends them.
    init(configuration: [String: AnyJSON]) {
        var playsNext = true
        if case .bool(let on)? = configuration[Self.nextEpisodeAutoPlayKey] {
            playsNext = on
        }
        self.init(
            languages: LanguagePreferences(configuration: configuration), playsNextEpisodeAutomatically: playsNext)
    }

    private static let nextEpisodeAutoPlayKey = "EnableNextEpisodeAutoPlay"
}
