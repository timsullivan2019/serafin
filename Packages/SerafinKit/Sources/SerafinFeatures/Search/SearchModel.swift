import Observation

/// The search tab's query and its results.
@Observable @MainActor final class SearchModel {
    /// What the user has typed.
    var query = "" {
        didSet { results = Catalog.search(query) }
    }

    /// Matches for the current query.
    private(set) var results = SearchResults()

    /// Whether the user has typed anything that is not whitespace.
    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
