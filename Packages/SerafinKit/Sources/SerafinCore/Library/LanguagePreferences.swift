import JellyfinAPI

/// The languages Jellyfin chooses audio and subtitles in for a user, and when it shows subtitles unasked.
///
/// They're saved on the server with the user's other settings, so the server applies them when it picks a video's
/// default audio and subtitles, and every Jellyfin app the user signs in to follows them.
public struct LanguagePreferences: Hashable, Sendable {
    /// The audio language to prefer, as a three-letter code such as "eng", or nil to play each video's default audio.
    public var audio: String?
    /// The subtitle language to prefer, as a three-letter code, or nil for none in particular.
    public var subtitles: String?
    /// When subtitles show without being turned on.
    public var subtitleMode: SubtitlePlaybackMode

    /// Creates preferences.
    public init(audio: String? = nil, subtitles: String? = nil, subtitleMode: SubtitlePlaybackMode = .default) {
        self.audio = audio
        self.subtitles = subtitles
        self.subtitleMode = subtitleMode
    }

    /// The preferences in a user's settings as the server sends them. An empty language means none.
    init(configuration: [String: AnyJSON]) {
        var mode = SubtitlePlaybackMode.default
        if case .string(let name)? = configuration[Self.subtitleModeKey],
            let known = SubtitlePlaybackMode(rawValue: name)
        {
            mode = known
        }
        self.init(
            audio: Self.language(Self.audioKey, in: configuration),
            subtitles: Self.language(Self.subtitlesKey, in: configuration),
            subtitleMode: mode
        )
    }

    /// A user's settings with these preferences in place of theirs, and everything else as it was.
    func applied(to configuration: [String: AnyJSON]) -> [String: AnyJSON] {
        var configuration = configuration
        func set(_ code: String?, for key: String) {
            if let code {
                configuration[key] = .string(code)
            } else if Self.language(key, in: configuration) != nil {
                // An empty string from another app means no language too, so it stays as it is.
                configuration[key] = .null
            }
        }
        set(audio, for: Self.audioKey)
        set(subtitles, for: Self.subtitlesKey)
        configuration[Self.subtitleModeKey] = .string(subtitleMode.rawValue)
        return configuration
    }

    /// The language saved under `key`, or nil when there's none, whether saved as null or as an empty string.
    private static func language(_ key: String, in configuration: [String: AnyJSON]) -> String? {
        guard case .string(let code)? = configuration[key], !code.isEmpty else { return nil }
        return code
    }

    private static let audioKey = "AudioLanguagePreference"
    private static let subtitlesKey = "SubtitleLanguagePreference"
    private static let subtitleModeKey = "SubtitleMode"
}

/// A language the server knows, for choosing preferences.
public struct Language: Hashable, Sendable, Identifiable {
    /// The three-letter code Jellyfin saves preferences with, such as "eng".
    public let code: String
    /// The server's name for the language, in English.
    public let name: String

    public var id: String { code }

    /// Creates a language.
    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    /// A language from the server's list, or nil without a three-letter code.
    init?(_ culture: CultureDto) {
        guard let code = culture.threeLetterISOLanguageName, !code.isEmpty else { return nil }
        self.init(code: code, name: culture.displayName ?? culture.name ?? code)
    }
}
