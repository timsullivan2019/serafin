import Observation
import SerafinDesign

/// How a library grid is ordered.
enum LibrarySort: CaseIterable, Identifiable {
    case name
    case dateAdded
    case year

    var id: Self { self }

    var title: String {
        switch self {
        case .name:
            String(localized: "Name", bundle: .module, comment: "Library sort option: alphabetical.")
        case .dateAdded:
            String(localized: "Date Added", bundle: .module, comment: "Library sort option: newest additions first.")
        case .year:
            String(localized: "Year", bundle: .module, comment: "Library sort option: newest releases first.")
        }
    }
}

/// One library's grid, with its sort order and unplayed filter.
@Observable @MainActor final class LibraryModel {
    let library: MediaLibrary?
    var sort = LibrarySort.name
    var unplayedOnly = false

    init(id: String) {
        library = Catalog.library(id: id)
    }

    /// The library's items, filtered and sorted.
    var items: [MediaCard] {
        let all = library?.items ?? []
        let filtered = unplayedOnly ? all.filter { !$0.isPlayed } : all
        switch sort {
        case .name:
            return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateAdded:
            // The fixtures are listed oldest addition first.
            return filtered.reversed()
        case .year:
            return filtered.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        }
    }
}
