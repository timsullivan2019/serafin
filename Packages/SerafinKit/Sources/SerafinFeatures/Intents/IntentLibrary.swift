import Foundation
import SerafinCore
import SerafinDesign

#if canImport(UIKit)
    import UIKit
#endif

/// The signed-in user's library as Siri, Shortcuts and Spotlight use it.
struct IntentLibrary: Sendable {
    /// The most matches a spoken or typed title offers.
    static let matchLimit = 10
    /// The most titles Siri and Shortcuts suggest.
    static let suggestionLimit = 20
    /// How long a list waits for posters before showing the titles without them.
    static let posterDeadline = Duration.seconds(2)

    let media: any MediaSource
    /// Makes a small JPEG of an item's poster, or nil when it has none.
    let poster: @Sendable (MediaItem) async -> Data?

    /// The library of whoever is signed in, once the saved account has loaded. Siri may have started the app just
    /// now, in the background.
    ///
    /// - Throws: ``IntentError/signedOut`` when no one is signed in.
    @MainActor static func current(in session: AppSession) async throws -> IntentLibrary {
        await session.load()
        guard let library = session.library else { throw IntentError.signedOut }
        let artwork = session.artwork
        return IntentLibrary(media: LiveMediaSource(library: library)) { item in
            await PosterThumbnail.jpeg(of: item, from: artwork)
        }
    }

    /// What Continue Watching plays: the movie or episode the user started most recently, otherwise the next episode
    /// of a show they're watching.
    ///
    /// - Throws: ``IntentError/nothingToContinue`` when there's neither.
    func continueWatching() async throws -> MediaItem {
        let items = try await translatingErrors { try await media.nextToWatch() }
        guard let item = items.first(where: { $0.card.kind == .movie || $0.card.kind == .episode }) else {
            throw IntentError.nothingToContinue
        }
        return item
    }

    /// The items with these IDs, in the same order, leaving out any the server no longer has.
    func entities(for ids: [String]) async throws -> [MediaEntity] {
        var items: [MediaItem] = []
        for id in ids {
            do {
                items.append(try await media.item(id))
            } catch SerafinError.notFound {
                continue
            } catch {
                throw IntentError(error)
            }
        }
        return await entities(items)
    }

    /// Movies, shows and episodes whose titles match `term`, exact titles first.
    func entities(matching term: String) async throws -> [MediaEntity] {
        let results = try await translatingErrors { try await media.search(term) }
        let items = Self.ranked(results.movies + results.shows + results.episodes, for: term)
        return await entities(Array(items.prefix(Self.matchLimit)))
    }

    /// What Siri and Shortcuts offer first: Continue Watching, then Next Up.
    func suggestions() async throws -> [MediaEntity] {
        let items = try await translatingErrors { try await media.nextToWatch() }
        return await entities(Array(items.prefix(Self.suggestionLimit)))
    }

    /// `items` with titles that are `term` first, then titles that start with it, otherwise in their order. Case,
    /// accents and a leading article don't count, as in the app's search.
    static func ranked(_ items: [MediaItem], for term: String) -> [MediaItem] {
        let term = comparable(term)
        func rank(_ item: MediaItem) -> Int {
            let title = comparable(item.card.title)
            if title == term { return 0 }
            return title.hasPrefix(term) ? 1 : 2
        }
        return items.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// A title folded for comparison: lowercase, without accents or a leading article.
    private static func comparable(_ title: String) -> String {
        let folded = title.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return SampleMediaSource.sortName(folded)
    }

    /// Entities for `items`, with whichever posters load within ``posterDeadline``.
    private func entities(_ items: [MediaItem]) async -> [MediaEntity] {
        guard !items.isEmpty else { return [] }
        var posters: [String: Data] = [:]
        await withTaskGroup(of: (id: String, poster: Data?)?.self) { group in
            for item in items {
                group.addTask { [poster] in (item.id, await poster(item)) }
            }
            // Nil marks the deadline.
            group.addTask {
                try? await Task.sleep(for: Self.posterDeadline)
                return nil
            }
            var loaded = 0
            for await result in group {
                guard let result else { break }
                posters[result.id] = result.poster
                loaded += 1
                if loaded == items.count { break }
            }
            group.cancelAll()
        }
        return items.map { MediaEntity($0, poster: posters[$0.id]) }
    }

    /// Runs `body`, turning a failure into words Siri can say.
    private func translatingErrors<Value>(_ body: () async throws -> Value) async throws -> Value {
        do {
            return try await body()
        } catch {
            throw IntentError(error)
        }
    }
}

/// A small poster for Siri, Shortcuts and Spotlight.
enum PosterThumbnail {
    /// The width it's drawn at, in points. Spotlight's and Siri's thumbnails are about this size.
    static let width = 60.0

    /// A JPEG of the item's poster, decoded and encoded again by Serafin so the server's bytes never reach another
    /// process, or nil when it has no poster or it won't load.
    static func jpeg(of item: MediaItem, from artwork: Artwork?) async -> Data? {
        #if canImport(UIKit)
            guard
                let artwork,
                let source = item.source,
                let request = artwork.request(.poster, of: source, width: width, scale: 3),
                let image = try? await artwork.pipeline.image(for: request)
            else { return nil }
            return image.jpegData(compressionQuality: 0.8)
        #else
            return nil
        #endif
    }
}

/// Why Siri or Shortcuts couldn't do what was asked, in words Siri can say.
enum IntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    /// No one is signed in.
    case signedOut
    /// The app lock is on, so nothing in the library is listed.
    case locked
    /// Continue Watching and Next Up are empty.
    case nothingToContinue
    /// Anything else, with what the app would say about it.
    case failed(String)

    /// The words for an error from the library.
    init(_ error: any Error) {
        if let error = error as? IntentError {
            self = error
            return
        }
        let message = UserMessage(error)
        guard !message.needsSignIn else {
            self = .failed(message.message)
            return
        }
        self = .failed(
            String(
                localized: "\(message.title). \(message.message)",
                bundle: .module,
                comment:
                    "Two sentences in a row: a title, then what follows it, such as Can't Reach the Server. Check that the server is running. Siri says this when something fails, and VoiceOver reads it when Home's out-of-date banner appears."
            )
        )
    }

    var localizedStringResource: LocalizedStringResource {
        LocalizedStringResource("\(message)", comment: "Text from the library or the app, shown as it is.")
    }

    /// What Siri says.
    var message: String {
        switch self {
        case .signedOut:
            String(
                localized: "Sign in to your Jellyfin server in Serafin first.",
                bundle: .module,
                comment: "What Siri says when no one is signed in."
            )
        case .locked:
            String(
                localized:
                    "With Serafin's lock on, Siri and Shortcuts can't look in your library. Open Serafin to find it there.",
                bundle: .module,
                comment: "What Siri says when the app lock is on and Siri was asked to find a title."
            )
        case .nothingToContinue:
            String(
                localized: "There's nothing to continue. Start a movie or show in Serafin first.",
                bundle: .module,
                comment: "What Siri says when Continue Watching and Next Up are empty."
            )
        case .failed(let message):
            message
        }
    }
}
