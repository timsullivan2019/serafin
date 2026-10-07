import CoreGraphics

/// Offline media for previews and tests: twelve movies and four series with their seasons and episodes.
///
/// Every title is public domain or an openly licensed film: Blender Studio's open movies and classic features
/// from the Internet Archive. Series are built from the public-domain books of Lewis Carroll, L. Frank Baum and
/// Arthur Conan Doyle, plus Blender's Caminandes shorts. Overviews are written for Serafin. Playback state is
/// varied on purpose so that progress bars, played badges and favourites all appear.
public enum MockMedia {
    /// Twelve movies with a mix of unwatched, in-progress, played and favourite states.
    public static let movies: [MediaCard] = [
        MediaCard(
            id: "movie-big-buck-bunny", kind: .movie, title: "Big Buck Bunny", year: 2008,
            runtime: .seconds(10 * 60), isFavourite: true,
            overview: "A gentle giant of a rabbit has his quiet morning spoiled by three bullying rodents, and plots "
                + "an elaborate revenge."
        ),
        MediaCard(
            id: "movie-sintel", kind: .movie, title: "Sintel", year: 2010,
            runtime: .seconds(15 * 60), progress: 0.4,
            overview: "A young woman crosses a frozen wilderness in search of the baby dragon she once rescued."
        ),
        MediaCard(
            id: "movie-tears-of-steel", kind: .movie, title: "Tears of Steel", year: 2012,
            runtime: .seconds(12 * 60), isPlayed: true,
            overview: "In a ruined Amsterdam, scientists and fighters try to replay one painful moment from the "
                + "past to stop an army of machines."
        ),
        MediaCard(
            id: "movie-elephants-dream", kind: .movie, title: "Elephants Dream", year: 2006,
            runtime: .seconds(11 * 60),
            overview: "Two men wander an endless, shifting machine world, one of them sure it is all his to command."
        ),
        MediaCard(
            id: "movie-cosmos-laundromat", kind: .movie, title: "Cosmos Laundromat", year: 2015,
            runtime: .seconds(12 * 60), isFavourite: true,
            overview: "A despairing sheep on a barren island is offered a strange bargain: any life he wants."
        ),
        MediaCard(
            id: "movie-spring", kind: .movie, title: "Spring", year: 2019,
            runtime: .seconds(8 * 60), progress: 0.75,
            overview: "A shepherd girl and her dog face ancient spirits to bring the season back to the mountains."
        ),
        MediaCard(
            id: "movie-sprite-fright", kind: .movie, title: "Sprite Fright", year: 2021,
            runtime: .seconds(10 * 60),
            overview: "A group of teenagers on a trip to the woods learn that the local mushroom folk are not as "
                + "friendly as they look."
        ),
        MediaCard(
            id: "movie-night-of-the-living-dead", kind: .movie, title: "Night of the Living Dead", year: 1968,
            runtime: .seconds(96 * 60), rating: "NR", isPlayed: true,
            overview: "Strangers barricade themselves in a Pennsylvania farmhouse as the dead rise and close in."
        ),
        MediaCard(
            id: "movie-the-general", kind: .movie, title: "The General", year: 1926,
            runtime: .seconds(79 * 60), rating: "NR", isFavourite: true,
            overview: "A railway engineer chases his stolen locomotive, and the woman he loves, deep behind enemy "
                + "lines."
        ),
        MediaCard(
            id: "movie-nosferatu", kind: .movie, title: "Nosferatu", year: 1922,
            runtime: .seconds(94 * 60), rating: "NR",
            overview: "An estate agent travels to a remote castle to close a sale, and brings its plague-bearing "
                + "owner home with him."
        ),
        MediaCard(
            id: "movie-his-girl-friday", kind: .movie, title: "His Girl Friday", year: 1940,
            runtime: .seconds(92 * 60), rating: "NR",
            overview: "A newspaper editor schemes to keep his star reporter, and former wife, from remarrying by "
                + "handing her one last story."
        ),
        MediaCard(
            id: "movie-charade", kind: .movie, title: "Charade", year: 1963,
            runtime: .seconds(113 * 60), rating: "NR", progress: 0.2,
            overview: "After her husband is murdered, a widow in Paris is pursued by men who want the fortune he hid."
        ),
    ]

    /// Four series. Their seasons and episodes come from ``seasons(of:)``.
    public static let series: [MediaCard] = [
        caminandes.card,
        sherlockHolmes.card,
        alice.card,
        oz.card,
    ]

    /// Two collections: Blender's open movies and the silent classics.
    public static let collections: [MediaCard] = [
        MediaCard(
            id: "collection-blender-open-movies", kind: .collection, title: "Blender Open Movies",
            overview: "Every open movie from Blender Studio, from Elephants Dream to Sprite Fright."
        ),
        MediaCard(
            id: "collection-silent-classics", kind: .collection, title: "Silent Classics",
            overview: "Two landmarks of the silent era."
        ),
    ]

    /// The movies in a collection from ``collections``, in release order, or an empty array for anything else.
    ///
    /// - Parameter collection: A collection card.
    public static func members(of collection: MediaCard) -> [MediaCard] {
        let ids: [String] =
            switch collection.id {
            case "collection-blender-open-movies":
                [
                    "movie-elephants-dream", "movie-big-buck-bunny", "movie-sintel", "movie-tears-of-steel",
                    "movie-cosmos-laundromat", "movie-spring", "movie-sprite-fright",
                ]
            case "collection-silent-classics": ["movie-nosferatu", "movie-the-general"]
            default: []
            }
        return ids.compactMap { id in movies.first { $0.id == id } }
    }

    /// Every episode of every series, in series, season and episode order.
    public static let episodes: [MediaCard] = allSeries.flatMap { $0.seasons.flatMap(\.episodes) }

    /// The seasons of a series from ``series``, in order, or an empty array for anything else.
    ///
    /// - Parameter series: A series card.
    public static func seasons(of series: MediaCard) -> [MediaSeason] {
        allSeries.first { $0.card.id == series.id }?.seasons ?? []
    }

    /// The series card for an episode, or nil for anything that is not an episode from ``episodes``.
    ///
    /// - Parameter episode: An episode card.
    public static func series(of episode: MediaCard) -> MediaCard? {
        series.first { $0.id == episode.episode?.seriesID }
    }

    /// The generated 2:3 poster for a card. The same card always gets the same poster.
    ///
    /// - Parameter card: Any card.
    public static func poster(for card: MediaCard) -> CGImage? {
        PlaceholderArt.poster(seed: stableSeed(for: card.id))
    }

    /// The generated 16:9 backdrop for a card, which also serves as an episode thumbnail.
    ///
    /// - Parameter card: Any card.
    public static func backdrop(for card: MediaCard) -> CGImage? {
        PlaceholderArt.backdrop(seed: stableSeed(for: card.id))
    }

    /// An FNV-1a hash of `id`. Unlike `hashValue`, it is the same on every launch.
    static func stableSeed(for id: String) -> Int {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return Int(truncatingIfNeeded: hash)
    }
}

// MARK: - Series

extension MockMedia {
    /// A series card with its seasons, kept together while the fixtures are built.
    struct MockSeries {
        var card: MediaCard
        var seasons: [MediaSeason]
    }

    static let allSeries = [caminandes, sherlockHolmes, alice, oz]

    static let caminandes = makeSeries(
        id: "series-caminandes", title: "Caminandes", year: 2013, minutes: 3,
        overview: "A stubborn llama in Patagonia keeps finding new obstacles between him and the greener grass.",
        seasons: [
            ("Season 1", ["Llama Drama", "Gran Dillama", "Llamigos"])
        ],
        played: 1
    )

    static let sherlockHolmes = makeSeries(
        id: "series-sherlock-holmes", title: "Sherlock Holmes", year: 1892, minutes: 50,
        overview: "The consulting detective of Baker Street and his friend Dr Watson take on London's strangest "
            + "cases.",
        seasons: [
            (
                "The Adventures",
                [
                    "A Scandal in Bohemia", "The Red-Headed League", "A Case of Identity",
                    "The Boscombe Valley Mystery", "The Five Orange Pips", "The Man with the Twisted Lip",
                ]
            ),
            ("The Memoirs", ["Silver Blaze", "The Yellow Face", "The Musgrave Ritual", "The Final Problem"]),
        ],
        played: 3,
        inProgress: 0.55,
        isFavourite: true
    )

    static let alice = makeSeries(
        id: "series-alice", title: "Alice's Adventures in Wonderland", year: 1865, minutes: 25,
        overview: "A curious girl follows a white rabbit underground, into a world where nothing behaves as it "
            + "should.",
        seasons: [
            (
                "Season 1",
                [
                    "Down the Rabbit-Hole", "The Pool of Tears", "A Caucus-Race and a Long Tale",
                    "The Rabbit Sends in a Little Bill", "Advice from a Caterpillar", "Pig and Pepper",
                ]
            )
        ],
        played: 2
    )

    static let oz = makeSeries(
        id: "series-oz", title: "The Wonderful Wizard of Oz", year: 1900, minutes: 25,
        overview: "Swept away by a cyclone, a Kansas girl follows a yellow brick road to the one wizard who can "
            + "send her home.",
        seasons: [
            (
                "Season 1",
                [
                    "The Cyclone", "The Council with the Munchkins", "How Dorothy Saved the Scarecrow",
                    "The Road Through the Forest", "The Rescue of the Tin Woodman", "The Cowardly Lion",
                ]
            )
        ],
        played: 0
    )

    /// Builds a series whose first `played` episodes are played and whose next episode is `inProgress`
    /// watched, when given.
    private static func makeSeries(
        id: String,
        title: String,
        year: Int,
        minutes: Int,
        overview: String,
        seasons seasonTitles: [(String, [String])],
        played: Int,
        inProgress: Double? = nil,
        isFavourite: Bool = false
    ) -> MockSeries {
        var order = 0
        let seasons = seasonTitles.enumerated().map { seasonIndex, season in
            let seasonNumber = seasonIndex + 1
            let episodes = season.1.enumerated().map { episodeIndex, episodeTitle in
                defer { order += 1 }
                return MediaCard(
                    id: "\(id)-s\(seasonNumber)e\(episodeIndex + 1)",
                    kind: .episode,
                    title: episodeTitle,
                    year: year,
                    runtime: .seconds(minutes * 60),
                    progress: order == played ? inProgress ?? 0 : 0,
                    isPlayed: order < played,
                    episode: MediaCard.EpisodeInfo(
                        seriesID: id,
                        seriesTitle: title,
                        seasonNumber: seasonNumber,
                        episodeNumber: episodeIndex + 1
                    )
                )
            }
            return MediaSeason(
                id: "\(id)-s\(seasonNumber)",
                seriesID: id,
                number: seasonNumber,
                title: season.0,
                episodes: episodes
            )
        }
        let card = MediaCard(
            id: id,
            kind: .series,
            title: title,
            year: year,
            runtime: .seconds(minutes * 60),
            isFavourite: isFavourite,
            overview: overview
        )
        return MockSeries(card: card, seasons: seasons)
    }
}
