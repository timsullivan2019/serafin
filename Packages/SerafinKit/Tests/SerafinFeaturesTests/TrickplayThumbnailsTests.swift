import CoreGraphics
import Foundation
import ImageIO
import JellyfinAPI
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

/// A tile as a server sends it: a PNG `columns` by `rows` thumbnails of `width` by `height` pixels.
private func tilePicture(columns: Int, rows: Int, width: Int, height: Int) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
        CGContext(
            data: nil, width: columns * width, height: rows * height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for row in 0..<rows {
        for column in 0..<columns {
            context.setFillColor(red: CGFloat(column * 50) / 255, green: CGFloat(row * 50) / 255, blue: 0, alpha: 1)
            context.fill(CGRect(x: column * width, y: row * height, width: width, height: height))
        }
    }
    let image = try #require(context.makeImage())
    let data = NSMutableData()
    let destination = try #require(
        CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

/// Thumbnails 32 by 18 pixels, 4 by 4 to a tile, one every 10 seconds: 40 of them, in three tiles, the last part full.
private func smallLayout() throws -> Trickplay {
    try #require(Trickplay(width: 32, height: 18, columns: 4, rows: 4, count: 40, intervalMilliseconds: 10_000))
}

/// Serves a test's tiles, and notes which it was asked for.
private actor TileServer {
    private(set) var reads: [Int] = []
    private let tile: Data
    private let failing: Set<Int>

    init(tile: Data, failing: Set<Int> = []) {
        self.tile = tile
        self.failing = failing
    }

    /// Small tiles, as for ``smallLayout()``.
    init(failing: Set<Int> = []) throws {
        self.init(tile: try tilePicture(columns: 4, rows: 4, width: 32, height: 18), failing: failing)
    }

    func read(_ index: Int) throws -> Data {
        reads.append(index)
        guard !failing.contains(index) else { throw URLError(.notConnectedToInternet) }
        return tile
    }

    /// A reader of `layout`'s tiles from this server, or from files on the device when it isn't remote.
    nonisolated func reader(of layout: Trickplay, isRemote: Bool) -> TrickplayTileReader {
        TrickplayTileReader(layout: layout, isRemote: isRemote) { index in
            try await self.read(index)
        }
    }
}

/// Waits until `condition` holds, for up to five seconds.
@MainActor private func waitUntil(_ condition: () async -> Bool) async throws {
    for _ in 0..<1000 {
        if await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("Timed out waiting")
    throw CancellationError()
}

@MainActor @Suite struct TrickplayThumbnailsTests {
    @Test func nothingIsReadBeforeTheFirstDrag() async throws {
        let server = try TileServer()
        let thumbnails = TrickplayThumbnails(reader: server.reader(of: try smallLayout(), isRemote: true))
        #expect(thumbnails.thumbnail(at: .seconds(150)) == nil)
        #expect(thumbnails.scrubberThumbnails.image(.seconds(150)) == nil)
        #expect(await server.reads.isEmpty)
    }

    @Test func aDragDecodesTheTileUnderTheFingerAndItsNearerNeighbour() async throws {
        let server = try TileServer()
        let thumbnails = TrickplayThumbnails(reader: server.reader(of: try smallLayout(), isRemote: false))

        // 2:30 is thumbnail 15, the last of the first tile, so the second tile is the nearer.
        thumbnails.prepare(around: .seconds(150))
        try await waitUntil { thumbnails.tiles.keys.sorted() == [0, 1] }

        let image = try #require(thumbnails.thumbnail(at: .seconds(150)))
        #expect(image.width == 32)
        #expect(image.height == 18)
        #expect(thumbnails.thumbnail(at: .seconds(310)) !== image)
        #expect(thumbnails.scrubberThumbnails.image(.seconds(150)) != nil)
        // Read from files, so nothing further is fetched ahead.
        #expect(await server.reads.sorted() == [0, 1])
    }

    @Test func whileATileIsntLoadedTheNearestThumbnailThatIsShows() async throws {
        let server = try TileServer(failing: [2])
        let thumbnails = TrickplayThumbnails(reader: server.reader(of: try smallLayout(), isRemote: false))
        thumbnails.prepare(around: .seconds(150))
        try await waitUntil { thumbnails.tiles.keys.sorted() == [0, 1] }

        // 6:30 is thumbnail 39, in the third tile, which can't be read: the second tile's last shows.
        thumbnails.prepare(around: .seconds(390))
        try await waitUntil { await server.reads.contains(2) }

        let shown = try #require(thumbnails.thumbnail(at: .seconds(390)))
        #expect(shown === thumbnails.thumbnail(at: .seconds(310)))
    }

    @Test func aTileThatCantBeReadIsntAskedForAgainAtOnce() async throws {
        let server = try TileServer(failing: [0])
        let thumbnails = TrickplayThumbnails(reader: server.reader(of: try smallLayout(), isRemote: false))
        thumbnails.prepare(around: .seconds(150))
        try await waitUntil { thumbnails.tiles.keys.sorted() == [1] }
        try await waitUntil { await server.reads.contains(0) }

        thumbnails.prepare(around: .seconds(150))
        try await Task.sleep(for: .milliseconds(100))

        #expect(await server.reads.filter { $0 == 0 }.count == 1)
        #expect(thumbnails.tiles.keys.sorted() == [1])
    }

    @Test func theServersTilesEitherSideAreFetchedAheadWithoutDecoding() async throws {
        let server = try TileServer()
        let thumbnails = TrickplayThumbnails(reader: server.reader(of: try smallLayout(), isRemote: true))

        // 2:50 is thumbnail 17, early in the second tile: the first is the nearer, and the third is fetched ahead.
        thumbnails.prepare(around: .seconds(170))
        try await waitUntil { thumbnails.tiles.keys.sorted() == [0, 1] }
        try await waitUntil { await server.reads.contains(2) }
        try await Task.sleep(for: .milliseconds(50))

        #expect(thumbnails.tiles.keys.sorted() == [0, 1])
        #expect(await server.reads.sorted() == [0, 1, 2])
    }

    @Test func beforeTheFirstDragTheTileAtThePlaybackPositionIsFetchedWithoutDecoding() async throws {
        let server = try TileServer()
        let thumbnails = TrickplayThumbnails(reader: server.reader(of: try smallLayout(), isRemote: true))

        thumbnails.prefetch(around: .seconds(170))
        try await waitUntil { await server.reads == [1] }
        thumbnails.prefetch(around: .seconds(170))
        try await Task.sleep(for: .milliseconds(50))

        #expect(await server.reads == [1])
        #expect(thumbnails.tiles.isEmpty)
    }

    @Test func decodedTilesStayWithinTheMemoryBudget() async throws {
        let standard = try #require(
            Trickplay(width: 320, height: 180, columns: 10, rows: 10, count: 300, intervalMilliseconds: 10_000))
        let server = TileServer(tile: try tilePicture(columns: 10, rows: 10, width: 320, height: 180))
        let thumbnails = TrickplayThumbnails(reader: server.reader(of: standard, isRemote: false))
        // Two of Jellyfin's standard tiles fit.
        #expect(thumbnails.maximumTiles == 2)

        // 0:15 is early in the first tile, which has no tile before it.
        thumbnails.prepare(around: .seconds(15))
        try await waitUntil { thumbnails.tiles.keys.sorted() == [0] }
        // 33:35 is early in the third tile, so the second is the nearer, and the first, used longest ago, goes.
        thumbnails.prepare(around: .seconds(2_015))
        try await waitUntil { thumbnails.tiles.keys.sorted() == [1, 2] }
    }

    @Test func tilesOfThumbnailsMadeVeryLargeAreKeptOneAtATime() throws {
        let huge = try #require(
            Trickplay(width: 1920, height: 1080, columns: 20, rows: 20, count: 400, intervalMilliseconds: 10_000))
        let thumbnails = TrickplayThumbnails(reader: TrickplayTileReader(layout: huge, isRemote: true) { _ in nil })
        #expect(thumbnails.maximumTiles == 1)
    }

    @Test func theScrubberGetsTheThumbnailsShapeAndLoadsThemAsItsDragged() async throws {
        let server = try TileServer()
        let thumbnails = TrickplayThumbnails(reader: server.reader(of: try smallLayout(), isRemote: false))
        let scrubber = thumbnails.scrubberThumbnails
        // Both sides are CGFloat: with a Double on the right, the testing library compares the two as AnyHashable,
        // which never finds a CGFloat equal to a Double.
        #expect(scrubber.aspectRatio == CGFloat(32) / CGFloat(18))

        scrubber.prepare(.seconds(150))

        try await waitUntil { scrubber.image(.seconds(150)) != nil }
        #expect(thumbnails.tiles.keys.sorted() == [0, 1])
    }

    @Test func thumbnailsComeFromWhatsSavedOrNothing() throws {
        let layout = try smallLayout()
        let files = (0..<3).map { URL.temporaryDirectory.appending(path: "tile-\($0).jpg") }
        let saved = TrickplayThumbnails(.saved(layout, files: files), isRegular: false, scale: 3, artwork: nil)
        #expect(saved?.layout == layout)
        #expect(TrickplayThumbnails(nil, isRegular: false, scale: 3, artwork: nil) == nil)
        // The server's need something to load them with.
        let server = TrickplayTiles.server(mediaSourceID: "aaaa1111", layouts: [layout])
        #expect(TrickplayThumbnails(server, isRegular: false, scale: 3, artwork: nil) == nil)
        #expect(TrickplayThumbnails.previewBudget(isRegular: false) == 320)
        #expect(TrickplayThumbnails.previewBudget(isRegular: true) == 480)
    }
}
