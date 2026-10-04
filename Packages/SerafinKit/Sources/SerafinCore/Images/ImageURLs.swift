import Foundation
import JellyfinAPI

/// Where an image is drawn, which decides which of an item's images suits it.
public enum ImageRole: Hashable, Sendable, CaseIterable {
    /// A 2:3 poster: the item's primary image, or its show's for an episode or season.
    case poster
    /// A 16:9 card: an episode's still, otherwise a thumb, otherwise a backdrop, falling back to the show's.
    case landscape
    /// The full-bleed art behind a detail screen: the item's backdrop, otherwise its show's.
    case backdrop
    /// The title logo: the item's own, otherwise its show's.
    case logo
}

/// Builds the addresses of item images on one server, sized for where they are drawn.
///
/// Episodes and seasons without their own art use their show's, so every card has something to show. Item IDs and
/// tags come from the server and are untrusted: an ID that is not plain letters, digits and dashes gets no URL.
public struct ImageURLs: Hashable, Sendable {
    /// The JPEG quality Serafin asks for, a balance of sharpness and size.
    public static let defaultQuality = 90

    /// The server the images come from.
    public let serverURL: URL

    /// Creates the builder for a server.
    public init(serverURL: URL) {
        self.serverURL = serverURL
    }

    /// The address of `item`'s image for `role`, or nil when neither the item nor its show has one.
    ///
    /// - Parameters:
    ///   - role: Where the image is drawn.
    ///   - item: The item.
    ///   - maxWidth: The width to ask the server for, in pixels.
    ///   - quality: The JPEG quality to ask for.
    public func url(_ role: ImageRole, of item: BaseItemDto, maxWidth: Int, quality: Int = defaultQuality) -> URL? {
        guard let source = Self.source(role, of: item) else { return nil }
        return url(itemID: source.itemID, type: source.type, tag: source.tag, maxWidth: maxWidth, quality: quality)
    }

    /// The address of one image, or nil when `itemID` is not a plain ID.
    ///
    /// - Parameters:
    ///   - itemID: The item that has the image.
    ///   - type: Which of its images.
    ///   - tag: The image's tag, which changes when the image does, so caches never serve a stale one.
    ///   - maxWidth: The width to ask the server for, in pixels.
    ///   - quality: The JPEG quality to ask for.
    public func url(itemID: String, type: ImageType, tag: String?, maxWidth: Int, quality: Int = defaultQuality) -> URL?
    {
        guard Self.isPlainID(itemID) else { return nil }
        var components = URLComponents(
            url: serverURL.appending(path: "Items/\(itemID)/Images/\(type.rawValue)"),
            resolvingAgainstBaseURL: false
        )
        var query = [
            URLQueryItem(name: "maxWidth", value: String(max(1, maxWidth))),
            URLQueryItem(name: "quality", value: String(min(max(quality, 1), 100))),
        ]
        if let tag, !tag.isEmpty {
            query.append(URLQueryItem(name: "tag", value: tag))
        }
        components?.queryItems = query
        return components?.url
    }

    /// One image of one item.
    struct Source: Equatable {
        let itemID: String
        let type: ImageType
        let tag: String
    }

    /// Which image suits `role` for `item`, trying the item's own images before its show's.
    static func source(_ role: ImageRole, of item: BaseItemDto) -> Source? {
        let candidates: [Source?]
        switch role {
        case .poster:
            candidates = [
                own(.primary, of: item),
                source(item.seriesID, .primary, item.seriesPrimaryImageTag),
            ]
        case .landscape:
            candidates = [
                item.type == .episode ? own(.primary, of: item) : nil,
                own(.thumb, of: item),
                source(item.parentThumbItemID, .thumb, item.parentThumbImageTag),
                source(item.seriesID, .thumb, item.seriesThumbImageTag),
                ownBackdrop(of: item),
                source(item.parentBackdropItemID, .backdrop, item.parentBackdropImageTags?.first),
            ]
        case .backdrop:
            candidates = [
                ownBackdrop(of: item),
                source(item.parentBackdropItemID, .backdrop, item.parentBackdropImageTags?.first),
            ]
        case .logo:
            candidates = [
                own(.logo, of: item),
                source(item.parentLogoItemID, .logo, item.parentLogoImageTag),
            ]
        }
        return candidates.lazy.compactMap { $0 }.first
    }

    private static func own(_ type: ImageType, of item: BaseItemDto) -> Source? {
        source(item.id, type, item.imageTags?[type.rawValue])
    }

    private static func ownBackdrop(of item: BaseItemDto) -> Source? {
        source(item.id, .backdrop, item.backdropImageTags?.first)
    }

    private static func source(_ itemID: String?, _ type: ImageType, _ tag: String?) -> Source? {
        guard let itemID, !itemID.isEmpty, let tag, !tag.isEmpty else { return nil }
        return Source(itemID: itemID, type: type, tag: tag)
    }

    /// Whether `id` is the kind of ID Jellyfin issues: letters, digits and dashes, nothing that could change the
    /// path.
    static func isPlainID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
