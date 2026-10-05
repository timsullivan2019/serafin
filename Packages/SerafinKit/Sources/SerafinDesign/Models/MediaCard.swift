/// A movie, series, season, episode or collection, in the shape Serafin's cards and headers display it.
///
/// Components in SerafinDesign render from this plain value, never from server models, so every one of them
/// previews offline. SerafinFeatures maps the server's items into it.
public struct MediaCard: Identifiable, Hashable, Sendable {
    /// What kind of item a card shows.
    public enum Kind: String, Hashable, Sendable {
        /// A feature or short film.
        case movie
        /// A whole series.
        case series
        /// One season of a series.
        case season
        /// One episode of a series.
        case episode
        /// A collection of movies or shows, such as a film series, made on the server.
        case collection
    }

    /// Where an episode sits within its series.
    public struct EpisodeInfo: Hashable, Sendable {
        /// The ``MediaCard/id`` of the series the episode belongs to.
        public var seriesID: String
        /// The series title, shown above the episode title.
        public var seriesTitle: String
        /// The season number, starting from 1.
        public var seasonNumber: Int
        /// The episode number within the season, starting from 1.
        public var episodeNumber: Int

        /// Creates the series details for an episode.
        public init(seriesID: String, seriesTitle: String, seasonNumber: Int, episodeNumber: Int) {
            self.seriesID = seriesID
            self.seriesTitle = seriesTitle
            self.seasonNumber = seasonNumber
            self.episodeNumber = episodeNumber
        }
    }

    /// A stable identifier, unique across movies, series and episodes.
    public var id: String
    /// What kind of item this is.
    public var kind: Kind
    /// The title of the movie, series or episode.
    public var title: String
    /// The release year, or the year a series first aired.
    public var year: Int?
    /// The running time. For a series, the length of a typical episode.
    public var runtime: Duration?
    /// The age rating as the server provides it, such as "PG-13" or "NR".
    public var rating: String?
    /// How much has been watched, from 0 for not started to 1 for finished.
    public var progress: Double
    /// Whether the item is marked as played.
    public var isPlayed: Bool
    /// Whether the item is marked as a favourite.
    public var isFavourite: Bool
    /// A short description, shown as plain text.
    public var overview: String?
    /// Series and season details, present for episodes only.
    public var episode: EpisodeInfo?

    /// Creates a card.
    ///
    /// - Parameters:
    ///   - id: A stable identifier, unique across all items.
    ///   - kind: What kind of item this is.
    ///   - title: The title.
    ///   - year: The release year.
    ///   - runtime: The running time.
    ///   - rating: The age rating.
    ///   - progress: How much has been watched, clamped to 0...1.
    ///   - isPlayed: Whether the item is marked as played.
    ///   - isFavourite: Whether the item is marked as a favourite.
    ///   - overview: A short description.
    ///   - episode: Series and season details for an episode.
    public init(
        id: String,
        kind: Kind,
        title: String,
        year: Int? = nil,
        runtime: Duration? = nil,
        rating: String? = nil,
        progress: Double = 0,
        isPlayed: Bool = false,
        isFavourite: Bool = false,
        overview: String? = nil,
        episode: EpisodeInfo? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.year = year
        self.runtime = runtime
        self.rating = rating
        self.progress = min(max(progress, 0), 1)
        self.isPlayed = isPlayed
        self.isFavourite = isFavourite
        self.overview = overview
        self.episode = episode
    }

    /// Whether playback has started and not finished, which puts the item in Continue Watching.
    public var isInProgress: Bool {
        progress > 0 && progress < 1
    }
}
