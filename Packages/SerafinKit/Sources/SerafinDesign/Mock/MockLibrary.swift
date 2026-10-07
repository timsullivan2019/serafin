/// The rows and libraries of a typical home screen, built from ``MockMedia``.
public enum MockLibrary {
    /// Movies and episodes that have been started but not finished, in fixture order.
    public static let continueWatching: [MediaCard] = (MockMedia.movies + MockMedia.episodes).filter(\.isInProgress)

    /// For each series that has been started, the first episode not yet played or started.
    public static let nextUp: [MediaCard] = MockMedia.series.compactMap { series in
        let episodes = MockMedia.seasons(of: series).flatMap(\.episodes)
        guard episodes.contains(where: \.isPlayed) else { return nil }
        return episodes.first { !$0.isPlayed && $0.progress == 0 }
    }

    /// Recently added movies and series, newest first.
    public static let latest: [MediaCard] = [
        "movie-sprite-fright",
        "series-caminandes",
        "movie-spring",
        "movie-cosmos-laundromat",
        "series-sherlock-holmes",
        "movie-tears-of-steel",
    ]
    .compactMap { id in (MockMedia.movies + MockMedia.series).first { $0.id == id } }

    /// Home's featured items as a server with some history would pick them: the latest started item, the first Next
    /// Up episode, then the newest additions.
    public static let hero: [HeroItem] = {
        var seen: Set<String> = []
        let picks = Array(continueWatching.prefix(1)) + Array(nextUp.prefix(1)) + latest
        return picks.filter { seen.insert($0.id).inserted }.prefix(4).map { HeroItem(card: $0) }
    }()

    /// The Movies and Shows libraries.
    public static let libraries: [MediaLibrary] = [
        MediaLibrary(id: "library-movies", name: "Movies", kind: .movies, items: MockMedia.movies),
        MediaLibrary(id: "library-shows", name: "Shows", kind: .shows, items: MockMedia.series),
    ]
}
