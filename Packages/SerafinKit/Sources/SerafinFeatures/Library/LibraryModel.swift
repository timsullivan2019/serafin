import Observation
import SerafinCore
import SerafinDesign

/// The Library tab's libraries, each with its tile's picture and count, and whether to offer collections.
@Observable @MainActor final class LibrariesModel {
    enum Phase {
        case loading
        case loaded([MediaLibrary])
        case failed(UserMessage)
    }

    /// What a library's tile shows.
    struct Overview: Sendable {
        /// How many movies or shows the library holds.
        let total: Int
        /// Its newest posters, up to four, for its collage.
        let newest: [MediaItem]
    }

    /// How many posters a collage takes.
    static let collageSize = 4

    private(set) var phase = Phase.loading
    /// Whether the server has collections, which adds a Collections row. A failed check leaves it out.
    private(set) var hasCollections = false
    /// Each library's tile, by library ID, as they load.
    private(set) var overviews: [String: Overview] = [:]

    func load(from media: any MediaSource) async {
        async let collections = try? media.hasCollections()
        do {
            let libraries = try await media.libraries()
            phase = .loaded(libraries)
            await loadOverviews(of: libraries, from: media)
        } catch is CancellationError {
        } catch {
            if case .loaded = phase {} else { phase = .failed(UserMessage(error)) }
        }
        hasCollections = await collections ?? hasCollections
    }

    /// Asks for every library's count and newest posters at once. A library whose answer fails keeps its last tile,
    /// or shows a plain one.
    private func loadOverviews(of libraries: [MediaLibrary], from media: any MediaSource) async {
        let newestFirst = GridOptions(sort: .dateAdded, ascending: false)
        await withTaskGroup(of: (String, Overview?).self) { group in
            for library in libraries {
                group.addTask {
                    let page = try? await media.page(
                        of: .library(library), options: newestFirst, start: 0, limit: Self.collageSize)
                    guard let page else { return (library.id, nil) }
                    return (library.id, Overview(total: page.total, newest: page.items.compactMap { $0 }))
                }
            }
            for await (id, overview) in group {
                if let overview {
                    overviews[id] = overview
                }
            }
        }
    }

    /// How many titles a library holds, as its tile says it, such as "75 movies".
    nonisolated static func caption(total: Int, kind: MediaLibrary.Kind) -> String {
        switch kind {
        case .movies:
            String(
                localized: "\(total) movies", bundle: .module,
                comment: "How many movies a library holds, under its name on the Library tab.")
        case .shows:
            String(
                localized: "\(total) shows", bundle: .module,
                comment: "How many shows a library holds, under its name on the Library tab.")
        case .mixed:
            String(
                localized: "\(total) movies and shows", bundle: .module,
                comment: "A number of movies and shows: in Shortcuts, and under a library's name on the Library tab.")
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
