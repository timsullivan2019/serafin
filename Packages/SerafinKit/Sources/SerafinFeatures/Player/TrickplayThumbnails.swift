import CoreGraphics
import Foundation
import Observation
import SerafinCore
import SerafinDesign
import SwiftUI
import os

/// The thumbnails the player's scrubber preview shows of what's playing, cut from the tiles of its trickplay
/// thumbnails as the finger nears them: from the server through the shared image pipeline, with the account's
/// `Authorization` header and the disk cache, or from the files saved with a download.
///
/// Nothing is decoded before the first drag, and only the tile at the playback position is fetched ahead, into the
/// disk cache. As the finger moves, the tile under it is decoded and cut into thumbnails once, and kept with the nearer
/// of its neighbours, within ``memoryBudget``; the tiles either side are fetched into the disk cache without being
/// decoded. While a tile loads, the preview shows the nearest thumbnail that has. A tile that can't be loaded isn't
/// asked for again for ``retryDelay``.
@Observable @MainActor final class TrickplayThumbnails {
    /// The most memory the decoded tiles take: two of Jellyfin's standard tiles, 10 by 10 thumbnails 320 pixels wide.
    /// One tile is always kept, however large.
    static let memoryBudget = 48 * 1024 * 1024
    /// How long a tile that couldn't be loaded waits before it's asked for again.
    static let retryDelay = Duration.seconds(5)
    /// The widest the scrubber's preview draws a thumbnail, in points, on iPhone and on iPad, which decides the size
    /// of thumbnails to load: the widest the server made that's no wider than this at the screen's scale.
    nonisolated static func previewBudget(isRegular: Bool) -> CGFloat {
        isRegular ? 480 : 320
    }

    nonisolated private static let logger = Logger(serafinCategory: "trickplay")

    /// The size of thumbnails shown.
    let layout: Trickplay
    /// The decoded tiles' thumbnails, by tile.
    private(set) var tiles: [Int: TrickplayTileImages] = [:]
    @ObservationIgnored private let reader: TrickplayTileReader
    /// The decoded tiles, the one used longest ago first.
    @ObservationIgnored private var recent: [Int] = []
    @ObservationIgnored private var decoding: [Int: Task<Void, Never>] = [:]
    @ObservationIgnored private var fetching: [Int: Task<Void, Never>] = [:]
    /// The tiles fetched into the disk cache, which needn't be fetched again.
    @ObservationIgnored private var fetched: Set<Int> = []
    /// When each tile that couldn't be loaded last failed.
    @ObservationIgnored private var failures: [Int: ContinuousClock.Instant] = [:]

    /// Creates the thumbnails `reader` reads.
    init(reader: TrickplayTileReader) {
        self.reader = reader
        layout = reader.layout
    }

    /// The thumbnails of `tiles` in the size that suits the scrubber's preview, or nil when there are none, or the
    /// server's have no `artwork` to load them with.
    ///
    /// - Parameters:
    ///   - isRegular: Whether the player is regular width, as on iPad, where the preview draws thumbnails wider.
    ///   - scale: The screen's scale.
    convenience init?(_ tiles: TrickplayTiles?, isRegular: Bool, scale: CGFloat, artwork: Artwork?) {
        guard let tiles,
            let reader = TrickplayTileReader(
                tiles, points: TrickplayThumbnails.previewBudget(isRegular: isRegular), scale: scale,
                artwork: artwork)
        else { return nil }
        self.init(reader: reader)
    }

    isolated deinit {
        for task in decoding.values {
            task.cancel()
        }
        for task in fetching.values {
            task.cancel()
        }
    }

    /// The thumbnails as the scrubber takes them.
    var scrubberThumbnails: ScrubberThumbnails {
        ScrubberThumbnails(
            aspectRatio: CGFloat(layout.width) / CGFloat(layout.height),
            image: { [weak self] position in
                self?.thumbnail(at: position).map { Image(decorative: $0, scale: 1) }
            },
            prepare: { [weak self] position in
                self?.prepare(around: position)
            }
        )
    }

    /// The thumbnail of the frame at `position`, or while its tile loads, the nearest one that has, or nil when none
    /// has.
    func thumbnail(at position: Duration) -> CGImage? {
        let wanted = layout.thumbnail(at: position)
        var nearest: (distance: Int, image: CGImage)?
        for images in tiles.values {
            let range = layout.thumbnails(inTile: images.tile)
            guard !range.isEmpty else { continue }
            let closest = min(max(wanted, range.lowerBound), range.upperBound - 1)
            guard let image = images.thumbnails[closest] else { continue }
            let distance = abs(closest - wanted)
            if distance == 0 { return image }
            if nearest.map({ distance < $0.distance }) ?? true {
                nearest = (distance, image)
            }
        }
        return nearest?.image
    }

    /// Fetches the tile showing `position` into the disk cache, without decoding it, so the first drag's preview
    /// shows sooner.
    func prefetch(around position: Duration) {
        fetch(layout.place(at: position).tile)
    }

    /// Loads the thumbnails around `position`, as a drag on the scrubber moves: decodes the tile showing it and the
    /// nearer of its neighbours, fetches the tiles either side ahead, and lets go of loads no longer near. Returns at
    /// once.
    func prepare(around position: Duration) {
        let place = layout.place(at: position)
        let range = layout.thumbnails(inTile: place.tile)
        let nearer = place.thumbnail - range.lowerBound < range.count / 2 ? place.tile - 1 : place.tile + 1
        let wanted = Set([place.tile, nearer].filter { isTile($0) }.prefix(maximumTiles))
        for (tile, task) in decoding where !wanted.contains(tile) {
            task.cancel()
            decoding[tile] = nil
        }
        decode(place.tile)
        if wanted.contains(nearer) {
            decode(nearer)
        }
        guard reader.isRemote else { return }
        let ahead: Set = [place.tile - 1, place.tile + 1]
        for (tile, task) in fetching where !ahead.contains(tile) {
            task.cancel()
            fetching[tile] = nil
        }
        for tile in ahead {
            fetch(tile)
        }
    }

    /// How many decoded tiles fit in ``memoryBudget``, and at least one.
    var maximumTiles: Int {
        let pixels = min(
            layout.columns * layout.width * layout.rows * layout.height, Trickplay.maximumTilePixels)
        return max(1, Self.memoryBudget / max(pixels * 4, 1))
    }

    private func isTile(_ tile: Int) -> Bool {
        (0..<layout.tileCount).contains(tile)
    }

    /// Whether `tile` failed less than ``retryDelay`` ago.
    private func isWaitingAfterFailure(_ tile: Int) -> Bool {
        guard let failed = failures[tile] else { return false }
        return ContinuousClock.now - failed < Self.retryDelay
    }

    private func decode(_ tile: Int) {
        guard isTile(tile) else { return }
        if tiles[tile] != nil {
            use(tile)
            return
        }
        guard decoding[tile] == nil, !isWaitingAfterFailure(tile) else { return }
        let reader = reader
        decoding[tile] = Task { [weak self] in
            let images = await Self.load(tile, from: reader)
            guard !Task.isCancelled else { return }
            self?.finishDecoding(tile, images)
        }
    }

    private func finishDecoding(_ tile: Int, _ images: TrickplayTileImages?) {
        decoding[tile] = nil
        guard let images else {
            failures[tile] = .now
            return
        }
        failures[tile] = nil
        fetched.insert(tile)
        tiles[tile] = images
        use(tile)
        while recent.count > maximumTiles, let oldest = recent.first {
            recent.removeFirst()
            tiles[oldest] = nil
        }
    }

    /// Notes `tile` as just used, so it's the last to go.
    private func use(_ tile: Int) {
        recent.removeAll { $0 == tile }
        recent.append(tile)
    }

    /// Fetches `tile` into the disk cache, unless it's there, decoded, on its way, or failed a moment ago.
    private func fetch(_ tile: Int) {
        guard reader.isRemote, isTile(tile), !fetched.contains(tile), tiles[tile] == nil, decoding[tile] == nil,
            fetching[tile] == nil, !isWaitingAfterFailure(tile)
        else { return }
        let reader = reader
        fetching[tile] = Task { [weak self] in
            let arrived = await Self.fetch(tile, from: reader)
            guard !Task.isCancelled else { return }
            self?.finishFetching(tile, arrived: arrived)
        }
    }

    private func finishFetching(_ tile: Int, arrived: Bool) {
        fetching[tile] = nil
        if arrived {
            fetched.insert(tile)
        } else {
            failures[tile] = .now
        }
    }

    /// Reads tile `tile` and cuts it into thumbnails, away from the main actor, or nil when it can't be read or
    /// isn't a picture.
    private nonisolated static func load(_ tile: Int, from reader: TrickplayTileReader) async -> TrickplayTileImages? {
        do {
            guard let data = try await reader.data(ofTile: tile) else { return nil }
            try Task.checkCancellation()
            return reader.layout.thumbnails(inTile: tile, from: data)
        } catch {
            if !(error is CancellationError) {
                logger.debug("No trickplay tile: \(error.localizedDescription, privacy: .private)")
            }
            return nil
        }
    }

    /// Reads tile `tile`, which keeps it in the disk cache, and returns whether it arrived.
    private nonisolated static func fetch(_ tile: Int, from reader: TrickplayTileReader) async -> Bool {
        do {
            return try await reader.data(ofTile: tile) != nil
        } catch {
            return false
        }
    }
}
