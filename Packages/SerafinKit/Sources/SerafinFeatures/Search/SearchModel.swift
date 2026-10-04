import Foundation
import Observation

/// The search tab's query and its results.
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

    /// The query without surrounding spaces.
    var term: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
