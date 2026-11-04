import CoreGraphics
import Foundation
import ImageIO
import JellyfinAPI
import Nuke
import Testing

@testable import SerafinCore

/// Jellyfin's standard thumbnails: 320 by 180 pixels, one every 10 seconds, 10 by 10 to a tile, for a film of an hour
/// and a half.
private let standard = Trickplay(
    width: 320, height: 180, columns: 10, rows: 10, count: 540, intervalMilliseconds: 10_000)
/// Thumbnails an administrator asked for wider and more often, 5 by 5 to a tile, for a four-minute short.
private let custom = Trickplay(width: 480, height: 270, columns: 5, rows: 5, count: 60, intervalMilliseconds: 4_000)

/// An ID shaped like Jellyfin's, since nothing else is asked for.
private let movieID = "0b82ed8e9f1daed4e2a44e4d233e29b4"

/// How the server lists a size of thumbnails in an item's `Trickplay` field.
private func info(width: Int, bandwidth: Int? = nil) -> TrickplayInfoDto {
    TrickplayInfoDto(
        bandwidth: bandwidth, height: width * 9 / 16, interval: 10_000, thumbnailCount: 540, tileHeight: 10,
        tileWidth: 10, width: width)
}

/// A tile as a server sends it: a PNG `columns` by `rows` thumbnails of `width` by `height` pixels, each filled with a
/// colour from its place, red rising 50 a column and green 50 a row, so a test can tell which one it has.
private func tilePicture(columns: Int, rows: Int, width: Int, height: Int) throws -> Data {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(
        CGContext(
            data: nil, width: columns * width, height: rows * height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    for row in 0..<rows {
        for column in 0..<columns {
            context.setFillColor(red: CGFloat(column * 50) / 255, green: CGFloat(row * 50) / 255, blue: 0, alpha: 1)
            // Core Graphics counts rows up from the bottom.
            context.fill(CGRect(x: column * width, y: (rows - 1 - row) * height, width: width, height: height))
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

/// The red and green in the middle of `image`, each from 0 to 255.
private func middleColour(of image: CGImage) throws -> (red: Int, green: Int) {
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    var pixel = [UInt8](repeating: 0, count: 4)
    let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
        guard
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        // Drawn so that the image's middle pixel lands on the context's only one.
        context.draw(
            image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        return true
    }
    #expect(drawn)
    return (Int(pixel[0]), Int(pixel[1]))
}

/// A client signed in on a stubbed server at `host`.
private func trickplayClient(on host: String) throws -> JellyfinClient {
    let configuration = JellyfinClient.Configuration(
        url: try #require(URL(string: "https://\(host)")),
        accessToken: "token-1",
        client: "Serafin",
        deviceName: "iPhone",
        deviceID: "device-1",
        version: "0.1.0"
    )
    return JellyfinClient(configuration: configuration, sessionConfiguration: StubURLProtocol.configuration())
}

/// Loads pictures from a stubbed server at `host`, with the header a signed-in account sends.
private func stubArtwork(on host: String) throws -> Artwork {
    Artwork(
        urls: ImageURLs(serverURL: try #require(URL(string: "https://\(host)"))),
        pipeline: ImagePipeline.serafin(
            pinning: nil, diskCacheName: nil, sessionConfiguration: StubURLProtocol.configuration()),
        authorization: #"MediaBrowser Token="secret""#,
        serverID: "server-1"
    )
}

@Suite struct TrickplayLayoutTests {
    @Test func aPositionFindsTheLastThumbnailTakenAtOrBeforeIt() throws {
        let layout = try #require(standard)
        #expect(layout.thumbnailsPerTile == 100)
        #expect(layout.tileCount == 6)
        #expect(layout.interval == .seconds(10))
        // 20:34 is 123.4 intervals in: thumbnail 123, the 24th of the second tile.
        #expect(layout.place(at: .seconds(1234)) == Trickplay.Place(thumbnail: 123, tile: 1, column: 3, row: 2))
        #expect(layout.thumbnail(at: .milliseconds(9_999)) == 0)
        #expect(layout.thumbnail(at: .seconds(10)) == 1)
    }

    @Test func positionsBeforeTheStartOrPastTheEndShowTheFirstOrTheLast() throws {
        let layout = try #require(standard)
        #expect(layout.thumbnail(at: .zero) == 0)
        #expect(layout.thumbnail(at: .seconds(-30)) == 0)
        #expect(layout.thumbnail(at: .seconds(100_000)) == 539)
        #expect(layout.place(ofThumbnail: 539) == Trickplay.Place(thumbnail: 539, tile: 5, column: 9, row: 3))
        #expect(layout.place(ofThumbnail: 1_000) == layout.place(ofThumbnail: 539))
        #expect(layout.place(ofThumbnail: -4) == Trickplay.Place(thumbnail: 0, tile: 0, column: 0, row: 0))
    }

    @Test func theLastTileHoldsWhatsLeft() throws {
        let layout = try #require(standard)
        #expect(layout.thumbnails(inTile: 0) == 0..<100)
        #expect(layout.thumbnails(inTile: 5) == 500..<540)
        #expect(layout.thumbnails(inTile: 6).isEmpty)
        #expect(layout.thumbnails(inTile: -1).isEmpty)
    }

    @Test func aThumbnailIsFoundInItsTileByColumnAndRow() throws {
        let layout = try #require(standard)
        let place = layout.place(at: .seconds(1234))
        let rect = layout.rect(of: place, inTileOf: CGSize(width: 3200, height: 1800))
        #expect(rect == CGRect(x: 960, y: 360, width: 320, height: 180))
    }

    @Test func anotherGridAndIntervalWorkTheSameWay() throws {
        let layout = try #require(custom)
        #expect(layout.tileCount == 3)
        // 2:30 is 37.5 intervals of four seconds in: the 13th thumbnail of the second tile.
        let place = layout.place(at: .seconds(150))
        #expect(place == Trickplay.Place(thumbnail: 37, tile: 1, column: 2, row: 2))
        #expect(
            layout.rect(of: place, inTileOf: CGSize(width: 2400, height: 1350))
                == CGRect(x: 960, y: 540, width: 480, height: 270))
    }

    @Test func aTileDecodedSmallerHasItsThumbnailsToScale() throws {
        let layout = try #require(custom)
        let place = Trickplay.Place(thumbnail: 12, tile: 0, column: 2, row: 2)
        #expect(
            layout.rect(of: place, inTileOf: CGSize(width: 1200, height: 675))
                == CGRect(x: 480, y: 270, width: 240, height: 135))
    }

    @Test func aTileSmallerThanTheLayoutSaysHasNoPlaceForThumbnailsPastIt() throws {
        let layout = try #require(custom)
        let corner = Trickplay.Place(thumbnail: 24, tile: 0, column: 4, row: 4)
        // As wide as the layout says, but only three rows tall.
        #expect(layout.rect(of: corner, inTileOf: CGSize(width: 2400, height: 810)) == nil)
        #expect(layout.rect(of: corner, inTileOf: .zero) == nil)
        let first = Trickplay.Place(thumbnail: 0, tile: 0, column: 0, row: 0)
        #expect(layout.rect(of: first, inTileOf: CGSize(width: 2400, height: 810)) != nil)
    }

    @Test func aLayoutTheServerDescribesBadlyIsntUsed() {
        #expect(
            Trickplay(width: 0, height: 180, columns: 10, rows: 10, count: 540, intervalMilliseconds: 10_000) == nil)
        #expect(
            Trickplay(width: 1921, height: 180, columns: 10, rows: 10, count: 540, intervalMilliseconds: 10_000) == nil)
        #expect(
            Trickplay(width: 320, height: -1, columns: 10, rows: 10, count: 540, intervalMilliseconds: 10_000) == nil)
        #expect(
            Trickplay(width: 320, height: 180, columns: 21, rows: 10, count: 540, intervalMilliseconds: 10_000) == nil)
        #expect(
            Trickplay(width: 320, height: 180, columns: 10, rows: 0, count: 540, intervalMilliseconds: 10_000) == nil)
        #expect(
            Trickplay(width: 320, height: 180, columns: 10, rows: 10, count: 0, intervalMilliseconds: 10_000) == nil)
        #expect(
            Trickplay(width: 320, height: 180, columns: 10, rows: 10, count: 100_001, intervalMilliseconds: 1) == nil)
        #expect(Trickplay(width: 320, height: 180, columns: 10, rows: 10, count: 540, intervalMilliseconds: 0) == nil)
        #expect(Trickplay(info(width: 320)) == standard)
        #expect(Trickplay(TrickplayInfoDto(height: 180, interval: 10_000, thumbnailCount: 540, width: 320)) == nil)
    }

    @Test func theServersSizesForAVersionAreListedNarrowestFirst() {
        let manifest = [
            // Jellyfin writes a version's ID without dashes.
            movieID: [
                "640": info(width: 640),
                "320": info(width: 320),
                "1280": TrickplayInfoDto(width: 1280),
            ],
            "f137a2dd21bbc1b99aa5c0f6bf02a805": ["320": info(width: 320)],
        ]
        let layouts = Trickplay.layouts(in: manifest, mediaSourceID: movieID)
        #expect(layouts.map(\.width) == [320, 640])
        // The same version, its ID written with dashes in capitals.
        let dashed = "0B82ED8E-9F1D-AED4-E2A4-4E4D233E29B4"
        #expect(Trickplay.layouts(in: manifest, mediaSourceID: dashed) == layouts)
        #expect(Trickplay.layouts(in: manifest, mediaSourceID: "aaaa1111").isEmpty)
        #expect(Trickplay.layouts(in: manifest, mediaSourceID: "").isEmpty)
        #expect(Trickplay.layouts(in: nil, mediaSourceID: movieID).isEmpty)
    }

    @Test func theSizeLoadedIsTheWidestNoWiderThanItsDrawn() {
        let layouts = [320, 640, 1280].compactMap { Trickplay(info(width: $0)) }
        #expect(Trickplay.best(of: layouts, points: 320, scale: 3)?.width == 640)
        #expect(Trickplay.best(of: layouts, points: 480, scale: 3)?.width == 1280)
        #expect(Trickplay.best(of: layouts, points: 320, scale: 1)?.width == 320)
        // Every size is wider than it's drawn: the narrowest.
        #expect(Trickplay.best(of: layouts, points: 100, scale: 1)?.width == 320)
        #expect(Trickplay.best(of: [], points: 320, scale: 3) == nil)
    }

    @Test func theServersBandwidthBoundsTheTilesSize() throws {
        // Jellyfin's bandwidth is a tile's bits over the 1,000 seconds its 100 thumbnails cover: here 300 KB a tile.
        let layout = try #require(Trickplay(info(width: 320, bandwidth: 2_400)))
        // Six tiles of 300 KB.
        #expect(layout.estimatedBytes == 1_800_000)
        #expect(try #require(standard).estimatedBytes == nil)
        #expect(try #require(Trickplay(info(width: 320, bandwidth: 0))).bandwidth == nil)
    }

    @Test func aLayoutSavedWithADownloadReadsAsItWasWritten() throws {
        let layout = try #require(Trickplay(info(width: 320, bandwidth: 2_400)))
        let read = try JSONDecoder().decode(Trickplay.self, from: try JSONEncoder().encode(layout))
        #expect(read == layout)
        let withoutBandwidth = try #require(standard)
        #expect(
            try JSONDecoder().decode(Trickplay.self, from: try JSONEncoder().encode(withoutBandwidth))
                == withoutBandwidth)
    }

    @Test func aDamagedLayoutReadsWithinTheBoundsAServersMustKeepTo() throws {
        let damaged = #"""
            {"width": 0, "height": 99999, "columns": 50, "rows": -3, "count": 0, "intervalMilliseconds": -5,
             "bandwidth": -1}
            """#
        let read = try JSONDecoder().decode(Trickplay.self, from: Data(damaged.utf8))
        #expect(read.width == 1)
        #expect(read.height == Trickplay.maximumWidth)
        #expect(read.columns == Trickplay.maximumGrid)
        #expect(read.rows == 1)
        #expect(read.count == 1)
        #expect(read.intervalMilliseconds == 1)
        #expect(read.bandwidth == nil)
        #expect(read.tileCount == 1)
    }
}

@Suite struct TrickplayTileTests {
    /// Thumbnails 48 by 27 pixels, 5 by 5 to a tile, 23 of them, so the only tile has two empty places.
    private let small = Trickplay(width: 48, height: 27, columns: 5, rows: 5, count: 23, intervalMilliseconds: 10_000)

    @Test func aTileIsCutIntoItsThumbnailsLeftToRightThenTopToBottom() throws {
        let layout = try #require(small)
        let data = try tilePicture(columns: 5, rows: 5, width: 48, height: 27)

        let images = try #require(layout.thumbnails(inTile: 0, from: data))

        #expect(images.tile == 0)
        #expect(images.thumbnails.keys.sorted() == Array(0..<23))
        #expect(images.thumbnails.values.allSatisfy { $0.width == 48 && $0.height == 27 })
        #expect(images.bytes >= 240 * 135 * 3)
        for (thumbnail, column, row) in [(3, 3, 0), (12, 2, 2), (21, 1, 4)] {
            let colour = try middleColour(of: try #require(images.thumbnails[thumbnail]))
            #expect(abs(colour.red - column * 50) <= 10, "thumbnail \(thumbnail)")
            #expect(abs(colour.green - row * 50) <= 10, "thumbnail \(thumbnail)")
        }
    }

    @Test func aTileThatIsntAPictureOrIsntInTheLayoutGivesNoThumbnails() throws {
        let layout = try #require(small)
        let data = try tilePicture(columns: 5, rows: 5, width: 48, height: 27)
        #expect(layout.thumbnails(inTile: 1, from: data) == nil)
        #expect(layout.thumbnails(inTile: 0, from: Data(#"{"Message":"Not found"}"#.utf8)) == nil)
        #expect(layout.thumbnails(inTile: 0, from: Data()) == nil)
    }

    @Test func aTileSmallerThanTheLayoutSaysGivesOnlyTheThumbnailsItHolds() throws {
        let layout = try #require(small)
        // Three rows rather than five.
        let data = try tilePicture(columns: 5, rows: 3, width: 48, height: 27)
        let images = try #require(layout.thumbnails(inTile: 0, from: data))
        #expect(images.thumbnails.keys.sorted() == Array(0..<15))
    }

    @Test func tileAddressesNameTheVersionInThePathAndTheQuery() throws {
        let urls = ImageURLs(serverURL: try #require(URL(string: "https://media.example.com")))
        let url = try #require(urls.trickplayTileURL(mediaSourceID: movieID, width: 320, index: 4))
        #expect(
            url.absoluteString
                == "https://media.example.com/Videos/\(movieID)/Trickplay/320/4.jpg?mediaSourceId=\(movieID)")
        #expect(urls.trickplayTileURL(mediaSourceID: "../System/Info", width: 320, index: 4) == nil)
        #expect(urls.trickplayTileURL(mediaSourceID: movieID, width: 0, index: 4) == nil)
        #expect(urls.trickplayTileURL(mediaSourceID: movieID, width: 320, index: -1) == nil)
    }

    @Test func aServersTileLoadsWithTheHeaderNotTheToken() async throws {
        let host = "trickplay-tile.example.com"
        let path = "/Videos/\(movieID)/Trickplay/640/1.jpg"
        StubURLProtocol.stub("\(host):443", path: path, .json(200, "tile"))
        let layouts = [320, 640, 1280].compactMap { Trickplay(info(width: $0)) }
        let reader = try #require(
            TrickplayTileReader(
                .server(mediaSourceID: movieID, layouts: layouts), points: 320, scale: 2,
                artwork: try stubArtwork(on: host)))

        #expect(reader.layout.width == 640)
        #expect(reader.isRemote)
        #expect(try await reader.data(ofTile: 1) == Data("tile".utf8))
        #expect(try await reader.data(ofTile: 6) == nil)

        let sent = try #require(StubURLProtocol.requests(to: "\(host):443", path: path).first)
        #expect(sent.authorization == #"MediaBrowser Token="secret""#)
        #expect(sent.query("mediaSourceId") == movieID)
        #expect(sent.query("api_key") == nil)
    }

    @Test func theServersTilesNeedSomethingToLoadThemWith() throws {
        let layouts = [320].compactMap { Trickplay(info(width: $0)) }
        #expect(
            TrickplayTileReader(.server(mediaSourceID: movieID, layouts: layouts), points: 320, scale: 3, artwork: nil)
                == nil)
        let artwork = try stubArtwork(on: "trickplay-none.example.com")
        #expect(
            TrickplayTileReader(.server(mediaSourceID: movieID, layouts: []), points: 320, scale: 3, artwork: artwork)
                == nil)
    }

    @Test func savedTilesAreReadFromTheirFiles() async throws {
        let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = try #require(custom)
        let files = (0..<3).map { directory.appending(path: "tile-\($0).jpg") }
        for (index, file) in files.enumerated() {
            try Data("tile \(index)".utf8).write(to: file)
        }

        let reader = try #require(
            TrickplayTileReader(.saved(layout, files: files), points: 320, scale: 3, artwork: nil))

        #expect(!reader.isRemote)
        #expect(reader.layout == layout)
        #expect(try await reader.data(ofTile: 2) == Data("tile 2".utf8))
        #expect(try await reader.data(ofTile: 3) == nil)
        #expect(try await reader.data(ofTile: -1) == nil)
        // Every tile of the layout, or none.
        #expect(
            TrickplayTileReader(.saved(layout, files: Array(files.prefix(2))), points: 320, scale: 3, artwork: nil)
                == nil)
    }

    @Test func aSavedTileLargerThanAnyTileIsntRead() async throws {
        let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let layout = try #require(
            Trickplay(width: 320, height: 180, columns: 10, rows: 10, count: 100, intervalMilliseconds: 10_000))
        let file = directory.appending(path: "tile-0.jpg")
        #expect(FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(Trickplay.maximumTileBytes + 1))
        try handle.close()

        let reader = try #require(
            TrickplayTileReader(.saved(layout, files: [file]), points: 320, scale: 3, artwork: nil))

        #expect(try await reader.data(ofTile: 0) == nil)
    }
}

@Suite struct TrickplayRepositoryTests {
    @Test func anItemWithItsTrickplayFieldAlreadyIsntAskedAbout() async throws {
        let host = "trickplay-known.example.com"
        let repository = TrickplayRepository(client: try trickplayClient(on: host), userID: "user-1")
        let item = BaseItemDto(id: movieID, trickplay: [:])

        #expect(await repository.details(of: item) == item)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movieID)").isEmpty)
    }

    @Test func anItemIsAskedAboutOnceForItsThumbnailsAndChapters() async throws {
        let host = "trickplay-asked.example.com"
        let answer = """
            {"Id": "\(movieID)", "Trickplay": {"\(movieID)": {"320": {"Width": 320, "Height": 180, "TileWidth": 10,
             "TileHeight": 10, "ThumbnailCount": 540, "Interval": 10000, "Bandwidth": 2400}}},
             "Chapters": [{"Name": "Opening", "StartPositionTicks": 0},
                          {"Name": "The Village", "StartPositionTicks": 950000000}]}
            """
        StubURLProtocol.stub("\(host):443", path: "/Items/\(movieID)", .json(200, answer))
        let repository = TrickplayRepository(client: try trickplayClient(on: host), userID: "user-1")
        let item = BaseItemDto(id: movieID)

        let details = await repository.details(of: item)
        let again = await repository.details(of: item)

        #expect(Trickplay.layouts(in: details.trickplay, mediaSourceID: movieID).map(\.width) == [320])
        #expect(details.chapters?.map(\.name) == ["Opening", "The Village"])
        #expect(again == details)
        let sent = StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movieID)")
        #expect(sent.count == 1)
        #expect(sent.first?.query("userId") == "user-1")
    }

    @Test func anItemTheServerCantAnswerForIsAskedAgainNextTime() async throws {
        let host = "trickplay-failing.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Items/\(movieID)", .json(500, "{}"))
        let repository = TrickplayRepository(client: try trickplayClient(on: host), userID: "user-1")
        let item = BaseItemDto(id: movieID, name: "Sintel")

        #expect(await repository.details(of: item) == item)
        #expect(await repository.details(of: item) == item)
        #expect(StubURLProtocol.requests(to: "\(host):443", path: "/Items/\(movieID)").count == 2)
    }

    @Test func anItemWithAnOddIDIsntAskedAbout() async throws {
        let host = "trickplay-odd.example.com"
        let repository = TrickplayRepository(client: try trickplayClient(on: host), userID: "user-1")
        let item = BaseItemDto(id: "../System/Info")

        #expect(await repository.details(of: item) == item)
        #expect(StubURLProtocol.lastRequest(to: "\(host):443") == nil)
    }
}
