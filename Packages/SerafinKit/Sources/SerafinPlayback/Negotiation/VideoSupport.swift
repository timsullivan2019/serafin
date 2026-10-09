import AVFoundation
import CoreMedia
import SerafinCore
import VideoToolbox
import os

/// The video this device plays beyond H.264 and HEVC, which every iPhone and iPad that runs Serafin decodes in
/// hardware: AV1, which only newer chips decode, and Dolby Vision.
///
/// It's read from the device: VideoToolbox says whether the chip decodes AV1 in hardware, and AVFoundation whether
/// AVPlayer plays a codec string. Decoding in software doesn't count, since it would drain the battery, so a device
/// without an AV1 decoder has the server convert AV1.
public struct VideoSupport: Equatable, Sendable {
    /// The highest AV1 level the device plays, as AV1's level index (13 is level 5.1, 4K at 60 frames a second), or
    /// nil when its chip has no AV1 decoder.
    public var av1Level: Int?
    /// Whether the device plays Dolby Vision in HEVC: profile 5, with nothing beneath it, and profile 8, with HDR10,
    /// HLG or SDR beneath it for other screens.
    public var dolbyVision: Bool
    /// Whether the device plays Dolby Vision in AV1, profile 10.
    public var dolbyVisionInAV1: Bool

    /// Creates a description of what a device plays.
    public init(av1Level: Int? = nil, dolbyVision: Bool = false, dolbyVisionInAV1: Bool = false) {
        self.av1Level = av1Level
        self.dolbyVision = dolbyVision
        self.dolbyVisionInAV1 = dolbyVisionInAV1
    }

    /// Neither AV1 nor Dolby Vision, so the server converts both.
    public static let none = VideoSupport()

    /// What this device plays, read the first time it's asked for, which ``prepare()`` does ahead of the first video.
    public static let current: VideoSupport = {
        var support = VideoSupport.none
        let took = ContinuousClock().measure { support = detect() }
        logger.debug(
            "AV1 up to level \(support.av1Level.map(String.init) ?? "none", privacy: .public), Dolby Vision \(support.dolbyVision, privacy: .public), in AV1 \(support.dolbyVisionInAV1, privacy: .public), read in \(took.loggedSeconds, privacy: .public)"
        )
        return support
    }()

    /// Reads ``current`` in the background, so the first video doesn't wait while the device is asked.
    public static func prepare() {
        Task.detached(priority: .utility) { _ = current }
    }

    /// The AV1 levels asked about, highest first: 6.3 down to 4.0.
    static let av1Levels = [19, 18, 17, 16, 15, 14, 13, 12, 9, 8]

    private static let logger = Logger(serafinCategory: "negotiation")

    /// Reads what a device plays.
    ///
    /// - Parameters:
    ///   - decodesInHardware: Whether the device's chip decodes a codec.
    ///   - plays: Whether AVPlayer plays MP4 video in a codec string, such as `dvh1.05.06`.
    static func detect(
        decodesInHardware: (CMVideoCodecType) -> Bool = { codec in
            timed("a hardware decoder for \(fourCharacters(codec))") { VTIsHardwareDecodeSupported(codec) }
        },
        plays: (String) -> Bool = { codecs in
            timed(codecs) { AVURLAsset.isPlayableExtendedMIMEType("video/mp4; codecs=\"\(codecs)\"") }
        }
    ) -> VideoSupport {
        // Dolby Vision is HEVC with extra metadata, and Apple's devices play profiles 5 and 8 alike, so either codec
        // string counts for both. The chip isn't asked about HEVC, which every device that runs Serafin decodes in
        // hardware: on an iPhone with iOS 27, that question took VideoToolbox 4.6 seconds the first time after launch.
        let dolbyVision = plays("dvh1.05.06") || plays("dvh1.08.06")
        var av1Level: Int?
        if decodesInHardware(kCMVideoCodecType_AV1) {
            // Main profile, in both 8-bit and 10-bit.
            av1Level = av1Levels.first { level in
                let index = level < 10 ? "0\(level)" : "\(level)"
                return plays("av01.0.\(index)M.08") && plays("av01.0.\(index)M.10")
            }
        }
        return VideoSupport(
            av1Level: av1Level,
            dolbyVision: dolbyVision,
            dolbyVisionInAV1: dolbyVision && av1Level != nil && plays("dav1.10.06")
        )
    }

    /// The device's answer to `ask`, logging how long it took when it took more than a tenth of a second.
    ///
    /// - Parameters:
    ///   - question: What's asked, such as a codec string, for the log.
    ///   - ask: Asks it.
    static func timed(_ question: String, _ ask: () -> Bool) -> Bool {
        var answer = false
        let took = ContinuousClock().measure { answer = ask() }
        if took > .milliseconds(100) {
            logger.debug("Asked about \(question, privacy: .public) in \(took.loggedSeconds, privacy: .public)")
        }
        return answer
    }

    /// A codec type's four characters, such as "hvc1".
    static func fourCharacters(_ code: CMVideoCodecType) -> String {
        String(decoding: [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: code >> $0) }, as: UTF8.self)
    }
}
