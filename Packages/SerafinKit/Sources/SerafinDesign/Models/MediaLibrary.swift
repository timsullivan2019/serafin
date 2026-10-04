/// One of the user's libraries on the server, such as Movies or Shows.
public struct MediaLibrary: Identifiable, Hashable, Sendable {
    /// What a library holds.
    public enum Kind: String, Hashable, Sendable {
        /// Movies.
        case movies
        /// Series and their episodes.
        case shows
    }

    /// A stable identifier for the library.
    public var id: String
    /// The name the server gives the library.
    public var name: String
    /// What the library holds.
    public var kind: Kind
    /// The library's top-level items: movies, or series.
    public var items: [MediaCard]

    /// Creates a library.
    ///
    /// - Parameters:
    ///   - id: A stable identifier for the library.
    ///   - name: The name the server gives the library.
    ///   - kind: What the library holds.
    ///   - items: The library's top-level items.
    public init(id: String, name: String, kind: Kind, items: [MediaCard]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.items = items
    }
}
