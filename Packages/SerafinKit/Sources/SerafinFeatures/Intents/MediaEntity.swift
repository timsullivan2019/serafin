import AppIntents
import CoreSpotlight
import Foundation
import SerafinDesign
import UniformTypeIdentifiers

/// A movie, show or episode in the signed-in user's library, as Siri, Shortcuts and Spotlight see it.
public struct MediaEntity: AppEntity, IndexedEntity {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource(
            "Movie or Show", comment: "What Siri and Shortcuts call a movie, show or episode in the library."),
        numericFormat: LocalizedStringResource(
            "\(placeholder: .int) movies and shows",
            comment: "A number of movies and shows: in Shortcuts, and under a library's name on the Library tab.")
    )

    public static let defaultQuery = MediaEntityQuery()

    /// The item's ID on the server.
    public let id: String
    /// The title.
    let title: String
    /// What sets it apart in a list, such as "Movie · 2010" or "Caminandes · S1 E2".
    let caption: String?
    /// Whether it's a movie, a show or an episode.
    let kind: MediaCard.Kind
    /// A small JPEG of the poster, made by Serafin, or nil.
    let poster: Data?

    /// An entity for an item, with its poster if it has loaded.
    init(_ item: MediaItem, poster: Data? = nil) {
        id = item.id
        title = item.card.title
        caption = Self.caption(for: item.card)
        kind = item.card.kind
        self.poster = poster
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource("\(title)", comment: "Text from the library or the app, shown as it is."),
            subtitle: caption.map {
                LocalizedStringResource("\($0)", comment: "Text from the library or the app, shown as it is.")
            },
            image: poster.map { DisplayRepresentation.Image(data: $0) }
                ?? DisplayRepresentation.Image(systemName: kind == .movie ? "film" : "tv")
        )
    }

    /// What Spotlight shows and searches: the title, the caption and the poster.
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .movie)
        attributes.title = title
        attributes.displayName = title
        attributes.contentDescription = caption
        attributes.thumbnailData = poster
        return attributes
    }

    /// "Movie · 2010", "Show · 1984", or an episode's show and code, such as "Caminandes · S1 E2".
    static func caption(for card: MediaCard) -> String? {
        if card.kind == .episode {
            return card.eyebrowText
        }
        let kind =
            card.kind == .movie
            ? String(
                localized: "Movie", bundle: .module, comment: "The kind of a title in Siri, Shortcuts and Spotlight.")
            : String(
                localized: "Show", bundle: .module, comment: "The kind of a title in Siri, Shortcuts and Spotlight.")
        guard let year = card.year else { return kind }
        return String(
            localized: "\(kind) · \(String(year))",
            bundle: .module,
            comment: "A title's kind and year in Siri, Shortcuts and Spotlight, such as Movie · 2010."
        )
    }
}

/// Finds movies, shows and episodes in the signed-in user's library for Siri and Shortcuts.
///
/// While the app lock is on it suggests nothing and refuses to search, saying why, so Siri and Shortcuts can't list
/// the library to whoever holds the device.
public struct MediaEntityQuery: EntityStringQuery {
    @Dependency private var session: AppSession
    @Dependency private var lock: AppLock

    /// Creates the query.
    public init() {}

    public func entities(for identifiers: [MediaEntity.ID]) async throws -> [MediaEntity] {
        try await library().entities(for: identifiers)
    }

    public func entities(matching string: String) async throws -> [MediaEntity] {
        try await library().entities(matching: string)
    }

    public func suggestedEntities() async throws -> [MediaEntity] {
        // Nothing rather than an error, so the titles Shortcuts and Siri already offer are taken away.
        guard await !isLockOn() else { return [] }
        return try await library().suggestions()
    }

    @MainActor private func isLockOn() -> Bool {
        lock.isEnabled
    }

    @MainActor private func library() async throws -> IntentLibrary {
        guard !isLockOn() else { throw IntentError.locked }
        return try await IntentLibrary.current(in: session)
    }
}
