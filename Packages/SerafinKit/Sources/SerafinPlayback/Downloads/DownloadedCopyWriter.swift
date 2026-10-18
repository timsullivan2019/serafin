import AVFoundation
import CoreMedia
import Foundation
import SerafinCore
import os

/// Writes the downloaded copies the player opens, on the device, from the file that arrived and the subtitles saved
/// with it. Nothing is converted: the video and audio are copied as they are into a QuickTime movie, and each WebVTT
/// file becomes a text track.
///
/// Jellyfin sends a video it converts for a download as fragmented MP4, made while it's sent. An HEVC video it copies
/// there carries the `hev1` tag, which AVPlayer doesn't play, so the copy carries `hvc1`, as the server's own HLS
/// streams do, and Dolby Vision's `dvhe` becomes `dvh1`. Text subtitles can't go into the server's MP4 at all, so they
/// come from its subtitle endpoint as WebVTT, timed on the video's own timeline, and become 3GPP text tracks, the
/// subtitles AVPlayer shows from MP4 and QuickTime files. They follow the file's own subtitle tracks, in one alternate
/// group that shows none until the player picks one. A QuickTime movie, because it's the container AVAssetWriter
/// copies every kind of track into.
public struct DownloadedCopyWriter: DownloadPreparing {
    private static let logger = Logger(serafinCategory: "downloads")

    /// Creates a writer.
    public init() {}

    public func prepare(_ job: DownloadPreparationJob) async throws {
        let asset = AVURLAsset(url: job.arrived)
        let sources: [SourceTrack]
        do {
            sources = try await SourceTrack.tracks(of: asset)
        } catch {
            Self.logger.error("Could not read a download: \(error.localizedDescription, privacy: .private)")
            throw DownloadPreparationError.unreadable
        }
        guard sources.contains(where: { $0.mediaType == .video }) else { throw DownloadPreparationError.unreadable }
        let subtitles = job.subtitles.map { added in
            let data = (try? Data(contentsOf: added.file)) ?? Data()
            return TextTrack(track: added.track, stretches: TimedText.stretches(of: WebVTT.cues(in: data)))
        }
        try Task.checkCancellation()
        if FileManager.default.fileExists(atPath: job.output.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: job.output)
        }
        let copy = try MovieCopy(asset: asset, sources: sources, subtitles: subtitles, output: job.output)
        try await copy.run()
    }

    /// The format `description` takes in the copy: HEVC tagged `hvc1`, or Dolby Vision `dvh1`, where it arrived as
    /// `hev1` or `dvhe`, which AVPlayer doesn't play. Nil when it stays as it is.
    static func retagged(_ description: CMFormatDescription) -> CMFormatDescription? {
        let replacements = [fourCharCode("hev1"): fourCharCode("hvc1"), fourCharCode("dvhe"): fourCharCode("dvh1")]
        guard CMFormatDescriptionGetMediaType(description) == kCMMediaType_Video,
            let replacement = replacements[CMFormatDescriptionGetMediaSubType(description)]
        else { return nil }
        let dimensions = CMVideoFormatDescriptionGetDimensions(description)
        var retagged: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: replacement,
            width: dimensions.width,
            height: dimensions.height,
            extensions: CMFormatDescriptionGetExtensions(description),
            formatDescriptionOut: &retagged
        )
        return status == noErr ? retagged : nil
    }

    /// `sample` described by `description` in place of its own format, with its data, its timing and what each
    /// frame says of itself, such as whether it's a key frame, as they are.
    static func sample(_ sample: CMSampleBuffer, describedBy description: CMFormatDescription) -> CMSampleBuffer? {
        var timingCount: CMItemCount = 0
        var sizeCount: CMItemCount = 0
        guard
            CMSampleBufferGetSampleTimingInfoArray(
                sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &timingCount) == noErr,
            CMSampleBufferGetSampleSizeArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &sizeCount)
                == noErr
        else { return nil }
        var timings = Array(repeating: CMSampleTimingInfo(), count: timingCount)
        var sizes = Array(repeating: 0, count: sizeCount)
        guard
            CMSampleBufferGetSampleTimingInfoArray(
                sample, entryCount: timingCount, arrayToFill: &timings, entriesNeededOut: nil) == noErr,
            CMSampleBufferGetSampleSizeArray(
                sample, entryCount: sizeCount, arrayToFill: &sizes, entriesNeededOut: nil) == noErr
        else { return nil }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: CMSampleBufferGetDataBuffer(sample),
            formatDescription: description,
            sampleCount: CMSampleBufferGetNumSamples(sample),
            sampleTimingEntryCount: timingCount,
            sampleTimingArray: timings,
            sampleSizeEntryCount: sizeCount,
            sampleSizeArray: sizes,
            sampleBufferOut: &copy
        )
        guard status == noErr, let copy else { return nil }
        CMPropagateAttachments(sample, destination: copy)
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            as? [NSDictionary],
            let copied = CMSampleBufferGetSampleAttachmentsArray(copy, createIfNecessary: true)
                as? [NSMutableDictionary]
        {
            for (from, to) in zip(attachments, copied) {
                to.addEntries(from: from as [AnyHashable: Any])
            }
        }
        return copy
    }

    /// The format of a 3GPP text track of subtitles, `forced` or not: the sample description ffmpeg writes for MP4
    /// subtitles, which AVPlayer shows in its own style. Nil when CoreMedia doesn't take it.
    static func textFormat(forced: Bool) -> CMFormatDescription? {
        var entry = Data()
        func append(_ value: UInt32) {
            withUnsafeBytes(of: value.bigEndian) { entry.append(contentsOf: $0) }
        }
        func append(_ value: UInt16) {
            withUnsafeBytes(of: value.bigEndian) { entry.append(contentsOf: $0) }
        }
        let font = Array("Sans-Serif".utf8)
        let fontTableSize = 8 + 2 + 2 + 1 + font.count
        // The sample entry: size, type, six reserved bytes and the data reference.
        append(UInt32(16 + 4 + 2 + 4 + 8 + 12 + fontTableSize))
        entry.append(contentsOf: Array("tx3g".utf8))
        entry.append(contentsOf: [0, 0, 0, 0, 0, 0])
        append(UInt16(1))
        // Display flags: every sample forced, for forced subtitles.
        append(forced ? UInt32(0x8000_0000) : 0)
        // Centred, at the bottom, on no background.
        entry.append(contentsOf: [0x01, 0xFF])
        append(UInt32(0))
        // The default text box, left to the player.
        append(UInt16(0))
        append(UInt16(0))
        append(UInt16(0))
        append(UInt16(0))
        // The default style: the whole sample, font 1, plain, 18 points, opaque white.
        append(UInt16(0))
        append(UInt16(0))
        append(UInt16(1))
        entry.append(contentsOf: [0, 18])
        append(UInt32(0xFFFF_FFFF))
        // The font table, with font 1.
        append(UInt32(fontTableSize))
        entry.append(contentsOf: Array("ftab".utf8))
        append(UInt16(1))
        append(UInt16(1))
        entry.append(UInt8(font.count))
        entry.append(contentsOf: font)
        var description: CMFormatDescription?
        let status = entry.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else {
                return kCMFormatDescriptionError_InvalidParameter
            }
            return CMTextFormatDescriptionCreateFromBigEndianTextDescriptionData(
                allocator: kCFAllocatorDefault,
                bigEndianTextDescriptionData: base,
                size: bytes.count,
                flavor: nil,
                mediaType: kCMMediaType_Subtitle,
                formatDescriptionOut: &description
            )
        }
        return status == noErr ? description : nil
    }

    /// A text sample showing `stretch`'s text for as long as it lasts.
    static func textSample(_ stretch: TimedText.Stretch, format: CMFormatDescription) -> CMSampleBuffer? {
        let data = TimedText.sample(stretch.text)
        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: data.count,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: data.count,
                flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &block
            ) == kCMBlockBufferNoErr, let block
        else { return nil }
        let copied = data.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
            return CMBlockBufferReplaceDataBytes(
                with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(stretch.end - stretch.start),
            presentationTimeStamp: CMTime(stretch.start),
            decodeTimeStamp: .invalid
        )
        var size = data.count
        var sample: CMSampleBuffer?
        let status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &size,
            sampleBufferOut: &sample
        )
        return status == noErr ? sample : nil
    }

    /// The tagged characteristics that mark a track as forced subtitles or as subtitles for the deaf and hard of
    /// hearing, as QuickTime movies carry them.
    static func characteristicsMetadata(_ characteristics: [AVMediaCharacteristic]) -> [AVMetadataItem] {
        characteristics.map { characteristic in
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeUserDataTaggedCharacteristic
            item.value = characteristic.rawValue as NSString
            return item
        }
    }

    /// The ISO 639-2/T code a QuickTime track carries for a language as Jellyfin names it, such as `fra` for `fre`.
    static func languageCode(_ language: String?) -> String? {
        SubtitleRules.language(language).flatMap { Locale.LanguageCode($0).identifier(.alpha3) }
    }

    /// The four-character code `text` spells, such as `hvc1`.
    static func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}

/// A track copied from the file that arrived, with what the copy keeps of it.
private struct SourceTrack {
    /// The characteristics a copied track keeps.
    static let keptCharacteristics: [AVMediaCharacteristic] = [
        .containsOnlyForcedSubtitles, .transcribesSpokenDialogForAccessibility,
        .describesMusicAndSoundForAccessibility,
    ]

    let track: AVAssetTrack
    let mediaType: AVMediaType
    let format: CMFormatDescription?
    let timeScale: CMTimeScale
    let transform: CGAffineTransform
    let languageCode: String?
    let extendedLanguageTag: String?
    let characteristics: [AVMediaCharacteristic]

    /// The tracks of `asset` a copy keeps, in the file's order: the first video, every audio track, and the subtitles
    /// the player can show, leaving out the text tracks that hold chapter titles.
    static func tracks(of asset: AVURLAsset) async throws -> [SourceTrack] {
        let tracks = try await asset.load(.tracks)
        var chapters: Set<CMPersistentTrackID> = []
        for track in tracks {
            for chapter in (try? await track.loadAssociatedTracks(ofType: .chapterList)) ?? [] {
                chapters.insert(chapter.trackID)
            }
        }
        var kept: [SourceTrack] = []
        for track in tracks {
            switch track.mediaType {
            case .video:
                guard !kept.contains(where: { $0.mediaType == .video }) else { continue }
            case .audio, .subtitle:
                break
            case .text:
                guard !chapters.contains(track.trackID) else { continue }
            default:
                continue
            }
            let (formats, timeScale, transform, languageCode, extendedLanguageTag, characteristics) =
                try await track.load(
                    .formatDescriptions, .naturalTimeScale, .preferredTransform, .languageCode, .extendedLanguageTag,
                    .mediaCharacteristics)
            kept.append(
                SourceTrack(
                    track: track,
                    mediaType: track.mediaType,
                    format: formats.first,
                    timeScale: timeScale,
                    transform: transform,
                    languageCode: languageCode,
                    extendedLanguageTag: extendedLanguageTag,
                    characteristics: characteristics.filter { keptCharacteristics.contains($0) }
                )
            )
        }
        return kept
    }
}

/// Subtitles to add to a copy as a text track.
private struct TextTrack {
    let track: DownloadTrack
    let stretches: [TimedText.Stretch]
}

/// One copy of an asset's tracks, with text tracks made from subtitles, into a QuickTime movie, moved on a queue of
/// its own. It's only ever touched on that queue once it's running.
private final class MovieCopy: @unchecked Sendable {
    /// Where each track of the copy comes from.
    private final class Feed {
        enum Source {
            /// A track of the asset, with the format its samples take in the copy, when it changes.
            case track(AVAssetReaderTrackOutput, retagged: CMFormatDescription?)
            /// Subtitle samples, in order.
            case text([CMSampleBuffer])
        }

        let input: AVAssetWriterInput
        let source: Source
        var position = 0
        var isDone = false

        init(input: AVAssetWriterInput, source: Source) {
            self.input = input
            self.source = source
        }

        /// The next sample, or nil once there are no more, or the reader has failed.
        ///
        /// - Throws: ``DownloadPreparationError/unreadable`` when a sample can't take the copy's format.
        func next() throws -> CMSampleBuffer? {
            switch source {
            case .track(let output, let retagged):
                guard let sample = output.copyNextSampleBuffer() else { return nil }
                guard let retagged else { return sample }
                guard let described = DownloadedCopyWriter.sample(sample, describedBy: retagged) else {
                    throw DownloadPreparationError.unreadable
                }
                return described
            case .text(let samples):
                guard position < samples.count else { return nil }
                position += 1
                return samples[position - 1]
            }
        }
    }

    private static let logger = Logger(serafinCategory: "downloads")

    private let queue = DispatchQueue(label: "app.getserafin.serafin.downloads.copy")
    private let reader: AVAssetReader
    private let writer: AVAssetWriter
    private let feeds: [Feed]
    /// How many tracks still have samples to write.
    private var waiting: Int
    private var continuation: CheckedContinuation<Void, any Error>?
    /// Whether the copy has finished, failed or been cancelled.
    private var isOver = false

    init(asset: AVAsset, sources: [SourceTrack], subtitles: [TextTrack], output: URL) throws {
        do {
            reader = try AVAssetReader(asset: asset)
            writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        } catch {
            throw DownloadPreparationError.unreadable
        }
        var feeds: [Feed] = []
        var audio: [AVAssetWriterInput] = []
        var legible: [AVAssetWriterInput] = []
        for source in sources {
            let trackOutput = AVAssetReaderTrackOutput(track: source.track, outputSettings: nil)
            trackOutput.alwaysCopiesSampleData = false
            guard reader.canAdd(trackOutput) else { throw DownloadPreparationError.unreadable }
            reader.add(trackOutput)
            let retagged = source.format.flatMap { DownloadedCopyWriter.retagged($0) }
            let input = AVAssetWriterInput(
                mediaType: source.mediaType, outputSettings: nil, sourceFormatHint: retagged ?? source.format)
            input.expectsMediaDataInRealTime = false
            switch source.mediaType {
            case .video:
                input.transform = source.transform
                if source.timeScale > 0 {
                    input.mediaTimeScale = source.timeScale
                }
            case .audio:
                // AVAssetWriter keeps an audio track's own time scale.
                input.languageCode = DownloadedCopyWriter.languageCode(source.languageCode)
                input.extendedLanguageTag = source.extendedLanguageTag
                audio.append(input)
            default:
                if source.timeScale > 0 {
                    input.mediaTimeScale = source.timeScale
                }
                input.languageCode = DownloadedCopyWriter.languageCode(source.languageCode)
                input.extendedLanguageTag = source.extendedLanguageTag
                input.metadata = DownloadedCopyWriter.characteristicsMetadata(source.characteristics)
                legible.append(input)
            }
            guard writer.canAdd(input) else { throw DownloadPreparationError.unreadable }
            writer.add(input)
            feeds.append(Feed(input: input, source: .track(trackOutput, retagged: retagged)))
        }
        for subtitle in subtitles {
            guard let format = DownloadedCopyWriter.textFormat(forced: subtitle.track.isForced) else {
                throw DownloadPreparationError.unreadable
            }
            // A file with no cues still makes a track, so the copy's subtitles stay in the order the player expects.
            var stretches = subtitle.stretches
            if stretches.isEmpty {
                stretches = [TimedText.Stretch(start: .zero, end: .seconds(1), text: "")]
            }
            var samples: [CMSampleBuffer] = []
            for stretch in stretches {
                guard let sample = DownloadedCopyWriter.textSample(stretch, format: format) else {
                    throw DownloadPreparationError.unreadable
                }
                samples.append(sample)
            }
            let input = AVAssetWriterInput(mediaType: .subtitle, outputSettings: nil, sourceFormatHint: format)
            input.expectsMediaDataInRealTime = false
            input.mediaTimeScale = 1000
            input.languageCode = DownloadedCopyWriter.languageCode(subtitle.track.language)
            input.extendedLanguageTag = SubtitleRules.language(subtitle.track.language)
            var characteristics: [AVMediaCharacteristic] = []
            if subtitle.track.isForced {
                characteristics.append(.containsOnlyForcedSubtitles)
            }
            if subtitle.track.isHearingImpaired {
                characteristics += [.transcribesSpokenDialogForAccessibility, .describesMusicAndSoundForAccessibility]
            }
            input.metadata = DownloadedCopyWriter.characteristicsMetadata(characteristics)
            guard writer.canAdd(input) else { throw DownloadPreparationError.unreadable }
            writer.add(input)
            legible.append(input)
            feeds.append(Feed(input: input, source: .text(samples)))
        }
        if !audio.isEmpty {
            let group = AVAssetWriterInputGroup(inputs: audio, defaultInput: audio.first)
            if writer.canAdd(group) {
                writer.add(group)
            } else {
                // Without a group, only the first plays, rather than all of them at once.
                for input in audio.dropFirst() {
                    input.marksOutputTrackAsEnabled = false
                }
            }
        }
        if !legible.isEmpty {
            let group = AVAssetWriterInputGroup(inputs: legible, defaultInput: nil)
            if writer.canAdd(group) {
                writer.add(group)
            } else {
                // Without a group, no subtitles show until the player picks them.
                for input in legible {
                    input.marksOutputTrackAsEnabled = false
                }
            }
        }
        self.feeds = feeds
        waiting = feeds.count
    }

    /// Writes the copy.
    ///
    /// - Throws: ``DownloadPreparationError``, or `CancellationError` when the calling task is cancelled.
    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                queue.async { self.start(continuation) }
            }
        } onCancel: {
            queue.async { self.end(throwing: CancellationError()) }
        }
    }

    private func start(_ continuation: CheckedContinuation<Void, any Error>) {
        guard !isOver else {
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        guard writer.startWriting() else {
            end(throwing: Self.failure(writer.error))
            return
        }
        guard reader.startReading() else {
            end(throwing: Self.failure(reader.error))
            return
        }
        writer.startSession(atSourceTime: .zero)
        for index in feeds.indices {
            feeds[index].input.requestMediaDataWhenReady(on: queue) { [self] in
                feed(index)
            }
        }
    }

    /// Appends the samples of track `index` while its input takes them.
    private func feed(_ index: Int) {
        let track = feeds[index]
        guard !isOver, !track.isDone else { return }
        while track.input.isReadyForMoreMediaData {
            let next: CMSampleBuffer?
            do {
                next = try track.next()
            } catch {
                end(throwing: error)
                return
            }
            guard let sample = next else {
                if reader.status == .failed {
                    end(throwing: Self.failure(reader.error))
                    return
                }
                track.input.markAsFinished()
                track.isDone = true
                waiting -= 1
                if waiting == 0 {
                    finish()
                }
                return
            }
            guard track.input.append(sample) else {
                end(throwing: Self.failure(writer.error))
                return
            }
        }
    }

    private func finish() {
        writer.finishWriting { [self] in
            queue.async { self.finished() }
        }
    }

    private func finished() {
        guard !isOver else { return }
        guard writer.status == .completed else {
            end(throwing: Self.failure(writer.error))
            return
        }
        isOver = true
        continuation?.resume()
        continuation = nil
    }

    /// Stops the copy, unless it's over already, and throws `error` to the caller.
    private func end(throwing error: any Error) {
        guard !isOver else { return }
        isOver = true
        if reader.status == .reading {
            reader.cancelReading()
        }
        if writer.status == .writing {
            writer.cancelWriting()
        }
        continuation?.resume(throwing: error)
        continuation = nil
    }

    /// What an error from the reader or the writer means for the download.
    private static func failure(_ error: (any Error)?) -> DownloadPreparationError {
        guard let error = error as NSError? else { return .unreadable }
        logger.error("Could not write a downloaded copy: \(error.localizedDescription, privacy: .private)")
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        for candidate in [error, underlying].compactMap({ $0 }) {
            switch (candidate.domain, candidate.code) {
            case (AVFoundationErrorDomain, AVError.Code.diskFull.rawValue),
                (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError),
                (NSPOSIXErrorDomain, Int(ENOSPC)):
                return .storageFull
            default:
                continue
            }
        }
        return .unreadable
    }
}
