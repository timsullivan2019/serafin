import Observation
import SerafinCore
import SerafinDesign

/// The Library tab's rows: one for each library, then Collections, Favourites, Unwatched and Genres. Each row asks
/// for its newest titles on its own, so the rows fill in as their answers arrive.
@Observable @MainActor final class LibrariesModel {
    enum Phase {
        /// Waiting for the libraries, before any row is known.
        case loading
        /// The rows are known, and fill in as they load.
        case loaded
        /// The libraries didn't load, or every row failed.
        case failed(UserMessage)
    }

    /// One row of the tab.
    enum Row: Hashable, Identifiable, Sendable {
        /// One library's newest movies or shows, under the library's own name, so a server with more than one movie
        /// library, or with libraries named its own way, reads as it does on the server.
        case library(MediaLibrary)
        /// The newest collections, shown when the server has any.
        case collections
        /// The newest favourites, or the newest titles not yet watched, from every library, shown when there are any.
        case shortcut(LibraryShortcut)
        /// The genres, as tiles, shown when the server lists any.
        case genres
    }

    /// How many titles a row holds.
    nonisolated static let rowLength = 12
    /// The order rows list their titles in: the newest additions first.
    nonisolated static let newestFirst = GridOptions(sort: .dateAdded, ascending: false)

    private(set) var phase = Phase.loading
    /// Every row the libraries call for, in order, whether or not it has anything in it.
    private(set) var rows: [Row] = []
    /// Each row's newest titles, once they've loaded.
    private(set) var titles: [Row: [MediaItem]] = [:]
    /// The genres, once they've loaded.
    private(set) var genres: [Genre]?
    /// The rows whose last answer was a failure, and which are left out until one succeeds.
    private var failed: Set<Row> = []
    /// Goes up with each load, so the genre tiles on screen ask for their posters again.
    private(set) var generation = 0

    /// The rows to show, in order. See ``visible(_:isLoaded:isEmpty:)``.
    var visibleRows: [Row] {
        Self.visible(rows, isLoaded: isLoaded, isEmpty: isEmpty)
    }

    /// Whether every row has had its answer, so a tab with nothing to show is really empty.
    var isSettled: Bool {
        rows.allSatisfy(isLoaded)
    }

    /// Loads the libraries, then every row at once.
    ///
    /// Rows keep what they show until their new titles arrive, so loading again, after pull to refresh or a change to
    /// a favourite, never empties the screen.
    func load(from media: any MediaSource) async {
        generation += 1
        do {
            rows = Self.rows(for: try await media.libraries())
        } catch is CancellationError {
            return
        } catch {
            if case .loaded = phase {} else { phase = .failed(UserMessage(error)) }
            return
        }
        // After a failure the tab starts over, its rows loading in place again.
        if case .failed = phase { failed = [] }
        titles = titles.filter { rows.contains($0.key) }
        phase = .loaded
        var failure: (any Error)?
        await withTaskGroup(of: Arrival.self) { group in
            for row in rows {
                group.addTask { await Self.fetch(row, from: media) }
            }
            for await arrival in group {
                switch arrival {
                case .titles(let row, let items):
                    titles[row] = items
                    failed.remove(row)
                case .genres(let list):
                    genres = list
                    failed.remove(.genres)
                case .failed(let row, let error):
                    // A cancelled load makes way for the next, which answers for the row.
                    if error is CancellationError { continue }
                    failure = failure ?? error
                    failed.insert(row)
                }
            }
        }
        if let failure, isSettled, visibleRows.isEmpty {
            phase = .failed(UserMessage(failure))
        }
    }

    /// The rows for `libraries`: one for each library, movies first, then shows, then libraries of both, each kind in
    /// the server's order; then Collections, Favourites, Unwatched and Genres. None at all without a library.
    ///
    /// Rows for Live TV, Music and Downloads join these in their own phases, behind those phases' flags; see
    /// docs/PLAN-2.md.
    static func rows(for libraries: [MediaLibrary]) -> [Row] {
        guard !libraries.isEmpty else { return [] }
        return MediaLibrary.ordered(libraries).map(Row.library) + [.collections]
            + LibraryShortcut.allCases.map(Row.shortcut) + [.genres]
    }

    /// The rows to show, in order.
    ///
    /// A library's row shows from the start, its cards loading in place, and goes if it turns out to be empty. Any
    /// other row may turn out empty, so it shows once it has loaded, and the rows after it wait for it: a row that
    /// arrives never pushes down a row already on screen.
    nonisolated static func visible(_ rows: [Row], isLoaded: (Row) -> Bool, isEmpty: (Row) -> Bool) -> [Row] {
        var visible: [Row] = []
        for row in rows {
            if isLoaded(row) {
                if !isEmpty(row) { visible.append(row) }
            } else if case .library = row {
                visible.append(row)
            } else {
                break
            }
        }
        return visible
    }

    private func isLoaded(_ row: Row) -> Bool {
        if failed.contains(row) { return true }
        return row == .genres ? genres != nil : titles[row] != nil
    }

    private func isEmpty(_ row: Row) -> Bool {
        row == .genres ? genres?.isEmpty ?? true : titles[row]?.isEmpty ?? true
    }

    /// What one row's request brought back.
    private enum Arrival: Sendable {
        case titles(Row, [MediaItem])
        case genres([Genre])
        case failed(Row, any Error)
    }

    /// Asks for one row's newest titles, or for the genres.
    nonisolated private static func fetch(_ row: Row, from media: any MediaSource) async -> Arrival {
        do {
            guard let scope = row.scope else { return .genres(try await media.genres()) }
            let page = try await media.page(of: scope, options: row.options, start: 0, limit: rowLength)
            return .titles(row, page.items.compactMap { $0 })
        } catch {
            return .failed(row, error)
        }
    }
}

extension LibrariesModel.Row {
    var id: String {
        switch self {
        case .library(let library): "library-\(library.id)"
        case .collections: "collections"
        case .shortcut(let shortcut): shortcut.rawValue
        case .genres: "genres"
        }
    }

    /// The row's title: the library's own name, or what the row holds, such as "Favorites".
    var title: String {
        scope?.title ?? String(localized: "Genres", bundle: .module, comment: "Genres, as a heading or a label.")
    }

    /// The grid the row's titles come from, or nil for the genres.
    var scope: GridScope? {
        switch self {
        case .library(let library): .library(library)
        case .collections: .collections
        case .shortcut(let shortcut): .shortcut(shortcut)
        case .genres: nil
        }
    }

    /// How the row asks for its titles: the newest additions first, with its grid's filter, such as favourites only.
    var options: GridOptions {
        var options = LibrariesModel.newestFirst
        options.unplayedOnly = scope?.initialOptions.unplayedOnly ?? false
        options.favouritesOnly = scope?.initialOptions.favouritesOnly ?? false
        return options
    }

    /// What the row's title opens: the row's grid, with that grid's own sort and filter chips, or the list of genres.
    var route: Route {
        switch self {
        case .library(let library): .library(library)
        case .collections: .collections
        case .shortcut(let shortcut): .shortcut(shortcut)
        case .genres: .genres
        }
    }
}

/// The genres of every library, for the Genres list.
@Observable @MainActor final class GenresModel {
    enum Phase {
        case loading
        case loaded([Genre])
        case failed(UserMessage)
    }

    private(set) var phase = Phase.loading

    func load(from media: any MediaSource) async {
        do {
            phase = .loaded(try await media.genres())
        } catch is CancellationError {
        } catch {
            if case .loaded = phase { return }
            phase = .failed(UserMessage(error))
        }
    }
}

/// One grid: a library, a genre, the collections or one collection, sorted and filtered.
///
/// The grid knows its full length from the first page, and holds a place for every item. Each place's page loads
/// when the place comes on screen, so a jump from the letter index to the middle of a long grid loads only the
/// pages around where it lands.
@Observable @MainActor final class LibraryModel {
    enum Phase {
        case loading
        case loaded
        case failed(UserMessage)
    }

    /// How many items one request loads.
    static let pageSize = 60
    /// How close to the end of a page a place has to be for the next page to load as well.
    static let prefetchDistance = 12
    /// How long a grid sorted by name has to be to get the letter index.
    static let indexMinimum = 48

    let scope: GridScope
    /// The sort and filters. Changing them reloads the grid.
    var options: GridOptions
    private(set) var phase = Phase.loading
    /// Every place in the grid, filled in as its page loads.
    private(set) var slots: [MediaItem?] = []
    /// Goes up whenever the grid reloads, so the places on screen load their pages again.
    private(set) var generation = 0
    /// The grid's genres and years, for the filter menus.
    private(set) var filters = LibraryFilters(genres: [], years: [])
    private var loadedOptions: GridOptions?
    private var loadedPages: Set<Int> = []
    private var loadingPages: Set<Int> = []
    private var letterPositions: [String: Int] = [:]

    init(scope: GridScope) {
        self.scope = scope
        options = scope.initialOptions
    }

    /// How many items the grid has.
    var total: Int { slots.count }

    /// The item in place `index`, or nil while its page loads.
    func item(at index: Int) -> MediaItem? {
        slots.indices.contains(index) ? slots[index] : nil
    }

    /// The letters the index shows, in the grid's order, or none when the grid isn't sorted by name or is short.
    var indexLetters: [String] {
        guard options.sort == .name, total >= Self.indexMinimum else { return [] }
        return options.ascending ? LetterIndex.alphabet : LetterIndex.alphabet.reversed()
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
    ///
    /// When only played marks or favourites changed, the grid keeps showing what it has while the pages on screen
    /// load again, so nothing flashes.
    func reload(from media: any MediaSource) async {
        let options = options
        do {
            let page = try await media.page(of: scope, options: options, start: 0, limit: Self.pageSize)
            guard options == self.options else { return }
            if options != loadedOptions || page.total != slots.count {
                slots = Array(repeating: nil, count: page.total)
                letterPositions = [:]
            }
            loadedOptions = options
            loadedPages = []
            loadingPages = []
            place(page.items, at: 0)
            loadedPages.insert(0)
            generation += 1
            phase = .loaded
        } catch is CancellationError {
        } catch {
            if case .loaded = phase, !slots.isEmpty { return }
            phase = .failed(UserMessage(error))
        }
        if filters.genres.isEmpty, filters.years.isEmpty {
            filters = (try? await media.filters(in: scope)) ?? filters
        }
    }

    /// Loads the page holding place `index`, and the next page too when the place is near the end of its own.
    func load(around index: Int, from media: any MediaSource) async {
        let page = index / Self.pageSize
        await loadPage(page, from: media)
        if index % Self.pageSize >= Self.pageSize - Self.prefetchDistance {
            await loadPage(page + 1, from: media)
        }
    }

    /// Where the titles under `letter` start, for the letter index, or nil when the server can't say.
    func position(of letter: String, from media: any MediaSource) async -> Int? {
        let options = options
        if let known = letterPositions[letter] { return known }
        var count = 0
        if let name = LetterPosition.name(for: letter, ascending: options.ascending) {
            guard let counted = try? await media.count(in: scope, options: options, before: name) else { return nil }
            count = counted
        }
        guard options == self.options, total > 0 else { return nil }
        let position = LetterPosition.position(counting: count, ascending: options.ascending, total: total)
        letterPositions[letter] = position
        return position
    }

    /// Asks the server again, skipping the cache, for pull to refresh.
    func refresh(from media: any MediaSource) async {
        await media.refresh()
        await reload(from: media)
    }

    private func loadPage(_ page: Int, from media: any MediaSource) async {
        let start = page * Self.pageSize
        guard start < slots.count, !loadedPages.contains(page), !loadingPages.contains(page) else { return }
        let options = options
        let generation = generation
        loadingPages.insert(page)
        let result = try? await media.page(of: scope, options: options, start: start, limit: Self.pageSize)
        // A reload in the meantime started the pages over, and its own loads replace this one.
        guard generation == self.generation else { return }
        loadingPages.remove(page)
        guard let result, options == self.options else { return }
        place(result.items, at: start)
        loadedPages.insert(page)
    }

    private func place(_ items: [MediaItem?], at start: Int) {
        for (offset, item) in items.enumerated() where start + offset < slots.count {
            slots[start + offset] = item
        }
    }
}

/// Where a letter's titles start in a grid sorted by name.
///
/// The server counts the titles whose sort names come before a name. Sort names are lowercase, and digits and
/// symbols come before letters, so "#" is the start of an A to Z grid.
enum LetterPosition {
    /// The name to count the titles before, or nil when the position needs no count.
    ///
    /// From A to Z, a letter's titles start after every title before it. From Z to A, they start after every title
    /// from the next letter on, so the count is of the titles before the next letter.
    static func name(for letter: String, ascending: Bool) -> String? {
        let lower = letter.lowercased()
        if ascending {
            return lower == "#" ? nil : lower
        }
        if lower == "#" { return "a" }
        // After "z" comes "{", which sorts after every title starting with z.
        return lower.unicodeScalars.first.flatMap { Unicode.Scalar($0.value + 1) }.map(String.init)
    }

    /// The position given the count for ``name(for:ascending:)``, kept inside a grid of `total` items.
    static func position(counting count: Int, ascending: Bool, total: Int) -> Int {
        let position = ascending ? count : total - count
        return min(max(position, 0), max(total - 1, 0))
    }
}
