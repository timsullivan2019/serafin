import AVFoundation
import Foundation
import SerafinCore
import Testing

@testable import SerafinPlayback

/// Copies written from small videos in `Fixtures/`, made with ffmpeg 6.1 from its test pattern and tones, two seconds
/// at 160 × 90 and ten frames a second:
///
/// - `HEVCFragmented.mp4`: HEVC tagged `hev1`, with B-frames, and AAC, as fragmented MP4, the way Jellyfin sends a
///   video it converts for a download (`-movflags frag_keyframe+empty_moov+delay_moov`).
/// - `H264AC3Fragmented.mp4`: H.264 and AC-3, the same way.
/// - `OriginalWithSubtitles.mp4`: H.264, English and French AAC, English 3GPP text subtitles and two chapters, as an
///   MP4 a library might hold.
@Suite struct DownloadedCopyWriterTests {
    private let directory = URL.temporaryDirectory.appending(path: "serafin-tests-\(UUID().uuidString)")

    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "mp4", subdirectory: "Fixtures"))
    }

    /// Writes a copy of fixture `name` with `subtitles` added, each a WebVTT file's text and the track it becomes, and
    /// returns the copy.
    private func writeCopy(of name: String, adding subtitles: [(String, DownloadTrack)] = []) async throws -> AVAsset {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var added: [AddedSubtitles] = []
        for (number, (text, track)) in subtitles.enumerated() {
            let file = directory.appending(path: "\(number).vtt")
            try Data(text.utf8).write(to: file)
            added.append(AddedSubtitles(track: track, file: file))
        }
        let output = directory.appending(path: "copy.mov")
        let job = DownloadPreparationJob(arrived: try fixture(name), subtitles: added, output: output)
        try await DownloadedCopyWriter().prepare(job)
        return AVURLAsset(url: output)
    }

    /// The four-character code of `track`'s format, such as `hvc1`.
    private func subtype(of track: AVAssetTrack) async throws -> FourCharCode? {
        let formats = try await track.load(.formatDescriptions)
        return formats.first.map { CMFormatDescriptionGetMediaSubType($0) }
    }

    /// How many frames `track` of `asset` has, and how many of them are key frames.
    private func frames(of track: AVAssetTrack, in asset: AVAsset) throws -> (all: Int, key: Int) {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var all = 0
        var key = 0
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            all += 1
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            let first = (attachments as? [[CFString: Any]])?.first
            if first?[kCMSampleAttachmentKey_NotSync] as? Bool != true {
                key += 1
            }
        }
        return (all, key)
    }

    /// The text, start and end of each sample in subtitle `track` of `asset`.
    private func stretches(of track: AVAssetTrack, in asset: AVAsset) throws -> [TimedText.Stretch] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var stretches: [TimedText.Stretch] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: length)
            let status = bytes.withUnsafeMutableBytes { buffer -> OSStatus in
                guard let base = buffer.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
            }
            guard status == kCMBlockBufferNoErr, bytes.count >= 2 else { continue }
            let textLength = Int(bytes[0]) << 8 | Int(bytes[1])
            let text = String(decoding: bytes.dropFirst(2).prefix(textLength), as: UTF8.self)
            let start = Duration(CMSampleBufferGetPresentationTimeStamp(sample))
            let end = start + Duration(CMSampleBufferGetDuration(sample))
            stretches.append(TimedText.Stretch(start: start, end: end, text: text))
        }
        return stretches
    }

    /// The languages of the options in `group`, as the player reads them. AVFoundation offers a subtitle track that
    /// isn't all forced twice: in full, and showing only its forced subtitles.
    private func languages(of group: AVMediaSelectionGroup?) -> Set<String> {
        Set(group?.options.compactMap { SubtitleRules.language($0.extendedLanguageTag ?? $0.locale?.identifier) } ?? [])
    }

    /// The language of each of `tracks`, as the player reads them.
    private func languages(of tracks: [AVAssetTrack]) async throws -> [String?] {
        var languages: [String?] = []
        for track in tracks {
            let (tag, code) = try await track.load(.extendedLanguageTag, .languageCode)
            languages.append(SubtitleRules.language(tag ?? code))
        }
        return languages
    }

    @Test func hevcTaggedHev1IsCopiedAsHvc1WithItsKeyFrames() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = try await writeCopy(of: "HEVCFragmented")
        let videos = try await copy.loadTracks(withMediaType: .video)
        let video = try #require(videos.first)
        #expect(try await subtype(of: video) == DownloadedCopyWriter.fourCharCode("hvc1"))
        #expect(try await copy.loadTracks(withMediaType: .audio).count == 1)
        let duration = try await copy.load(.duration)
        #expect(abs(duration.seconds - 2) < 0.1)

        let original = AVURLAsset(url: try fixture("HEVCFragmented"))
        let originalVideos = try await original.loadTracks(withMediaType: .video)
        let originalVideo = try #require(originalVideos.first)
        let copied = try frames(of: video, in: copy)
        let arrived = try frames(of: originalVideo, in: original)
        #expect(copied.all == arrived.all)
        #expect(copied.key == arrived.key)
        #expect(copied.key < copied.all)
    }

    @Test func addedSubtitlesBecomeTextTracksThatShowNoneUntilPicked() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let english = """
            WEBVTT

            00:00:00.500 --> 00:00:01.500
            <i>Hello</i>
            """
        let french = "WEBVTT\n\n00:00:01.000 --> 00:00:01.800\nBonjour\n"
        let copy = try await writeCopy(
            of: "H264AC3Fragmented",
            adding: [
                (english, DownloadTrack(index: 2, codec: "subrip", language: "eng", isHearingImpaired: true)),
                (french, DownloadTrack(index: 3, codec: "subrip", language: "fre", isForced: true)),
            ])
        let audio = try await copy.loadTracks(withMediaType: .audio)
        #expect(audio.count == 1)
        if let track = audio.first {
            #expect(try await subtype(of: track) == DownloadedCopyWriter.fourCharCode("ac-3"))
        }

        let group = try await copy.loadMediaSelectionGroup(for: .legible)
        #expect(languages(of: group) == ["en", "fr"])
        #expect(group?.defaultOption == nil)
        #expect(group?.options.first?.hasMediaCharacteristic(.transcribesSpokenDialogForAccessibility) == true)
        #expect(group?.options.last?.hasMediaCharacteristic(.containsOnlyForcedSubtitles) == true)

        let subtitles = try await copy.loadTracks(withMediaType: .subtitle)
        #expect(try await languages(of: subtitles) == ["en", "fr"])
        for track in subtitles {
            #expect(try await track.load(.isEnabled) == false)
        }
        let first = try #require(subtitles.first)
        let shown = try stretches(of: first, in: copy)
        #expect(
            shown == [
                TimedText.Stretch(start: .zero, end: .milliseconds(500), text: ""),
                TimedText.Stretch(start: .milliseconds(500), end: .milliseconds(1500), text: "Hello"),
            ])
    }

    @Test func aCopyKeepsTheFilesOwnTracksInOrderButNotItsChapters() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let german = "WEBVTT\n\n00:00:00.200 --> 00:00:01.000\nHallo\n"
        let copy = try await writeCopy(
            of: "OriginalWithSubtitles", adding: [(german, DownloadTrack(index: 5, codec: "subrip", language: "ger"))])
        let tracks = try await copy.load(.tracks)
        #expect(tracks.map(\.mediaType) == [.video, .audio, .audio, .subtitle, .subtitle])

        let audible = try await copy.loadMediaSelectionGroup(for: .audible)
        #expect(languages(of: audible) == ["en", "fr"])
        let audio = try await copy.loadTracks(withMediaType: .audio)
        var enabled: [Bool] = []
        for track in audio {
            enabled.append(try await track.load(.isEnabled))
        }
        #expect(enabled == [true, false])

        let legible = try await copy.loadMediaSelectionGroup(for: .legible)
        #expect(languages(of: legible) == ["en", "de"])
        #expect(legible?.defaultOption == nil)
        let subtitles = try await copy.loadTracks(withMediaType: .subtitle)
        #expect(try await languages(of: subtitles) == ["en", "de"])
        let original = try #require(subtitles.first)
        let shown = try stretches(of: original, in: copy)
        #expect(shown.map(\.text).filter { !$0.isEmpty } == ["Hello", "Goodbye"])
    }

    @Test func oneAddedTrackOfSubtitlesCanStillBePicked() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let english = "WEBVTT\n\n00:00:00.500 --> 00:00:01.000\nHello\n"
        let copy = try await writeCopy(
            of: "HEVCFragmented", adding: [(english, DownloadTrack(index: 2, codec: "subrip", language: "eng"))])
        let group = try await copy.loadMediaSelectionGroup(for: .legible)
        #expect(languages(of: group) == ["en"])
        #expect(group?.defaultOption == nil)
        #expect(try await languages(of: copy.loadTracks(withMediaType: .subtitle)) == ["en"])
    }

    @Test func subtitlesWithNothingToShowStillMakeATrack() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = try await writeCopy(
            of: "HEVCFragmented",
            adding: [
                ("WEBVTT\n", DownloadTrack(index: 2, codec: "subrip", language: "eng")),
                ("not subtitles", DownloadTrack(index: 3, codec: "subrip", language: "spa")),
            ])
        #expect(try await languages(of: copy.loadTracks(withMediaType: .subtitle)) == ["en", "es"])
    }

    @Test func aFileThatIsntAVideoCantBeCopied() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let arrived = directory.appending(path: "arrived.mp4")
        try Data("not a video".utf8).write(to: arrived)
        let output = directory.appending(path: "copy.mov")
        await #expect(throws: DownloadPreparationError.unreadable) {
            try await DownloadedCopyWriter().prepare(
                DownloadPreparationJob(arrived: arrived, subtitles: [], output: output))
        }
        #expect(!FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test func everyHEVCFrameTakesTheRetaggedFormatAndKeepsItsTiming() async throws {
        let asset = AVURLAsset(url: try fixture("HEVCFragmented"))
        let videos = try await asset.loadTracks(withMediaType: .video)
        let video = try #require(videos.first)
        let formats = try await video.load(.formatDescriptions)
        let arrived = try #require(formats.first)
        let retagged = try #require(DownloadedCopyWriter.retagged(arrived))
        let extensions = Set((CMFormatDescriptionGetExtensions(retagged) as? [CFString: Any] ?? [:]).keys)
        #expect(!extensions.contains(kCMFormatDescriptionExtension_VerbatimISOSampleEntry))
        #expect(!extensions.contains(kCMFormatDescriptionExtension_VerbatimSampleDescription))
        #expect(extensions.contains(kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms))

        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
        reader.add(output)
        #expect(reader.startReading())
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            let described = try #require(
                DownloadedCopyWriter.sample(sample, describedBy: retagged), "Frame \(frames) wasn't retagged")
            let format = try #require(CMSampleBufferGetFormatDescription(described))
            #expect(CMFormatDescriptionGetMediaSubType(format) == DownloadedCopyWriter.fourCharCode("hvc1"))
            #expect(CMSampleBufferGetPresentationTimeStamp(described) == CMSampleBufferGetPresentationTimeStamp(sample))
            #expect(CMSampleBufferGetDecodeTimeStamp(described) == CMSampleBufferGetDecodeTimeStamp(sample))
            #expect(CMSampleBufferGetTotalSampleSize(described) == CMSampleBufferGetTotalSampleSize(sample))
            frames += 1
        }
        #expect(frames == 20)
    }

    /// The HEVC fixture's video alone, copied frame by frame into a movie the way the copy is written, recording what
    /// the writer says when it stops.
    @Test func hevcVideoAloneIsWrittenAsHvc1() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let asset = AVURLAsset(url: try fixture("HEVCFragmented"))
        let videos = try await asset.loadTracks(withMediaType: .video)
        let video = try #require(videos.first)
        let formats = try await video.load(.formatDescriptions)
        let arrived = try #require(formats.first)
        let retagged = try #require(DownloadedCopyWriter.retagged(arrived))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: video, outputSettings: nil)
        reader.add(output)
        let writer = try AVAssetWriter(outputURL: directory.appending(path: "video.mov"), fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: retagged)
        input.expectsMediaDataInRealTime = false
        try #require(writer.canAdd(input))
        writer.add(input)
        try #require(writer.startWriting(), "Not started: \(String(describing: writer.error))")
        try #require(reader.startReading())
        writer.startSession(atSourceTime: .zero)
        var frame = 0
        while let sample = output.copyNextSampleBuffer() {
            guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
            let described = try #require(DownloadedCopyWriter.sample(sample, describedBy: retagged))
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(1))
            }
            try #require(input.append(described), "Frame \(frame) refused: \(String(describing: writer.error))")
            frame += 1
        }
        input.markAsFinished()
        await writer.finishWriting()
        #expect(writer.status == .completed, "Not finished: \(String(describing: writer.error))")
    }

    @Test func onlyHEVCAndDolbyVisionTaggedForStreamingAreRetagged() throws {
        func format(_ code: String) throws -> CMFormatDescription {
            var description: CMFormatDescription?
            let status = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: DownloadedCopyWriter.fourCharCode(code),
                width: 160,
                height: 90,
                extensions: nil,
                formatDescriptionOut: &description
            )
            #expect(status == noErr)
            return try #require(description)
        }
        let hev1 = try format("hev1")
        let dvhe = try format("dvhe")
        let hvc1 = try format("hvc1")
        let avc1 = try format("avc1")
        let fromHev1 = try #require(DownloadedCopyWriter.retagged(hev1))
        #expect(CMFormatDescriptionGetMediaSubType(fromHev1) == DownloadedCopyWriter.fourCharCode("hvc1"))
        #expect(CMVideoFormatDescriptionGetDimensions(fromHev1).width == 160)
        let fromDvhe = try #require(DownloadedCopyWriter.retagged(dvhe))
        #expect(CMFormatDescriptionGetMediaSubType(fromDvhe) == DownloadedCopyWriter.fourCharCode("dvh1"))
        #expect(DownloadedCopyWriter.retagged(hvc1) == nil)
        #expect(DownloadedCopyWriter.retagged(avc1) == nil)
    }

    @Test func forcedSubtitlesAreMarkedForcedInTheirFormat() throws {
        let forced = try #require(DownloadedCopyWriter.textFormat(forced: true))
        let plain = try #require(DownloadedCopyWriter.textFormat(forced: false))
        #expect(CMFormatDescriptionGetMediaType(forced) == kCMMediaType_Subtitle)
        #expect(CMFormatDescriptionGetMediaSubType(forced) == DownloadedCopyWriter.fourCharCode("tx3g"))
        func flags(_ format: CMFormatDescription) -> UInt32 {
            let value = CMFormatDescriptionGetExtension(
                format, extensionKey: kCMTextFormatDescriptionExtension_DisplayFlags)
            return (value as? NSNumber)?.uint32Value ?? 0
        }
        #expect(flags(forced) == 0x8000_0000)
        #expect(flags(plain) == 0)
    }

    @Test func languagesTakeTheCodesQuickTimeMoviesCarry() {
        #expect(DownloadedCopyWriter.languageCode("fre") == "fra")
        #expect(DownloadedCopyWriter.languageCode("en") == "eng")
        #expect(DownloadedCopyWriter.languageCode("und") == nil)
        #expect(DownloadedCopyWriter.languageCode(nil) == nil)
    }
}
