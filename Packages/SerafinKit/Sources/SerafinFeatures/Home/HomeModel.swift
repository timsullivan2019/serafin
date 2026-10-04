import Observation
import SerafinDesign

/// The rows of the home screen.
@Observable @MainActor final class HomeModel {
    /// The newest items of one library, shown as a row of posters.
    struct LatestRow: Identifiable {
        let library: MediaLibrary
        let items: [MediaCard]
        var id: String { library.id }
    }

    private(set) var continueWatching: [MediaCard] = []
    private(set) var nextUp: [MediaCard] = []
    private(set) var latest: [LatestRow] = []
    private(set) var hasLoaded = false

    /// Whether every row is empty, which shows the empty state.
    var isEmpty: Bool {
        continueWatching.isEmpty && nextUp.isEmpty && latest.allSatisfy(\.items.isEmpty)
    }

    /// Fills the rows from the catalog.
    func load() async {
        continueWatching = Catalog.continueWatching
        nextUp = Catalog.nextUp
        latest = Catalog.libraries.map { LatestRow(library: $0, items: Catalog.latest(in: $0)) }
        hasLoaded = true
    }
}
