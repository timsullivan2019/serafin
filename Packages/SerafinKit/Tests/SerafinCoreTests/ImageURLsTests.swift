import Foundation
import JellyfinAPI
import Nuke
import Testing

@testable import SerafinCore

private let server = URL(string: "https://media.example.com") ?? URL.temporaryDirectory
private let urls = ImageURLs(serverURL: server)

private let movie = BaseItemDto(
    backdropImageTags: ["backdrop-tag"],
    id: "aaaa1111",
    imageTags: ["Primary": "poster-tag", "Thumb": "thumb-tag", "Logo": "logo-tag"],
    type: .movie
)

/// An episode with none of its own art, so everything comes from its show.
private let bareEpisode = BaseItemDto(
    id: "bbbb2222",
    imageTags: [:],
    parentBackdropImageTags: ["show-backdrop-tag"],
    parentBackdropItemID: "show1111",
    parentLogoImageTag: "show-logo-tag",
    parentLogoItemID: "show1111",
    parentThumbImageTag: "show-thumb-tag",
    parentThumbItemID: "show1111",
    seriesID: "show1111",
    seriesPrimaryImageTag: "show-poster-tag",
    type: .episode
)

@Suite struct ImageURLsTests {
    @Test func postersAskForTheSizeTheTagAndTheQuality() throws {
        let url = try #require(urls.url(.poster, of: movie, maxWidth: 300))
        #expect(
            url.absoluteString
                == "https://media.example.com/Items/aaaa1111/Images/Primary?maxWidth=300&quality=90&tag=poster-tag")
    }

    @Test func episodesWithoutTheirOwnArtUseTheShows() throws {
        #expect(
            try #require(urls.url(.poster, of: bareEpisode, maxWidth: 300)).path() == "/Items/show1111/Images/Primary")
        #expect(
            try #require(urls.url(.landscape, of: bareEpisode, maxWidth: 600)).path() == "/Items/show1111/Images/Thumb")
        #expect(
            try #require(urls.url(.backdrop, of: bareEpisode, maxWidth: 1200)).path()
                == "/Items/show1111/Images/Backdrop")
        #expect(try #require(urls.url(.logo, of: bareEpisode, maxWidth: 400)).path() == "/Items/show1111/Images/Logo")
    }

    @Test func anEpisodesPosterIsItsShowsEvenWithAStillOfItsOwn() throws {
        var episode = bareEpisode
        episode.imageTags = ["Primary": "still-tag"]
        #expect(try #require(urls.url(.poster, of: episode, maxWidth: 300)).path() == "/Items/show1111/Images/Primary")
        episode.seriesPrimaryImageTag = nil
        #expect(try #require(urls.url(.poster, of: episode, maxWidth: 300)).path() == "/Items/bbbb2222/Images/Primary")
    }

    @Test func landscapeCardsPreferAnEpisodesOwnStill() throws {
        var episode = bareEpisode
        episode.imageTags = ["Primary": "still-tag"]
        let url = try #require(urls.url(.landscape, of: episode, maxWidth: 600))
        #expect(url.path() == "/Items/bbbb2222/Images/Primary")
        #expect(url.query()?.contains("tag=still-tag") == true)
    }

    @Test func landscapeCardsFallBackFromThumbToBackdrop() throws {
        #expect(try #require(urls.url(.landscape, of: movie, maxWidth: 600)).path() == "/Items/aaaa1111/Images/Thumb")
        var withoutThumb = movie
        withoutThumb.imageTags = ["Primary": "poster-tag"]
        #expect(
            try #require(urls.url(.landscape, of: withoutThumb, maxWidth: 600)).path()
                == "/Items/aaaa1111/Images/Backdrop")
    }

    @Test func continueWatchingPrefersThumbThenBackdropThenTheShowsBackdropThenTheStill() throws {
        var episode = bareEpisode
        episode.imageTags = ["Primary": "still-tag"]
        episode.parentThumbImageTag = nil
        episode.parentThumbItemID = nil
        // With its show's backdrop, an episode in Continue Watching shows that rather than its still.
        #expect(
            try #require(urls.url(.watching, of: episode, maxWidth: 600)).path() == "/Items/show1111/Images/Backdrop")
        episode.parentBackdropImageTags = nil
        #expect(
            try #require(urls.url(.watching, of: episode, maxWidth: 600)).path() == "/Items/bbbb2222/Images/Primary")
        #expect(try #require(urls.url(.watching, of: movie, maxWidth: 600)).path() == "/Items/aaaa1111/Images/Thumb")
    }

    @Test func continueWatchingNeverShowsAMoviesPoster() {
        var withoutLandscapeArt = movie
        withoutLandscapeArt.imageTags = ["Primary": "poster-tag"]
        withoutLandscapeArt.backdropImageTags = []
        #expect(urls.url(.watching, of: withoutLandscapeArt, maxWidth: 600) == nil)
    }

    @Test func aMoviesPosterIsNeverAStill() {
        // Only episodes use their primary image as a 16:9 still.
        var withoutLandscapeArt = movie
        withoutLandscapeArt.imageTags = ["Primary": "poster-tag"]
        withoutLandscapeArt.backdropImageTags = []
        #expect(urls.url(.landscape, of: withoutLandscapeArt, maxWidth: 600) == nil)
    }

    @Test func noArtMeansNoAddress() {
        let item = BaseItemDto(id: "cccc3333", imageTags: [:], type: .movie)
        for role in ImageRole.allCases {
            #expect(urls.url(role, of: item, maxWidth: 300) == nil)
        }
    }

    @Test(arguments: ["../../System/Info", "a/b", "id?x=1", "", "%2e%2e"])
    func idsThatCouldChangeThePathGetNoAddress(_ id: String) {
        #expect(urls.url(itemID: id, type: .primary, tag: "t", maxWidth: 300) == nil)
    }

    @Test func aServerUnderAPathKeepsIt() throws {
        let urls = ImageURLs(serverURL: try #require(URL(string: "https://example.com/jellyfin")))
        #expect(
            try #require(urls.url(.poster, of: movie, maxWidth: 300)).path()
                == "/jellyfin/Items/aaaa1111/Images/Primary")
    }
}

@Suite struct ArtworkTests {
    @Test(arguments: [
        (CGFloat(100), CGFloat(3), 300), (101, 3, 400), (0.4, 1, 100), (180, 2, 400), (390, 3, 1200),
    ])
    func widthsRoundUpToTheNextStep(points: CGFloat, scale: CGFloat, pixels: Int) {
        #expect(Artwork.pixelWidth(points: points, scale: scale) == pixels)
    }

    @Test func requestsCarryTheHeaderAndAreDecodedAtTheirWidth() throws {
        let artwork = Artwork(
            urls: urls,
            pipeline: ImagePipeline.serafin(pinning: nil, diskCacheName: nil),
            authorization: #"MediaBrowser Token="secret""#
        )
        let request = try #require(artwork.request(.poster, of: movie, width: 120, scale: 3))

        #expect(request.urlRequest?.value(forHTTPHeaderField: "Authorization") == #"MediaBrowser Token="secret""#)
        #expect(request.url?.query()?.contains("maxWidth=400") == true)
        #expect(request.url?.query()?.contains("secret") == false)
        let decodedSize = ImageRequest.ThumbnailOptions(
            size: CGSize(width: 400, height: 1600),
            unit: .pixels,
            contentMode: .aspectFit
        )
        #expect(request.thumbnail == decodedSize)
    }

    @Test func decodedImagesKeepAtMostEightyMegabytes() throws {
        let pipeline = ImagePipeline.serafin(pinning: nil, diskCacheName: nil)
        let cache = try #require(pipeline.configuration.imageCache as? ImageCache)
        #expect(cache.costLimit == 80 * 1024 * 1024)
        #expect(cache.costLimit < ImageCache.defaultCostLimit || ImageCache.defaultCostLimit <= 80 * 1024 * 1024)
    }

    @Test func noArtMeansNoRequest() {
        let artwork = Artwork(
            urls: urls, pipeline: ImagePipeline.serafin(pinning: nil, diskCacheName: nil), authorization: "x")
        #expect(artwork.request(.backdrop, of: BaseItemDto(id: "dddd4444"), width: 390, scale: 3) == nil)
    }
}

@Suite struct ProfileImageTests {
    @Test func aProfilePictureComesFromUserImageWithItsTag() throws {
        let url = try #require(urls.userImageURL(userID: "eeee5555", tag: "face-tag"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/UserImage")
        #expect(components.queryItems?.contains(URLQueryItem(name: "userId", value: "eeee5555")) == true)
        #expect(components.queryItems?.contains(URLQueryItem(name: "tag", value: "face-tag")) == true)
    }

    @Test func aUserWithNoPictureOrAnOddIDHasNoAddress() {
        #expect(urls.userImageURL(userID: "eeee5555", tag: nil) == nil)
        #expect(urls.userImageURL(userID: "eeee5555", tag: "") == nil)
        #expect(urls.userImageURL(userID: "../Users", tag: "face-tag") == nil)
    }

    @Test func theRequestCarriesTheHeaderNotTheToken() throws {
        let artwork = Artwork(
            urls: urls, pipeline: ImagePipeline.serafin(pinning: nil, diskCacheName: nil), authorization: "header")
        let request = try #require(artwork.request(userImage: "eeee5555", tag: "face-tag", width: 28, scale: 3))
        #expect(request.urlRequest?.value(forHTTPHeaderField: "Authorization") == "header")
        #expect(request.url?.query?.contains("api_key") == false)
    }
}
