import CoreGraphics
import Foundation
import ImageIO
import JellyfinAPI
import os

/// How the thumbnails Jellyfin makes of a video for scrubbing are laid out: a picture of the video every
/// ``interval``, each ``width`` by ``height`` pixels, packed into tiles ``columns`` across and ``rows`` down, left to
/// right and then top to bottom, the first tile numbered 0.
///
/// Jellyfin lists the sizes it made for each version of an item in the item's `Trickplay` field, keyed by the
/// version's ID and then by the thumbnail width, and serves tile `n` of a size at
/// `/Videos/{id}/Trickplay/{width}/{n}.jpg`. Each tile is a full grid, the last one too, with nothing in the places
/// past the last thumbnail (10.10's `TrickplayManager` and `SkiaEncoder.CreateTrickplayTile`). What the server says
/// is checked before use: a size it describes incompletely, or with a dimension that's not positive or past
/// ``maximumWidth``, ``maximumGrid`` or ``maximumCount``, is left out.
public struct Trickplay: Codable, Hashable, Sendable {
    /// The widest or tallest thumbnail Serafin uses, in pixels. Jellyfin makes them 320 wide unless the administrator
    /// asks for other widths.
    public static let maximumWidth = 1920
    /// The most thumbnails across or down a tile Serafin uses. Jellyfin's tiles are 10 by 10 unless the
    /// administrator changes them.
    public static let maximumGrid = 20
    /// The most thumbnails Serafin uses of one video: one a second for more than a day. Jellyfin takes one every 10
    /// seconds unless the administrator changes it.
    public static let maximumCount = 100_000

    /// The width of one thumbnail, in pixels, which also names the size on the server.
    public let width: Int
    /// The height of one thumbnail, in pixels.
    public let height: Int
    /// How many thumbnails sit across one tile.
    public let columns: Int
    /// How many thumbnails sit down one tile.
    public let rows: Int
    /// How many thumbnails there are in all.
    public let count: Int
    /// The time between one thumbnail and the next, in milliseconds.
    public let intervalMilliseconds: Int
    /// The most bits per second the tiles take as they play, as the server works it out, or nil when it doesn't
    /// say: the largest tile's size over the time its thumbnails cover.
    public let bandwidth: Int?

    /// Creates a layout, or nil when a dimension isn't positive or is larger than Serafin uses.
    public init?(
        width: Int, height: Int, columns: Int, rows: Int, count: Int, intervalMilliseconds: Int, bandwidth: Int? = nil
    ) {
        guard (1...Self.maximumWidth).contains(width), (1...Self.maximumWidth).contains(height),
            (1...Self.maximumGrid).contains(columns), (1...Self.maximumGrid).contains(rows),
            (1...Self.maximumCount).contains(count), intervalMilliseconds > 0
        else { return nil }
        self.width = width
        self.height = height
        self.columns = columns
        self.rows = rows
        self.count = count
        self.intervalMilliseconds = intervalMilliseconds
        self.bandwidth = bandwidth.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The layout the server describes, or nil when it leaves a dimension out or gives one Serafin doesn't use.
    public init?(_ info: TrickplayInfoDto) {
        guard let width = info.width, let height = info.height, let columns = info.tileWidth,
            let rows = info.tileHeight,
            let count = info.thumbnailCount, let interval = info.interval
        else { return nil }
        self.init(
            width: width, height: height, columns: columns, rows: rows, count: count, intervalMilliseconds: interval,
            bandwidth: info.bandwidth)
    }

    private enum CodingKeys: String, CodingKey {
        case width, height, columns, rows, count, intervalMilliseconds, bandwidth
    }

    /// Reads a layout saved with a download. Each dimension is held within the bounds a server's must keep to, so
    /// a damaged index can't make one Serafin doesn't use, nor lose the other downloads by failing to read.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys, in bounds: ClosedRange<Int>) throws -> Int {
            min(max(try container.decode(Int.self, forKey: key), bounds.lowerBound), bounds.upperBound)
        }
        width = try value(.width, in: 1...Self.maximumWidth)
        height = try value(.height, in: 1...Self.maximumWidth)
        columns = try value(.columns, in: 1...Self.maximumGrid)
        rows = try value(.rows, in: 1...Self.maximumGrid)
        count = try value(.count, in: 1...Self.maximumCount)
        intervalMilliseconds = try value(.intervalMilliseconds, in: 1...Int(Int32.max))
        bandwidth = try container.decodeIfPresent(Int.self, forKey: .bandwidth).flatMap { $0 > 0 ? $0 : nil }
    }

    /// The time between one thumbnail and the next.
    public var interval: Duration {
        .milliseconds(intervalMilliseconds)
    }

    /// How many thumbnails one tile holds.
    public var thumbnailsPerTile: Int {
        max(columns, 1) * max(rows, 1)
    }

    /// How many tiles there are: each one full but perhaps the last.
    public var tileCount: Int {
        (max(count, 0) + thumbnailsPerTile - 1) / thumbnailsPerTile
    }

    /// The most bytes the tiles can come to, from the server's ``bandwidth``, or nil when it doesn't say. Jellyfin
    /// works the bandwidth out from each tile's size over the time a full tile covers, so no tile is larger than that
    /// time's worth.
    public var estimatedBytes: Int? {
        guard let bandwidth else { return nil }
        let seconds = Double(tileCount * thumbnailsPerTile) * Double(intervalMilliseconds) / 1000
        let bytes = Double(bandwidth) / 8 * seconds
        return bytes < Double(Int.max) ? Int(bytes.rounded(.up)) : .max
    }

    /// Where one thumbnail is: in which tile, and in which column and row of it, each counted from 0.
    public struct Place: Hashable, Sendable {
        /// The thumbnail's place among them all.
        public let thumbnail: Int
        /// The tile it's in.
        public let tile: Int
        /// Its column in the tile, from the left.
        public let column: Int
        /// Its row in the tile, from the top.
        public let row: Int

        /// Creates a place.
        public init(thumbnail: Int, tile: Int, column: Int, row: Int) {
            self.thumbnail = thumbnail
            self.tile = tile
            self.column = column
            self.row = row
        }
    }

    /// The thumbnail that shows the video at `position`: the last one taken at or before it, as Jellyfin's web client
    /// picks it, and the last of all past the end.
    public func thumbnail(at position: Duration) -> Int {
        guard count > 0, intervalMilliseconds > 0, position > .zero else { return 0 }
        let taken = (position / .milliseconds(intervalMilliseconds)).rounded(.down)
        return Int(min(taken, Double(count - 1)))
    }

    /// Where the thumbnail numbered `thumbnail` is, the first or the last when it's out of range.
    public func place(ofThumbnail thumbnail: Int) -> Place {
        let index = min(max(thumbnail, 0), max(count - 1, 0))
        let columns = max(self.columns, 1)
        let offset = index % thumbnailsPerTile
        return Place(thumbnail: index, tile: index / thumbnailsPerTile, column: offset % columns, row: offset / columns)
    }

    /// Where the thumbnail that shows the video at `position` is.
    public func place(at position: Duration) -> Place {
        place(ofThumbnail: thumbnail(at: position))
    }

    /// The thumbnails tile `tile` holds, which are fewer than a full tile's in the last one.
    public func thumbnails(inTile tile: Int) -> Range<Int> {
        guard tile >= 0, tile < tileCount else { return 0..<0 }
        let start = tile * thumbnailsPerTile
        return start..<min(start + thumbnailsPerTile, count)
    }

    /// The part of a tile image `size` pixels large that shows the thumbnail at `place`, or nil when the image has no
    /// such part, as when it's smaller than the layout says.
    ///
    /// A tile decoded at another size than the server made it is scaled evenly from its width, so its thumbnails are
    /// found in the same proportion.
    public func rect(of place: Place, inTileOf size: CGSize) -> CGRect? {
        let fullWidth = CGFloat(max(columns, 1) * max(width, 1))
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = size.width / fullWidth
        let rect = CGRect(
            x: CGFloat(place.column * width) * scale,
            y: CGFloat(place.row * height) * scale,
            width: CGFloat(width) * scale,
            height: CGFloat(height) * scale
        )
        // A pixel of slack, for a scale that doesn't divide evenly.
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1)
        guard bounds.contains(rect) else { return nil }
        return rect.intersection(CGRect(origin: .zero, size: size))
    }

    /// The size that suits a thumbnail drawn `points` wide on a screen of `scale`: the widest no wider than it's drawn,
    /// or the narrowest when every one is wider, so the picture is sharp without loading more than it shows.
    public static func best(of layouts: [Trickplay], points: CGFloat, scale: CGFloat) -> Trickplay? {
        let pixels = points * max(scale, 1)
        let fitting = layouts.filter { CGFloat($0.width) <= pixels }
        return fitting.max { $0.width < $1.width } ?? layouts.min { $0.width < $1.width }
    }

    /// The sizes the server lists for the version `mediaSourceID` in an item's `Trickplay` field, narrowest first,
    /// leaving out any it describes incompletely. The version's ID matches with or without dashes, in either case.
    public static func layouts(
        in manifest: [String: [String: TrickplayInfoDto]]?, mediaSourceID: String
    ) -> [Trickplay] {
        let wanted = comparable(mediaSourceID)
        guard !wanted.isEmpty, let sizes = manifest?.first(where: { comparable($0.key) == wanted })?.value else {
            return []
        }
        return sizes.values.compactMap { Trickplay($0) }.sorted { $0.width < $1.width }
    }

    /// An ID as it compares, whichever way the server writes it.
    private static func comparable(_ id: String) -> String {
        id.lowercased().replacingOccurrences(of: "-", with: "")
    }
}

extension Trickplay {
    /// The most pixels a tile is decoded at: 12 megapixels, about 48 MB in memory. A larger tile, as of thumbnails
    /// made far wider than Serafin draws them, is decoded smaller in proportion, and its thumbnails found to scale.
    public static let maximumTilePixels = 12_000_000
    /// The largest tile Serafin reads, in bytes: the most the image pipeline takes from the server for any picture.
    public static let maximumTileBytes = 20 * 1024 * 1024

    /// The thumbnails in tile `tile`, cut from `data`, the tile's picture as the server sends it. Nil when `data`
    /// isn't a picture; a thumbnail the picture is too small to hold, as when it's smaller than the layout says, is
    /// left out.
    ///
    /// The tile is decoded once, and each thumbnail is a part of it rather than a copy, so they cost no more memory
    /// than the tile.
    public func thumbnails(inTile tile: Int, from data: Data) -> TrickplayTileImages? {
        let wanted = thumbnails(inTile: tile)
        guard !wanted.isEmpty, data.count <= Self.maximumTileBytes, let image = Self.decodeTile(data) else {
            return nil
        }
        let size = CGSize(width: image.width, height: image.height)
        var cut: [Int: CGImage] = [:]
        for index in wanted {
            guard let rect = rect(of: place(ofThumbnail: index), inTileOf: size),
                let thumbnail = image.cropping(to: rect.integral)
            else { continue }
            cut[index] = thumbnail
        }
        return TrickplayTileImages(tile: tile, thumbnails: cut, bytes: image.bytesPerRow * image.height)
    }

    /// `data` decoded into memory, at most ``maximumTilePixels`` large, or nil when it isn't a picture.
    private static func decodeTile(_ data: Data) -> CGImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options), CGImageSourceGetCount(source) > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0
        else { return nil }
        let longest = max(width, height)
        let pixels = Double(width) * Double(height)
        let shrink = min(1, (Double(maximumTilePixels) / pixels).squareRoot())
        // Decoded now, off whichever thread draws it, and kept, not purged, while its thumbnails are.
        let decoding =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, Int(Double(longest) * shrink)),
                kCGImageSourceCreateThumbnailWithTransform: false,
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, decoding)
    }
}

/// The thumbnails cut from one decoded tile. A `CGImage` never changes once made, so they can go from the thread that
/// decoded the tile to the one that draws them.
public struct TrickplayTileImages: @unchecked Sendable {
    /// The tile they're cut from.
    public let tile: Int
    /// The thumbnails, keyed by their place among all of the video's.
    public let thumbnails: [Int: CGImage]
    /// How much memory the decoded tile they share takes, in bytes.
    public let bytes: Int

    /// Creates a tile's thumbnails.
    public init(tile: Int, thumbnails: [Int: CGImage], bytes: Int) {
        self.tile = tile
        self.thumbnails = thumbnails
        self.bytes = bytes
    }
}

/// Where the tiles of a movie's or an episode's trickplay thumbnails come from.
public enum TrickplayTiles: Hashable, Sendable {
    /// The server, which makes them for the version `mediaSourceID` in each of `layouts`, narrowest first.
    case server(mediaSourceID: String, layouts: [Trickplay])
    /// Files saved with a download, in one size: `files[n]` is tile `n`.
    case saved(Trickplay, files: [URL])
}

/// Reads the tiles of one size of a movie's or an episode's trickplay thumbnails: from the server, through the
/// shared image pipeline with the account's `Authorization` header and its disk cache, or from the files saved with a
/// download. The player reads both the same way.
public struct TrickplayTileReader: Sendable {
    /// The size the tiles hold.
    public let layout: Trickplay
    /// Whether tiles come from the server, so fetching the ones ahead into the disk cache saves waiting later.
    public let isRemote: Bool
    private let read: @Sendable (Int) async throws -> Data?

    /// Creates a reader that reads tile `n` with `read`.
    public init(layout: Trickplay, isRemote: Bool, read: @escaping @Sendable (Int) async throws -> Data?) {
        self.layout = layout
        self.isRemote = isRemote
        self.read = read
    }

    /// The reader for the size in `tiles` that suits a thumbnail drawn `points` wide on a screen of `scale`, as
    /// ``Trickplay/best(of:points:scale:)`` picks it, or nil when there's none, or the server's has no `artwork` to
    /// load it with.
    public init?(_ tiles: TrickplayTiles, points: CGFloat, scale: CGFloat, artwork: Artwork?) {
        switch tiles {
        case .server(let mediaSourceID, let layouts):
            guard let artwork, let layout = Trickplay.best(of: layouts, points: points, scale: scale) else {
                return nil
            }
            self.init(layout: layout, isRemote: true) { index in
                try await artwork.data(trickplayTile: index, width: layout.width, mediaSourceID: mediaSourceID)
            }
        case .saved(let layout, let files):
            guard files.count == layout.tileCount else { return nil }
            self.init(layout: layout, isRemote: false) { index in
                try Self.readFile(files[index])
            }
        }
    }

    /// Tile `index`, as the server sends it or as it was saved, or nil when the layout has no such tile.
    ///
    /// - Throws: The image pipeline's error, or the file system's, when the tile can't be read.
    public func data(ofTile index: Int) async throws -> Data? {
        guard (0..<layout.tileCount).contains(index) else { return nil }
        return try await read(index)
    }

    /// The saved tile at `url`, or nil when it's larger than any tile Serafin reads.
    private static func readFile(_ url: URL) throws -> Data? {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= Trickplay.maximumTileBytes else { return nil }
        return try Data(contentsOf: url)
    }
}

/// Finds what the player's scrubber shows of a movie or an episode besides its length: the thumbnail sizes the server
/// made of each version, and the chapters.
///
/// Jellyfin includes both in `GET /Items/{id}`, whose answer has every field but a season's user data and the refresh
/// state (10.10's `DtoOptions`), so no field needs asking for. An item handed over with its `Trickplay` field already,
/// as from its detail screen, isn't asked about again, and each other item is asked about once for as long as the
/// repository lasts. Nothing here fails: a server that can't answer has no thumbnails or chapters to show.
public actor TrickplayRepository {
    private static let logger = Logger(serafinCategory: "trickplay")

    private let client: JellyfinClient
    private let userID: String
    /// The answer for each item asked about, or the request on its way.
    private var found: [String: Task<BaseItemDto?, Never>] = [:]

    /// Creates the repository for the signed-in account.
    public init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
    }

    /// `item` with its `Trickplay` and `Chapters` fields: as it is when it has them, or else as the server answers for
    /// it. An item the server can't answer for comes back as it is, and is asked about again next time.
    public func details(of item: BaseItemDto) async -> BaseItemDto {
        guard item.trickplay == nil, let id = item.id, ItemID.isPlain(id) else { return item }
        if let known = found[id] {
            return await known.value ?? item
        }
        let client = client
        let userID = userID
        let request = Task { await Self.fetch(id, userID: userID, client: client) }
        found[id] = request
        guard let answer = await request.value else {
            found[id] = nil
            return item
        }
        return answer
    }

    private static func fetch(_ itemID: String, userID: String, client: JellyfinClient) async -> BaseItemDto? {
        do {
            return try await client.send(Paths.getItem(itemID: itemID, userID: userID)).value
        } catch {
            // Nothing to show either way, so nothing to report.
            logger.debug("No trickplay or chapters: \(error.localizedDescription, privacy: .private)")
            return nil
        }
    }
}
