import CoreGraphics
import Foundation
import JellyfinAPI
import Nuke

/// Loads item images for one signed-in account through the app's shared image pipeline.
///
/// Every request asks the server for an image as wide as the view that shows it, carries the account's
/// `Authorization` header rather than a token in the URL, and is decoded no larger than that width even if the
/// server sends more.
public struct Artwork: Sendable {
    /// Requested widths are rounded up to a multiple of this many pixels, so nearby sizes share the cache.
    static let widthStep = 100

    /// Builds the image addresses on the account's server.
    public let urls: ImageURLs
    /// The pipeline every image loads through.
    public let pipeline: ImagePipeline
    /// The account's `Authorization` header.
    let authorization: String

    init(urls: ImageURLs, pipeline: ImagePipeline, authorization: String) {
        self.urls = urls
        self.pipeline = pipeline
        self.authorization = authorization
    }

    /// The request for `item`'s image in `role`, drawn `width` points wide on a screen of `scale`, or nil when the
    /// item and its show have no such image.
    public func request(_ role: ImageRole, of item: BaseItemDto, width: CGFloat, scale: CGFloat) -> ImageRequest? {
        let pixels = Self.pixelWidth(points: width, scale: scale)
        return request(urls.url(role, of: item, maxWidth: pixels), pixels: pixels)
    }

    /// The request for a cast or crew member's photo, drawn `width` points wide on a screen of `scale`, or nil when
    /// the server has none.
    public func request(person: BaseItemPerson, width: CGFloat, scale: CGFloat) -> ImageRequest? {
        guard let id = person.id, let tag = person.primaryImageTag else { return nil }
        let pixels = Self.pixelWidth(points: width, scale: scale)
        return request(urls.url(itemID: id, type: .primary, tag: tag, maxWidth: pixels), pixels: pixels)
    }

    /// The request for a user's profile picture, drawn `width` points wide on a screen of `scale`, or nil when the
    /// user has none. The server sends the picture at its own size; it's decoded no larger than the view.
    public func request(userImage userID: String, tag: String?, width: CGFloat, scale: CGFloat) -> ImageRequest? {
        request(urls.userImageURL(userID: userID, tag: tag), pixels: Self.pixelWidth(points: width, scale: scale))
    }

    private func request(_ url: URL?, pixels: Int) -> ImageRequest? {
        guard let url else { return nil }
        var urlRequest = URLRequest(url: url)
        urlRequest.setValue(authorization, forHTTPHeaderField: "Authorization")
        var request = ImageRequest(urlRequest: urlRequest)
        // A box as wide as asked for and taller than any poster, so only the width limits the decoded size.
        request.thumbnail = ImageRequest.ThumbnailOptions(
            size: CGSize(width: pixels, height: pixels * 4),
            unit: .pixels,
            contentMode: .aspectFit
        )
        return request
    }

    /// The width in pixels to ask for: `points` at `scale`, rounded up to the next ``widthStep``.
    static func pixelWidth(points: CGFloat, scale: CGFloat) -> Int {
        let exact = max(1, Int((points * max(scale, 1)).rounded(.up)))
        return (exact + widthStep - 1) / widthStep * widthStep
    }
}

extension ImagePipeline {
    /// The most image data the disk cache keeps.
    nonisolated static let diskCacheLimit = 200 * 1024 * 1024
    /// The most memory decoded images keep, about 80 posters. Nuke's own limit is 15% of the device's memory, up to
    /// 768 MB, which ten minutes of browsing a large library fills. Images that drop out decode again from the disk
    /// cache, already sized for their views.
    nonisolated static let memoryCacheLimit = 80 * 1024 * 1024
    /// The largest image download allowed. Sized images are far smaller; this stops a server sending something huge.
    nonisolated static let responseLimit = 20 * 1024 * 1024
    /// The name of the image disk cache's folder in Caches.
    nonisolated static let diskCacheName = "app.getserafin.serafin.images"

    /// The pipeline Serafin loads every image through.
    ///
    /// - Parameters:
    ///   - pinning: Accepts the user's pinned certificates, as for every other request.
    ///   - diskCacheName: The folder in Caches for the 200 MB disk cache, or nil for none, as in tests.
    ///   - sessionConfiguration: The `URLSession` configuration. It is ephemeral, since the disk cache does the
    ///     caching; tests pass one with a stub protocol.
    nonisolated static func serafin(
        pinning: PinningDelegate?,
        diskCacheName: String? = ImagePipeline.diskCacheName,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) -> ImagePipeline {
        let loader = DataLoader(configuration: sessionConfiguration)
        loader.delegate = pinning
        var configuration = ImagePipeline.Configuration(dataLoader: loader)
        configuration.imageCache = ImageCache(costLimit: memoryCacheLimit)
        if let diskCacheName, let cache = try? DataCache(name: diskCacheName) {
            cache.sizeLimit = diskCacheLimit
            configuration.dataCache = cache
        }
        configuration.maximumResponseDataSize = responseLimit
        return ImagePipeline(configuration: configuration)
    }
}
