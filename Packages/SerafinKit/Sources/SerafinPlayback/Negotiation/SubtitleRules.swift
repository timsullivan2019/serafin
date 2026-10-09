import Foundation
import JellyfinAPI
import MediaAccessibility
import SerafinCore

/// The subtitles showing, as the player and its sheet agree on them. The app decides it as each video starts and the
/// sheet changes it, so what the sheet checks is always what's on screen.
public enum SubtitleSelection: Hashable, Sendable {
    /// No subtitles.
    case off
    /// The server's subtitle stream with this index: text the player draws, or an image the server burns into the
    /// picture.
    case stream(Int)
    /// Subtitles iOS generates from the audio, where it offers them.
    case generated

    /// The subtitle stream to ask the server for: this one's, or -1 for none, since the player makes generated
    /// subtitles itself.
    public var serverIndex: Int {
        if case .stream(let index) = self { index } else { -1 }
    }
}

/// Subtitles picked in the player, as they carry on to the next episode: off, generated, or a language.
public enum SubtitleChoice: Equatable, Sendable {
    /// No subtitles.
    case off
    /// The subtitles iOS generates from the audio.
    case generated
    /// Subtitles in `language`, as the server names it, such as "eng", preferring forced or SDH ones as picked.
    case language(String, isForced: Bool, isHearingImpaired: Bool)
}

/// How a video's starting subtitles follow Settings: the subtitle mode, the languages the viewer reads, and the
/// language of the audio playing.
///
/// Serafin decides rather than leaving it to the server, which falls back on the last subtitles picked for each video
/// and so made Settings look ignored. The modes mean:
///
/// - Off: none.
/// - Always: the best subtitles in the viewer's language.
/// - For Other Languages (Jellyfin's Smart): those, but only when the audio is in another language.
/// - Forced Only: the forced subtitles in the audio's language, if there are any.
/// - Automatic (Jellyfin's Default): the viewer's language when the audio is in another, otherwise forced only.
///
/// Closed Captions + SDH in the system's accessibility settings turns subtitles on as Always does, preferring SDH,
/// because that setting is how deaf and hard of hearing viewers ask every app for captions.
public struct SubtitleRules: Hashable, Sendable {
    /// When subtitles show without being turned on.
    public var mode: SubtitlePlaybackMode
    /// The languages the viewer reads, most wanted first, as ``SubtitleRules/language(_:)`` normalizes them.
    public var languages: [String]
    /// Whether the system's accessibility settings ask for captions, with SDH preferred.
    public var wantsCaptions: Bool

    /// Creates rules.
    ///
    /// - Parameters:
    ///   - mode: When subtitles show without being turned on.
    ///   - languages: The languages the viewer reads, most wanted first, as Jellyfin codes or BCP 47 tags.
    ///   - wantsCaptions: Whether the system's accessibility settings ask for captions.
    public init(mode: SubtitlePlaybackMode, languages: [String], wantsCaptions: Bool = false) {
        self.mode = mode
        var seen: Set<String> = []
        self.languages = languages.compactMap(Self.language).filter { seen.insert($0).inserted }
        self.wantsCaptions = wantsCaptions
    }

    /// The rules for an account: its subtitle mode, and its subtitle language or, with none set, the device's
    /// languages.
    ///
    /// - Parameters:
    ///   - preferences: The account's preferences, from the server.
    ///   - deviceLanguages: The languages the device is set to, most preferred first.
    ///   - wantsCaptions: Whether the system's accessibility settings ask for captions.
    public init(
        preferences: LanguagePreferences,
        deviceLanguages: [String] = Locale.preferredLanguages,
        wantsCaptions: Bool = Self.systemWantsCaptions()
    ) {
        self.init(
            mode: preferences.subtitleMode,
            languages: preferences.subtitles.map { [$0] } ?? deviceLanguages,
            wantsCaptions: wantsCaptions
        )
    }

    /// Whether Closed Captions + SDH is on in the system's accessibility settings.
    public static func systemWantsCaptions() -> Bool {
        MACaptionAppearanceGetDisplayType(.user) == .alwaysOn
    }

    /// The subtitles to start with, among a version's `streams`, for audio in `audioLanguage`.
    ///
    /// - Parameters:
    ///   - streams: The version's streams; only its subtitles count.
    ///   - audioLanguage: The language of the audio playing, as the server names it, or nil when unknown.
    public func selection(among streams: [MediaStream], audioLanguage: String?) -> SubtitleSelection {
        let subtitles = streams.filter { $0.type == .subtitle && $0.index != nil }
        let audio = Self.language(audioLanguage)
        // Unknown audio is taken to be in the viewer's language, as most files without a language tag are.
        let audioIsTheirs = audio.map(languages.contains) ?? true
        let theirs = inTheirLanguage(subtitles)
        let forced = forcedFor(audio, among: subtitles)
        let picked: MediaStream?
        if wantsCaptions {
            picked = theirs ?? forced
        } else {
            switch mode {
            case .none:
                picked = nil
            case .always:
                picked = theirs
            case .smart:
                picked = audioIsTheirs ? nil : theirs
            case .onlyForced:
                picked = forced
            case .default:
                picked = audioIsTheirs ? forced : theirs
            }
        }
        return picked?.index.map(SubtitleSelection.stream) ?? .off
    }

    /// The best subtitles in the viewer's languages: full ones before forced, then SDH as the system's settings
    /// prefer it, text before pictures, the file's default, and the file's order.
    private func inTheirLanguage(_ subtitles: [MediaStream]) -> MediaStream? {
        for language in languages {
            let candidates = subtitles.filter { Self.language($0.language) == language }
            let ranked = candidates.enumerated().sorted { first, second in
                let a = first.element
                let b = second.element
                let keys = [
                    (a.isForced != true, b.isForced != true),
                    ((a.isHearingImpaired == true) == wantsCaptions, (b.isHearingImpaired == true) == wantsCaptions),
                    (Self.isText(a), Self.isText(b)),
                    (a.isDefault == true, b.isDefault == true),
                ]
                for (left, right) in keys where left != right {
                    return left
                }
                return first.offset < second.offset
            }
            if let best = ranked.first?.element {
                return best
            }
        }
        return nil
    }

    /// The forced subtitles for audio in `audio`: in that language, or with no language at all. With the audio's
    /// language unknown, forced subtitles in the viewer's language count too.
    private func forcedFor(_ audio: String?, among subtitles: [MediaStream]) -> MediaStream? {
        let forced = subtitles.filter { $0.isForced == true }
        let wanted = audio.map { [$0] } ?? languages
        for language in wanted {
            if let match = forced.first(where: { Self.language($0.language) == language }) {
                return match
            }
        }
        return forced.first { Self.language($0.language) == nil }
    }

    /// Whether the player draws `stream` as text, rather than the server burning it into the picture as it does
    /// pictures and styled ASS and SSA, which Jellyfin can't turn into the WebVTT the player draws.
    static func isText(_ stream: MediaStream) -> Bool {
        let burned: Set = ["ass", "ssa", "pgssub", "pgs", "dvdsub", "vobsub", "dvbsub", "dvb_subtitle", "xsub"]
        if burned.contains(stream.codec?.lowercased() ?? "") {
            return false
        }
        return stream.isTextSubtitleStream ?? true
    }

    /// A language as rules compare them: ISO 639-1 where there's a two-letter code, so "ger", "deu", "de" and "de-DE"
    /// all read "de". Nil for no language, an unknown one, or Jellyfin's placeholders.
    ///
    /// - Parameter code: An ISO 639-2 code, bibliographic or terminology, as Jellyfin writes them, or a BCP 47 tag.
    public static func language(_ code: String?) -> String? {
        guard
            var code = code?.trimmingCharacters(in: .whitespaces).lowercased(),
            !code.isEmpty,
            !["und", "unknown", "mis", "mul", "zxx", "qaa"].contains(code)
        else { return nil }
        if let primary = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first {
            code = String(primary)
        }
        code = bibliographic[code] ?? code
        return Locale.LanguageCode(code).identifier(.alpha2) ?? code
    }

    /// The ISO 639-2 bibliographic codes Jellyfin and most files use where they differ from the terminology codes
    /// Foundation knows, and Jellyfin's code for Brazilian Portuguese.
    private static let bibliographic = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho", "cze": "ces", "dut": "nld",
        "fre": "fra", "geo": "kat", "ger": "deu", "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri",
        "may": "msa", "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym", "pob": "por",
    ]
}
