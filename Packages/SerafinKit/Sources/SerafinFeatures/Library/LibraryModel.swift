import Observation
import SerafinCore
import SerafinDesign

/// The Library tab's list of libraries.
@Observable @MainActor final class LibrariesModel {
    enum Phase {
        case loading
        case loaded([MediaLibrary])
        case failed(UserMessage)
    }

    private(set) var phase = Phase.loading

    func load(from media: any MediaSource) async {
        do {
            phase = .loaded(try await media.libraries())
        } catch is CancellationError {
        } catch {
            if case .loaded = phase { return }
            phase = .failed(UserMessage(error))
        }
    }
}

/// One library's grid: its items a page at a time, sorted and filtered.
@Observable @MainActor final class LibraryModel {
    enum Phase {
        case loading
        case loaded
        case failed(UserMessage)
    }

    /// How many items from the end of the loaded ones the next page starts loading.
    static let prefetchDistance = 12

    let library: MediaLibrary
    /// The sort and filters. Changing them reloads the grid.
    var options = GridOptions()
    private(set) var phase = Phase.loading
    private(set) var items: [MediaItem] = []
    /// The library's genres and years, for the filter menus.
    private(set) var filters = LibraryFilters(genres: [], years: [])
    private(set) var isLoadingMore = false
    private var nextStart: Int?

    init(library: MediaLibrary) {
        self.library = library
    }

    /// Picks a sort. Picking the current sort again flips its direction; a new sort starts in its natural direction.
    func select(_ sort: LibraryQuery.Sort) {
        if options.sort == sort {
            options.ascending.toggle()
        } else {
            options.sort = sort
            options.ascending = sort == .name
        }
    }

    /// Loads the first page for the current options, and the filter menus the first time.
    func reload(from media: any MediaSource) async {
        let options = options
        do {
            let page = try await media.page(of: library, options: options, start: 0)
            guard options == self.options else { return }
            items = page.items
            nextStart = page.nextStart
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if case .loaded = phase, !items.isEmpty { return }
            phase = .failed(UserMessage(error))
        }
        if filters.genres.isEmpty, filters.years.isEmpty {
            filters = (try? await media.filters(in: library)) ?? filters
        }
    }

    /// Loads the next page when `item` is close to the end of what has loaded.
    func loadMore(after item: MediaItem, from media: any MediaSource) async {
        guard
            let start = nextStart, !isLoadingMore,
            let index = items.firstIndex(where: { $0.id == item.id }),
            index >= items.count - Self.prefetchDistance
        else { return }
        let options = options
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await media.page(of: library, options: options, start: start), options == self.options
        else { return }
        let known = Set(items.map(\.id))
        items += page.items.filter { !known.contains($0.id) }
        nextStart = page.nextStart
    }

    /// Asks the server again, skipping the cache, for pull to refresh.
    func refresh(from media: any MediaSource) async {
        await media.refresh()
        await reload(from: media)
    }
}
