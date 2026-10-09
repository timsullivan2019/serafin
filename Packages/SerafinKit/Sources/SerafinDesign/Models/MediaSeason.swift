/// One season of a series, with its episodes in order.
public struct MediaSeason: Identifiable, Hashable, Sendable {
    /// A stable identifier for the season.
    public var id: String
    /// The ``MediaCard/id`` of the series.
    public var seriesID: String
    /// The season number, starting from 1, or 0 for Specials.
    public var number: Int
    /// The season's display name, such as "Season 1", as the server provides it.
    public var title: String
    /// The episodes, in airing order.
    public var episodes: [MediaCard]

    /// Creates a season.
    ///
    /// - Parameters:
    ///   - id: A stable identifier for the season.
    ///   - seriesID: The identifier of the series.
    ///   - number: The season number, or 0 for Specials.
    ///   - title: The season's display name.
    ///   - episodes: The episodes, in airing order.
    public init(id: String, seriesID: String, number: Int, title: String, episodes: [MediaCard]) {
        self.id = id
        self.seriesID = seriesID
        self.number = number
        self.title = title
        self.episodes = episodes
    }

    /// The season as a card, for showing it among a series' seasons.
    public var card: MediaCard {
        MediaCard(
            id: id,
            kind: .season,
            title: title,
            year: episodes.first?.year,
            isPlayed: !episodes.isEmpty && episodes.allSatisfy(\.isPlayed)
        )
    }
}
