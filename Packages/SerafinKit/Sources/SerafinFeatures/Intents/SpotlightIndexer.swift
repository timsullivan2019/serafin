import AppIntents
import CoreSpotlight
import Foundation
import SerafinCore
import os

/// Keeps the signed-in user's movies and shows in Spotlight, with their posters, so searching the iPhone or iPad finds
/// them and a tap opens them in Serafin.
///
/// The library is written again at most once a day, newest additions first. Each pass writes into the domain the
/// last full pass didn't use, then removes that pass's domain, which takes away whatever has left the server. Signing
/// out, switching accounts and turning on the app lock empty the index.
actor SpotlightIndexer {
    /// The index the app writes to.
    static let shared = SpotlightIndexer(store: SystemSpotlight(), defaults: .standard)

    /// How long a full pass stands before the library is written again.
    static let refreshInterval: TimeInterval = 24 * 60 * 60
    /// How many items each request to the server lists.
    static let pageSize = 100
    /// How many posters load at once.
    static let posterLoads = 6
    /// The two domains passes take turns writing into.
    static let domains = ["library-a", "library-b"]

    private static let accountKey = "app.getserafin.serafin.spotlight.account"
    private static let domainKey = "app.getserafin.serafin.spotlight.domain"
    private static let dateKey = "app.getserafin.serafin.spotlight.date"
    private static let logger = Logger(serafinCategory: "spotlight")

    private let store: any SpotlightStore
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date
    /// The pass that's writing, if any.
    private var pass: Task<Void, Never>?

    /// Creates an indexer.
    ///
    /// - Parameters:
    ///   - store: Where entries go.
    ///   - defaults: Where it notes which account it wrote and when. Only IDs and a date, nothing from the library.
    ///   - now: The time, which tests move.
    init(store: any SpotlightStore, defaults: UserDefaults, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.defaults = defaults
        self.now = now
    }

    /// Writes `account`'s movies and shows to Spotlight, unless they were written within the last day. Another
    /// account's entries are removed first. Does nothing while a pass is already writing.
    ///
    /// - Parameters:
    ///   - account: Whose library it is.
    ///   - media: The library.
    ///   - poster: Makes a small JPEG of an item's poster.
    func update(
        account: SessionKey,
        media: any MediaSource,
        poster: @escaping @Sendable (MediaItem) async -> Data?
    ) async {
        guard pass == nil, store.isAvailable else { return }
        let task = Task { await write(account: account, media: media, poster: poster) }
        pass = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        pass = nil
    }

    /// Stops any pass and empties the index.
    func removeAll() async {
        pass?.cancel()
        await pass?.value
        do {
            try await store.removeAll()
        } catch {
            Self.logger.error("Could not empty Spotlight: \(error.localizedDescription, privacy: .private)")
        }
        forget()
    }

    /// One pass over the whole library.
    private func write(
        account: SessionKey,
        media: any MediaSource,
        poster: @escaping @Sendable (MediaItem) async -> Data?
    ) async {
        let owner = "\(account.serverID)/\(account.userID)"
        do {
            if defaults.string(forKey: Self.accountKey) != owner {
                try await store.removeAll()
                forget()
            } else if let date = defaults.object(forKey: Self.dateKey) as? Date,
                now().timeIntervalSince(date) < Self.refreshInterval
            {
                return
            }
            let previous = defaults.string(forKey: Self.domainKey)
            let domain = Self.domains.first { $0 != previous } ?? Self.domains[0]
            var written: Set<String> = []
            for library in try await media.libraries() {
                var start = 0
                while true {
                    try Task.checkCancellation()
                    let page = try await media.page(
                        of: .library(library),
                        options: GridOptions(sort: .dateAdded, ascending: false),
                        start: start,
                        limit: Self.pageSize
                    )
                    let items = page.items.compactMap { $0 }.filter { written.insert($0.id).inserted }
                    let entities = await Self.entities(for: items, poster: poster)
                    try Task.checkCancellation()
                    try await store.index(entities, domain: domain)
                    start += page.items.count
                    if page.items.isEmpty || start >= page.total { break }
                }
            }
            if let previous {
                try await store.remove(domains: [previous])
            }
            defaults.set(owner, forKey: Self.accountKey)
            defaults.set(domain, forKey: Self.domainKey)
            defaults.set(now(), forKey: Self.dateKey)
        } catch is CancellationError {
        } catch {
            // The next launch tries again.
            Self.logger.error(
                "Could not write the library to Spotlight: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Forgets which account was written, so the next pass starts afresh.
    private func forget() {
        for key in [Self.accountKey, Self.domainKey, Self.dateKey] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Entities for `items`, with their posters, a few loading at a time.
    private static func entities(
        for items: [MediaItem],
        poster: @escaping @Sendable (MediaItem) async -> Data?
    ) async -> [MediaEntity] {
        var posters: [String: Data] = [:]
        await withTaskGroup(of: (id: String, poster: Data?).self) { group in
            var waiting = items[...]
            for item in waiting.prefix(posterLoads) {
                group.addTask { (item.id, await poster(item)) }
            }
            waiting = waiting.dropFirst(posterLoads)
            for await result in group {
                posters[result.id] = result.poster
                if let item = waiting.popFirst() {
                    group.addTask { (item.id, await poster(item)) }
                }
            }
        }
        return items.map { MediaEntity($0, poster: posters[$0.id]) }
    }
}

/// Where the indexer writes: the system's Spotlight index in the app, a recording in tests.
protocol SpotlightStore: Sendable {
    /// Whether the device can index at all.
    var isAvailable: Bool { get }
    /// Adds entities, replacing any entry with the same ID, domain and all.
    func index(_ entities: [MediaEntity], domain: String) async throws
    /// Removes every entry in these domains.
    func remove(domains: [String]) async throws
    /// Removes every entry.
    func removeAll() async throws
}

/// The app's Spotlight index. Entries are readable only while the device is unlocked.
struct SystemSpotlight: SpotlightStore {
    private static let indexName = "app.getserafin.serafin.library"

    var isAvailable: Bool {
        CSSearchableIndex.isIndexingAvailable()
    }

    func index(_ entities: [MediaEntity], domain: String) async throws {
        guard !entities.isEmpty else { return }
        let items = entities.map { entity in
            let item = CSSearchableItem(
                uniqueIdentifier: entity.id, domainIdentifier: domain, attributeSet: entity.attributeSet)
            // Lets Siri and Apple Intelligence know an entry is this title, and has Spotlight open it with
            // OpenMediaIntent.
            item.associateAppEntity(entity)
            return item
        }
        try await Self.index().indexSearchableItems(items)
    }

    func remove(domains: [String]) async throws {
        try await Self.index().deleteSearchableItems(withDomainIdentifiers: domains)
    }

    func removeAll() async throws {
        try await Self.index().deleteAllSearchableItems()
    }

    private static func index() -> CSSearchableIndex {
        CSSearchableIndex(name: indexName, protectionClass: .complete)
    }
}
