import Foundation
import Observation
import SerafinCore

/// The search tab's query and its results, and what it offers before anything is typed: recent searches and a few
/// suggested titles.
@Observable @MainActor final class SearchModel {
    enum Phase {
        case idle
        case searching
        case results(MediaSearchResults)
        case failed(UserMessage)
    }

    /// How long typing must pause before a search starts, so each keystroke doesn't send one.
    static let pause = Duration.milliseconds(300)

    /// What the user has typed.
    var query = ""
    private(set) var phase = Phase.idle
    /// The account's recent searches, newest first.
    private(set) var recents: [String] = []
    /// Movies and shows the user hasn't watched, suggested before anything is typed.
    private(set) var suggestions: [MediaItem] = []
    /// Whether the suggestions have been asked for, so the empty field doesn't flash its explanation first.
    private(set) var hasLoadedSuggestions = false
    @ObservationIgnored private var recentSearches = RecentSearches(account: nil)

    /// The query without surrounding spaces.
    var term: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the results on screen are worth remembering: the current term found something.
    var isShowingResults: Bool {
        if case .results(let results) = phase { !results.isEmpty } else { false }
    }

    /// Searches for the current query once typing pauses. Typing again cancels the wait.
    func search(in media: any MediaSource) async {
        let term = term
        guard !term.isEmpty else {
            phase = .idle
            return
        }
        do {
            try await Task.sleep(for: Self.pause)
            if case .results = phase {} else { phase = .searching }
            let results = try await media.search(term)
            phase = .results(results)
        } catch is CancellationError {
        } catch {
            phase = .failed(UserMessage(error))
        }
    }

    // MARK: - Before anything is typed

    /// Shows `account`'s recent searches, kept in `defaults`.
    func showRecents(of account: SessionKey?, in defaults: UserDefaults = .standard) {
        recentSearches = RecentSearches(account: account, defaults: defaults)
        recents = recentSearches.terms
    }

    /// Remembers the current term as the newest recent search.
    func remember() {
        guard !term.isEmpty else { return }
        recents = recentSearches.record(term)
    }

    /// Searches for a recent term again, and moves it to the top.
    func searchAgain(_ recent: String) {
        query = recent
        remember()
    }

    /// Forgets every recent search.
    func clearRecents() {
        recentSearches.clear()
        recents = []
    }

    /// Asks for a few titles to suggest. Suggestions that fail to load are simply left out.
    func loadSuggestions(from media: any MediaSource) async {
        let loaded = try? await media.suggestions()
        guard !Task.isCancelled else { return }
        suggestions = loaded ?? []
        hasLoadedSuggestions = true
    }
}
