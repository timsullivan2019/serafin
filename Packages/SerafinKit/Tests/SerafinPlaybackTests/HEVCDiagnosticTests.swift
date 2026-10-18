import AVFoundation
import CoreVideo
import Foundation
import Testing
import VideoToolbox

@testable import SerafinPlayback

/// A one-off look at how AVFoundation on this machine sees HEVC: what it says it plays, which of a set of ffmpeg-made
/// HEVC files it lists a video track for, and whether it can write and read HEVC of its own. Each finding is recorded
/// as an issue, so it shows in the log. Removed once the findings are in.
@Suite struct HEVCDiagnosticTests {
    private let directory = URL.temporaryDirectory.appending(path: "serafin-diagnostic-\(UUID().uuidString)")

    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "mp4", subdirectory: "Fixtures"))
    }

    /// What AVFoundation lists in the file at `url`.
    private func describe(_ url: URL, as name: String) async -> String {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.load(.tracks)
            var parts: [String] = []
            for track in tracks {
                let formats = try await track.load(.formatDescriptions)
                let playable = try await track.load(.isPlayable)
                let decodable = try await track.load(.isDecodable)
                let codes = formats.map { VideoSupport.fourCharacters(CMFormatDescriptionGetMediaSubType($0)) }
                parts.append("\(track.mediaType.rawValue) \(codes) playable \(playable) decodable \(decodable)")
            }
            let playable = try await asset.load(.isPlayable)
            return "DIAG \(name): \(tracks.count) tracks \(parts), asset playable \(playable)"
        } catch {
            return "DIAG \(name): \(error)"
        }
    }

    /// A copy of fixture `name`, retagged as the writer retags the file that arrived.
    private func retagged(_ name: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(name)-retagged.mp4")
        try FileManager.default.copyItem(at: try fixture(name), to: url)
        try SampleEntryTags.rewrite(fileAt: url)
        return url
    }

    /// Writes ten frames of `codec` with AVAssetWriter and describes what it wrote.
    private func written(_ codec: AVVideoCodecType) async -> String {
        let name = "Apple \(codec.rawValue)"
        let url = directory.appending(path: "apple-\(codec.rawValue).mov")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let settings: [String: Any] = [AVVideoCodecKey: codec, AVVideoWidthKey: 320, AVVideoHeightKey: 180]
            guard writer.canApply(outputSettings: settings, forMediaType: .video) else {
                return "DIAG \(name): settings refused"
            }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: 320,
                kCVPixelBufferHeightKey as String: 180,
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: input, sourcePixelBufferAttributes: attributes)
            writer.add(input)
            guard writer.startWriting() else {
                return "DIAG \(name): couldn't start, \(String(describing: writer.error))"
            }
            writer.startSession(atSourceTime: .zero)
            for frame in 0..<10 {
                var waited = 0
                while !input.isReadyForMoreMediaData && waited < 500 {
                    try await Task.sleep(for: .milliseconds(10))
                    waited += 1
                }
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(kCFAllocatorDefault, 320, 180, kCVPixelFormatType_32BGRA, nil, &buffer)
                guard let buffer else { return "DIAG \(name): no pixel buffer" }
                CVPixelBufferLockBaseAddress(buffer, [])
                if let base = CVPixelBufferGetBaseAddress(buffer) {
                    memset(base, Int32(frame * 20), CVPixelBufferGetDataSize(buffer))
                }
                CVPixelBufferUnlockBaseAddress(buffer, [])
                let time = CMTime(value: CMTimeValue(frame), timescale: 10)
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    return "DIAG \(name): frame \(frame) refused, \(String(describing: writer.error))"
                }
            }
            input.markAsFinished()
            await withCheckedContinuation { continuation in
                writer.finishWriting { continuation.resume() }
            }
            guard writer.status == .completed else {
                return "DIAG \(name): couldn't finish, \(String(describing: writer.error))"
            }
            return await describe(url, as: name)
        } catch {
            return "DIAG \(name): \(error)"
        }
    }

    @Test func howThisMachineSeesHEVC() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        var findings = [
            "DIAG plays hvc1 \(AVURLAsset.isPlayableExtendedMIMEType("video/mp4; codecs=\"hvc1.1.6.L30.90\""))",
            "DIAG plays avc1 \(AVURLAsset.isPlayableExtendedMIMEType("video/mp4; codecs=\"avc1.42E01E\""))",
            "DIAG decodes HEVC in hardware \(VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC))",
            "DIAG decodes H.264 in hardware \(VTIsHardwareDecodeSupported(kCMVideoCodecType_H264))",
        ]
        let names = [
            "DiagHvc1Plain", "DiagHvc1Large", "DiagHev1Plain", "DiagHvc1Info", "DiagHvc1Frag", "DiagHvc1LargeFrag",
            "HEVCFragmented", "H264AC3Fragmented",
        ]
        for name in names {
            findings.append(await describe(try fixture(name), as: name))
        }
        for name in ["DiagHev1Plain", "HEVCFragmented"] {
            findings.append(await describe(try retagged(name), as: "\(name) retagged"))
        }
        findings.append(await written(.hevc))
        findings.append(await written(.h264))
        for finding in findings {
            Issue.record(Comment(rawValue: finding))
        }
    }
}
