import Foundation
import JellyfinAPI
import Observation
import SerafinCore

/// Where the account's language preferences live: the server, in the app.
protocol LanguagePreferenceStore: Sendable {
    /// The languages the server knows.
    func languages() async throws -> [Language]
    /// The account's preferences as saved.
    func languagePreferences() async throws -> LanguagePreferences
    /// Saves the account's preferences.
    func setLanguagePreferences(_ preferences: LanguagePreferences) async throws
}

extension LibraryRepository: LanguagePreferenceStore {}

/// The account's audio and subtitle languages, as Settings shows and changes them.
///
/// A change shows at once and is saved in the background. Saves go one at a time, each with the latest choices, so
/// quick changes never reach the server out of order. When a save fails, the server's own preferences come back.
@Observable @MainActor final class LanguagesModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(UserMessage)
    }

    private(set) var phase = Phase.loading
    /// The languages to choose from, by name in the device's language.
    private(set) var languages: [Language] = []
    /// The preferences as they stand, including changes still being saved.
    private(set) var preferences = LanguagePreferences()
    /// The last save that failed, until the next change.
    private(set) var failure: UserMessage?

    @ObservationIgnored private let store: any LanguagePreferenceStore
    @ObservationIgnored private let locale: Locale
    @ObservationIgnored private var saving: Task<Void, Never>?

    init(store: any LanguagePreferenceStore, locale: Locale = .current) {
        self.store = store
        self.locale = locale
    }

    /// Reads the languages and the preferences from the server.
    func load() async {
        do {
            async let languages = store.languages()
            async let preferences = store.languagePreferences()
            let saved = try await preferences
            var known = try await languages
            // A language saved by another app that the server doesn't list still shows as the one chosen.
            for code in [saved.audio, saved.subtitles].compactMap(\.self)
            where !known.contains(where: { $0.code == code }) {
                known.append(Language(code: code, name: code))
            }
            self.languages = Self.named(known, in: locale)
            self.preferences = saved
            phase = .loaded
        } catch is CancellationError {
        } catch {
            phase = .failed(UserMessage(error))
        }
    }

    /// Prefers audio in a language, or each video's default for nil.
    func setAudio(_ code: String?) {
        change { $0.audio = code }
    }

    /// Prefers subtitles in a language, or none in particular for nil.
    func setSubtitles(_ code: String?) {
        change { $0.subtitles = code }
    }

    /// Sets when subtitles show unasked.
    func setSubtitleMode(_ mode: SubtitlePlaybackMode) {
        change { $0.subtitleMode = mode }
    }

    /// Waits for any save still going.
    func finishSaving() async {
        await saving?.value
    }

    private func change(_ edit: (inout LanguagePreferences) -> Void) {
        var changed = preferences
        edit(&changed)
        guard changed != preferences else { return }
        preferences = changed
        failure = nil
        let previous = saving
        saving = Task {
            await previous?.value
            do {
                // The latest choices, which may be newer than this change.
                try await store.setLanguagePreferences(preferences)
            } catch is CancellationError {
            } catch {
                failure = UserMessage(error)
                if let saved = try? await store.languagePreferences() {
                    preferences = saved
                }
            }
        }
    }

    /// The server's languages, renamed in the device's language and sorted by those names.
    static func named(_ languages: [Language], in locale: Locale) -> [Language] {
        languages
            .map { Language(code: $0.code, name: locale.localizedString(forLanguageCode: $0.code) ?? $0.name) }
            .sorted { $0.name.compare($1.name, locale: locale) == .orderedAscending }
    }
}

extension SubtitlePlaybackMode {
    /// The choices in the order Settings lists them.
    static let settingsOrder: [SubtitlePlaybackMode] = [.default, .smart, .always, .onlyForced, .none]

    /// The mode as Settings lists it.
    var title: String {
        switch self {
        case .default:
            String(localized: "Automatic", bundle: .module, comment: "Subtitle mode: as the video marks them.")
        case .smart:
            String(
                localized: "For Other Languages", bundle: .module,
                comment: "Subtitle mode: when the audio isn't in the user's language.")
        case .always:
            String(localized: "Always", bundle: .module, comment: "Subtitle mode: always on.")
        case .onlyForced:
            String(localized: "Forced Only", bundle: .module, comment: "Subtitle mode: only forced subtitles.")
        case .none:
            String(localized: "Off", bundle: .module, comment: "Subtitle mode: only when turned on.")
        }
    }

    /// What the mode does, for the footer under it.
    var explanation: String {
        switch self {
        case .default:
            String(
                localized:
                    "Subtitles in your language show when the audio is in another. Otherwise only forced subtitles show, such as for signs or foreign speech.",
                bundle: .module, comment: "Explanation of the automatic subtitle mode.")
        case .smart:
            String(
                localized: "Subtitles in your language show when the audio is in another.", bundle: .module,
                comment: "Explanation of the subtitle mode for other languages.")
        case .always:
            String(
                localized: "Subtitles in your language always show.", bundle: .module,
                comment: "Explanation of the always-on subtitle mode.")
        case .onlyForced:
            String(
                localized:
                    "Only forced subtitles in the audio's language show, such as for signs or foreign speech.",
                bundle: .module, comment: "Explanation of the forced-only subtitle mode.")
        case .none:
            String(
                localized: "Subtitles show only when you turn them on.", bundle: .module,
                comment: "Explanation of the subtitle mode that leaves them off.")
        }
    }
}
