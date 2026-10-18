import Foundation

/// Rewrites the codec tags of an MP4 file's sample descriptions in place, where AVFoundation reads the same samples
/// only under another tag.
///
/// Jellyfin's ffmpeg tags HEVC it copies into an MP4 `hev1`, which lets parameter sets sit inside the samples as well
/// as in the sample description, and AVFoundation doesn't list a track tagged that way at all. Tagged `hvc1`, as the
/// server tags the same samples in its own HLS streams, the track reads and plays. Dolby Vision's `dvhe` becomes
/// `dvh1` the same way. Only the four bytes of each tag change, so every offset in the file stays as it is.
///
/// The file is untrusted input: every box is checked against what holds it, and only the movie box is read.
enum SampleEntryTags {
    /// A box in the file: its type, where it starts, and where its contents are.
    struct Box {
        let type: FourCharCode
        let start: Int
        let contents: Range<Int>
    }

    /// The tags rewritten, and what each becomes.
    static let replacements: [FourCharCode: FourCharCode] = [
        DownloadedCopyWriter.fourCharCode("hev1"): DownloadedCopyWriter.fourCharCode("hvc1"),
        DownloadedCopyWriter.fourCharCode("dvhe"): DownloadedCopyWriter.fourCharCode("dvh1"),
    ]

    /// The most bytes of a movie box read: far more than a fragmented MP4's, whose samples are described in the
    /// fragments after it, and than a whole film's sample tables.
    static let maximumMovieBytes = 64 << 20

    /// The most boxes looked through at the top of the file before the movie box.
    private static let maximumTopLevelBoxes = 1_000

    /// The boxes from the movie box down to a track's sample descriptions.
    private static let pathToSampleDescriptions = ["trak", "mdia", "minf", "stbl", "stsd"].map {
        DownloadedCopyWriter.fourCharCode($0)
    }

    /// Rewrites the tags in the MP4 file at `url`, returning how many it rewrote. A file with no movie box within
    /// reach has none rewritten.
    ///
    /// - Throws: When the file can't be read or written.
    @discardableResult
    static func rewrite(fileAt url: URL) throws -> Int {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        guard let movie = try movieBox(in: handle) else { return 0 }
        let tags = tagOffsets(inMovie: movie.contents)
        for (offset, replacement) in tags {
            try handle.seek(toOffset: movie.offset + UInt64(offset))
            try handle.write(contentsOf: bigEndianBytes(replacement))
        }
        return tags.count
    }

    /// Where each tag to rewrite is in `movie`, the movie box's contents, and what it becomes.
    static func tagOffsets(inMovie movie: [UInt8]) -> [(offset: Int, replacement: FourCharCode)] {
        var ranges = [0..<movie.count]
        for type in pathToSampleDescriptions {
            ranges = ranges.flatMap { range in
                boxes(in: movie, range).filter { $0.type == type }.map(\.contents)
            }
        }
        var tags: [(offset: Int, replacement: FourCharCode)] = []
        for descriptions in ranges {
            // A full box, then the number of entries, then the entries, each a box whose type is its tag.
            guard descriptions.count >= 8 else { continue }
            let entries = (descriptions.lowerBound + 8)..<descriptions.upperBound
            for entry in boxes(in: movie, entries) {
                guard let replacement = replacements[entry.type] else { continue }
                tags.append((entry.start + 4, replacement))
            }
        }
        return tags
    }

    /// The boxes in `range` of `bytes`, in order, until one doesn't fit what holds it.
    static func boxes(in bytes: [UInt8], _ range: Range<Int>) -> [Box] {
        var found: [Box] = []
        var position = range.lowerBound
        while range.upperBound - position >= 8 {
            var size = UInt64(integer(bytes, at: position, count: 4))
            let type = FourCharCode(integer(bytes, at: position + 4, count: 4))
            var header = 8
            if size == 1 {
                guard range.upperBound - position >= 16 else { break }
                size = integer(bytes, at: position + 8, count: 8)
                header = 16
            } else if size == 0 {
                size = UInt64(range.upperBound - position)
            }
            guard size >= UInt64(header), size <= UInt64(range.upperBound - position) else { break }
            let end = position + Int(size)
            found.append(Box(type: type, start: position, contents: (position + header)..<end))
            position = end
        }
        return found
    }

    /// The movie box's contents and where they start in the file, or nil when the file has none within reach.
    private static func movieBox(in handle: FileHandle) throws -> (offset: UInt64, contents: [UInt8])? {
        let end = try handle.seekToEnd()
        let movieType = DownloadedCopyWriter.fourCharCode("moov")
        var position: UInt64 = 0
        for _ in 0..<maximumTopLevelBoxes {
            guard end >= 8, position <= end - 8 else { return nil }
            try handle.seek(toOffset: position)
            let header = [UInt8](try handle.read(upToCount: 16) ?? Data())
            guard header.count >= 8 else { return nil }
            var size = UInt64(integer(header, at: 0, count: 4))
            let type = FourCharCode(integer(header, at: 4, count: 4))
            var headerSize: UInt64 = 8
            if size == 1 {
                guard header.count == 16 else { return nil }
                size = integer(header, at: 8, count: 8)
                headerSize = 16
            } else if size == 0 {
                size = end - position
            }
            guard size >= headerSize, size <= end - position else { return nil }
            if type == movieType {
                let length = size - headerSize
                guard length <= UInt64(maximumMovieBytes) else { return nil }
                try handle.seek(toOffset: position + headerSize)
                let contents = [UInt8](try handle.read(upToCount: Int(length)) ?? Data())
                guard contents.count == Int(length) else { return nil }
                return (position + headerSize, contents)
            }
            position += size
        }
        return nil
    }

    /// The big-endian unsigned number in the `count` bytes of `bytes` from `offset`, which the caller has checked are
    /// there.
    private static func integer(_ bytes: [UInt8], at offset: Int, count: Int) -> UInt64 {
        bytes[offset..<(offset + count)].reduce(0) { $0 << 8 | UInt64($1) }
    }

    /// `value`'s four bytes, most significant first.
    private static func bigEndianBytes(_ value: FourCharCode) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
