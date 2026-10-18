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

    /// Where a copy works from: a fixture copied as the file that arrived, which the writer retags in place.
    private var arrived: URL {
        directory.appending(path: "arrived.mp4")
    }

    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "mp4", subdirectory: "Fixtures"))
    }

    /// Copies fixture `name` to ``arrived``, as the file that arrived.
    private func arrive(_ name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try fixture(name), to: arrived)
    }

    /// Writes a copy of fixture `name` with `subtitles` added, each a WebVTT file's text and the track it becomes,
    /// signalling `dolbyVision`, and returns the copy.
    private func writeCopy(
        of name: String,
        adding subtitles: [(String, DownloadTrack)] = [],
        dolbyVision: DolbyVisionConfiguration? = nil
    ) async throws -> AVAsset {
        try arrive(name)
        var added: [AddedSubtitles] = []
        for (number, (text, track)) in subtitles.enumerated() {
            let file = directory.appending(path: "\(number).vtt")
            try Data(text.utf8).write(to: file)
            added.append(AddedSubtitles(track: track, file: file))
        }
        let output = directory.appending(path: "copy.mov")
        let job = DownloadPreparationJob(arrived: arrived, subtitles: added, output: output, dolbyVision: dolbyVision)
        try await DownloadedCopyWriter().prepare(job)
        return AVURLAsset(url: output)
    }

    /// The boxes `track`'s format carries beside its codec's own description, by type.
    private func atoms(of track: AVAssetTrack) async throws -> [String: Data] {
        let formats = try await track.load(.formatDescriptions)
        let format = try #require(formats.first)
        let atoms = CMFormatDescriptionGetExtension(
            format, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
        return (atoms as? [String: Any] ?? [:]).compactMapValues { $0 as? Data }
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
        #expect(try await atoms(of: video).keys.contains("hvcC"))
        #expect(try await copy.loadTracks(withMediaType: .audio).count == 1)
        let duration = try await copy.load(.duration)
        #expect(abs(duration.seconds - 2) < 0.1)

        // The file that arrived, retagged in place, which AVFoundation now reads.
        let original = AVURLAsset(url: arrived)
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

    @Test func theFileThatArrivedIsRetaggedInPlace() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        // As it arrives, tagged hev1, the video isn't among the tracks AVFoundation lists.
        try arrive("HEVCFragmented")
        let before = try Data(contentsOf: arrived)

        #expect(try SampleEntryTags.rewrite(fileAt: arrived) == 1)
        let after = try Data(contentsOf: arrived)
        #expect(after.count == before.count)
        // Only the four bytes of the video's tag change, in the sample description ffmpeg wrote.
        let changed = zip(before, after).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        #expect(changed.allSatisfy { (461..<465).contains($0) })
        #expect(String(decoding: after[461..<465], as: UTF8.self) == "hvc1")
        let videos = try await AVURLAsset(url: arrived).loadTracks(withMediaType: .video)
        let video = try #require(videos.first)
        #expect(try await subtype(of: video) == DownloadedCopyWriter.fourCharCode("hvc1"))
        // Once is enough.
        #expect(try SampleEntryTags.rewrite(fileAt: arrived) == 0)
    }

    @Test func filesWithoutHEVCTaggedHev1AreLeftAsTheyAre() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try arrive("H264AC3Fragmented")
        let before = try Data(contentsOf: arrived)
        #expect(try SampleEntryTags.rewrite(fileAt: arrived) == 0)
        #expect(try Data(contentsOf: arrived) == before)

        try Data("not a video".utf8).write(to: arrived)
        #expect(try SampleEntryTags.rewrite(fileAt: arrived) == 0)
    }

    @Test func boxesThatDontFitWhatHoldsThemAreLeftAlone() {
        func box(_ type: String, _ contents: [UInt8], size: Int? = nil) -> [UInt8] {
            let length = UInt32(size ?? 8 + contents.count)
            return withUnsafeBytes(of: length.bigEndian) { Array($0) } + Array(type.utf8) + contents
        }
        func track(_ descriptions: [UInt8]) -> [UInt8] {
            box("trak", box("mdia", box("minf", box("stbl", descriptions))))
        }
        let entry = box("hev1", [UInt8](repeating: 0, count: 8))
        let header: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 1]
        // Four boxes' headers down to the descriptions, then theirs, its own header, and the entry's size.
        #expect(SampleEntryTags.tagOffsets(inMovie: track(box("stsd", header + entry))).map(\.offset) == [52])
        // An entry claiming more than the box holding it, and a box claiming less than its own header.
        let overlong = box("stsd", header + box("hev1", [], size: 64))
        #expect(SampleEntryTags.tagOffsets(inMovie: track(overlong)).isEmpty)
        #expect(SampleEntryTags.tagOffsets(inMovie: box("trak", box("mdia", [], size: 4))).isEmpty)
        #expect(SampleEntryTags.boxes(in: [0, 0, 0], 0..<3).isEmpty)
    }

    @Test func dolbyVisionIsSignalledAsApplesOwnVideosSignalIt() throws {
        func format(_ code: String, atoms: [String: Data] = [:]) throws -> CMFormatDescription {
            let key = kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
            let extensions: CFDictionary? = atoms.isEmpty ? nil : [key: atoms] as CFDictionary
            var description: CMFormatDescription?
            let status = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: DownloadedCopyWriter.fourCharCode(code),
                width: 160,
                height: 90,
                extensions: extensions,
                formatDescriptionOut: &description
            )
            #expect(status == noErr)
            return try #require(description)
        }
        func atoms(of description: CMFormatDescription) -> [String: Data] {
            let atoms = CMFormatDescriptionGetExtension(
                description, extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms)
            return (atoms as? [String: Any] ?? [:]).compactMapValues { $0 as? Data }
        }
        let hevc = try format("hvc1", atoms: ["hvcC": Data([1, 2, 3])])
        let profile8 = DolbyVisionConfiguration(profile: 8, level: 6, baseLayerCompatibility: 1)
        let profile5 = DolbyVisionConfiguration(profile: 5, level: 6, baseLayerCompatibility: 0)
        let profile10 = DolbyVisionConfiguration(profile: 10, level: 6, baseLayerCompatibility: 0)

        // Profile 8 plays as HDR10 without Dolby Vision, so it stays HEVC, with its configuration beside.
        let withHDR10 = try #require(DownloadedCopyWriter.format(hevc, signalling: profile8))
        #expect(CMFormatDescriptionGetMediaSubType(withHDR10) == DownloadedCopyWriter.fourCharCode("hvc1"))
        #expect(atoms(of: withHDR10) == ["hvcC": Data([1, 2, 3]), "dvvC": profile8.record])
        #expect(CMVideoFormatDescriptionGetDimensions(withHDR10).width == 160)
        // Profile 5 shows as nothing without it.
        let alone = try #require(DownloadedCopyWriter.format(hevc, signalling: profile5))
        #expect(CMFormatDescriptionGetMediaSubType(alone) == DownloadedCopyWriter.fourCharCode("dvh1"))
        #expect(atoms(of: alone).keys.sorted() == ["dvcC", "hvcC"])
        let av1 = try #require(DownloadedCopyWriter.format(try format("av01"), signalling: profile10))
        #expect(CMFormatDescriptionGetMediaSubType(av1) == DownloadedCopyWriter.fourCharCode("dav1"))
        #expect(atoms(of: av1).keys.sorted() == ["dvvC"])

        #expect(DownloadedCopyWriter.format(try format("hvc1", atoms: ["dvvC": Data()]), signalling: profile8) == nil)
        #expect(DownloadedCopyWriter.format(try format("dvh1"), signalling: profile5) == nil)
        #expect(DownloadedCopyWriter.format(try format("avc1"), signalling: profile8) == nil)
    }

    @Test func theConfigurationIsWrittenAsDolbysRecord() {
        let profile8 = DolbyVisionConfiguration(profile: 8, level: 6, baseLayerCompatibility: 1)
        #expect(profile8.record == Data([1, 0, 0x10, 0x35, 0x10, 0] + [UInt8](repeating: 0, count: 18)))
        #expect(profile8.boxType == "dvvC")
        let profile5 = DolbyVisionConfiguration(
            versionMajor: 2, versionMinor: 1, profile: 5, level: 9, hasRPU: true, hasEnhancementLayer: true,
            hasBaseLayer: false, baseLayerCompatibility: 0)
        #expect(profile5.record.prefix(6) == Data([2, 1, 0x0A, 0x4E, 0, 0]))
        #expect(profile5.boxType == "dvcC")
        #expect(DolbyVisionConfiguration(profile: 20, level: 1, baseLayerCompatibility: 2).boxType == "dvwC")
        #expect(DolbyVisionConfiguration(profile: 200, level: 99, baseLayerCompatibility: 99).record.count == 24)
    }

    @Test func aCopyOfDolbyVisionVideoSaysSo() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile8 = DolbyVisionConfiguration(profile: 8, level: 1, baseLayerCompatibility: 1)
        let copy = try await writeCopy(of: "HEVCFragmented", dolbyVision: profile8)
        let videos = try await copy.loadTracks(withMediaType: .video)
        let video = try #require(videos.first)
        #expect(try await subtype(of: video) == DownloadedCopyWriter.fourCharCode("hvc1"))
        #expect(try await atoms(of: video)["dvvC"] == profile8.record)
        #expect(try frames(of: video, in: copy).all == 20)
    }

    @Test func aCopyOfDolbyVisionProfile5IsTaggedDvh1() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile5 = DolbyVisionConfiguration(profile: 5, level: 1, baseLayerCompatibility: 0)
        let copy = try await writeCopy(of: "HEVCFragmented", dolbyVision: profile5)
        let videos = try await copy.loadTracks(withMediaType: .video)
        let video = try #require(videos.first)
        #expect(try await subtype(of: video) == DownloadedCopyWriter.fourCharCode("dvh1"))
        #expect(try await atoms(of: video)["dvcC"] == profile5.record)
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
