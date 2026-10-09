import CoreMedia
import Foundation
import JellyfinAPI
import Testing

@testable import SerafinPlayback

/// The device profile decides what plays untouched and what the server converts, so any change to it is a
/// deliberate diff against `Fixtures/DeviceProfile.json`. Run with `SERAFIN_RECORD_SNAPSHOTS=1` to rewrite the
/// snapshot after a change you mean to make.
@Suite struct DeviceProfileTests {
    private func encoded(_ profile: DeviceProfile) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(profile), as: UTF8.self) + "\n"
    }

    @Test func profileMatchesTheSnapshot() throws {
        let json = try encoded(.serafin(maxBitrate: 8_000_000, video: .none))
        let snapshot = URL(filePath: #filePath).deletingLastPathComponent().appending(
            path: "Fixtures/DeviceProfile.json")
        if ProcessInfo.processInfo.environment["SERAFIN_RECORD_SNAPSHOTS"] == "1" {
            try json.write(to: snapshot, atomically: true, encoding: .utf8)
        }
        let expected = try String(contentsOf: try #require(Fixture.url("DeviceProfile")), encoding: .utf8)
        #expect(json == expected)
    }

    @Test func noCapStreamsAtUpTo120Megabits() {
        let profile = DeviceProfile.serafin()
        #expect(profile.maxStreamingBitrate == 120_000_000)
        #expect(profile.maxStaticBitrate == 120_000_000)
    }

    /// The values of `property`'s condition in the profile for `codec`.
    private func condition(_ property: ProfileConditionValue, of codec: String, in profile: DeviceProfile) throws
        -> String
    {
        let codecProfile = try #require(profile.codecProfiles?.first { $0.codec == codec })
        return try #require(codecProfile.conditions?.first { $0.property == property }?.value)
    }

    @Test func withoutAV1OrDolbyVisionTheServerConvertsThem() throws {
        let profile = DeviceProfile.serafin(video: .none)
        #expect(profile.directPlayProfiles?.first?.videoCodec == "h264,hevc")
        #expect(profile.transcodingProfiles?.first?.videoCodec == "hevc,h264")
        #expect(profile.codecProfiles?.map(\.codec) == ["h264", "hevc"])
        #expect(try condition(.videoRangeType, of: "hevc", in: profile) == "SDR|HDR10|HDR10Plus|HLG")
        #expect(try condition(.videoCodecTag, of: "hevc", in: profile) == "hvc1")
    }

    @Test func dolbyVisionPlaysOnADeviceThatShowsIt() throws {
        let profile = DeviceProfile.serafin(video: VideoSupport(dolbyVision: true))
        #expect(
            try condition(.videoRangeType, of: "hevc", in: profile)
                == "SDR|HDR10|HDR10Plus|HLG|DOVI|DOVIWithHDR10|DOVIWithHLG|DOVIWithSDR|DOVIWithHDR10Plus")
        #expect(try condition(.videoCodecTag, of: "hevc", in: profile) == "hvc1|dvh1")
        // Profile 7 has a second layer AVPlayer can't decode, so the server sends something else.
        #expect(try !condition(.videoRangeType, of: "hevc", in: profile).contains("DOVIWithEL"))
        #expect(profile.directPlayProfiles?.first?.videoCodec == "h264,hevc")
    }

    @Test func av1PlaysAndIsCopiedWhereTheChipDecodesIt() throws {
        let profile = DeviceProfile.serafin(video: VideoSupport(av1Level: 13, dolbyVision: true))
        #expect(profile.directPlayProfiles?.first?.videoCodec == "h264,hevc,av1")
        // HEVC stays first, so a server that has to convert still makes HEVC.
        #expect(profile.transcodingProfiles?.first?.videoCodec == "hevc,av1,h264")
        #expect(try condition(.videoLevel, of: "av1", in: profile) == "13")
        #expect(try condition(.videoProfile, of: "av1", in: profile) == "main")
        #expect(try condition(.videoRangeType, of: "av1", in: profile) == "SDR|HDR10|HDR10Plus|HLG")
    }

    @Test func dolbyVisionInAV1PlaysWhereTheDeviceDecodesBoth() throws {
        let profile = DeviceProfile.serafin(
            video: VideoSupport(av1Level: 17, dolbyVision: true, dolbyVisionInAV1: true))
        #expect(try condition(.videoRangeType, of: "av1", in: profile).contains("DOVIWithHDR10"))
    }
}

@Suite struct VideoSupportTests {
    /// A device whose chip decodes `hardware` and whose AVPlayer plays every codec string `plays` accepts.
    private func detect(hardware: Set<CMVideoCodecType>, plays: @escaping (String) -> Bool) -> VideoSupport {
        VideoSupport.detect(decodesInHardware: { hardware.contains($0) }, plays: plays)
    }

    @Test func aChipWithoutAnAV1DecoderLeavesAV1ToTheServer() {
        let support = detect(hardware: [kCMVideoCodecType_HEVC]) { _ in true }
        #expect(support.av1Level == nil)
        #expect(support.dolbyVision)
        #expect(!support.dolbyVisionInAV1)
    }

    @Test func theAV1LevelIsTheHighestPlayedInEightAndTenBit() {
        let support = detect(hardware: [kCMVideoCodecType_HEVC, kCMVideoCodecType_AV1]) { codecs in
            ["av01.0.18M.08", "av01.0.17M.08", "av01.0.17M.10", "av01.0.13M.08", "av01.0.13M.10"].contains(codecs)
        }
        #expect(support.av1Level == 17)
    }

    @Test func lowAV1LevelsAreAskedAboutWithTwoDigits() {
        let support = detect(hardware: [kCMVideoCodecType_AV1]) { codecs in
            codecs == "av01.0.08M.08" || codecs == "av01.0.08M.10"
        }
        #expect(support.av1Level == 8)
    }

    @Test func dolbyVisionNeedsTheHEVCDecoderAndEitherProfile() {
        #expect(detect(hardware: [kCMVideoCodecType_HEVC]) { $0 == "dvh1.05.06" }.dolbyVision)
        #expect(detect(hardware: [kCMVideoCodecType_HEVC]) { $0 == "dvh1.08.06" }.dolbyVision)
        #expect(!detect(hardware: [kCMVideoCodecType_HEVC]) { $0.hasPrefix("hvc1") }.dolbyVision)
        #expect(!detect(hardware: []) { _ in true }.dolbyVision)
    }

    @Test func dolbyVisionInAV1NeedsAV1AndDolbyVision() {
        let everything = detect(hardware: [kCMVideoCodecType_HEVC, kCMVideoCodecType_AV1]) { _ in true }
        #expect(everything == VideoSupport(av1Level: 19, dolbyVision: true, dolbyVisionInAV1: true))
        let noDolbyVision = detect(hardware: [kCMVideoCodecType_AV1]) { _ in true }
        #expect(!noDolbyVision.dolbyVisionInAV1)
    }

    @Test func timingAQuestionKeepsItsAnswer() {
        #expect(VideoSupport.timed("dvh1.05.06") { true })
        #expect(!VideoSupport.timed("dav1.10.06") { false })
        #expect(VideoSupport.fourCharacters(kCMVideoCodecType_HEVC) == "hvc1")
        #expect(VideoSupport.fourCharacters(kCMVideoCodecType_AV1) == "av01")
    }

    @Test func timesAreLoggedInSecondsToTwoPlaces() {
        #expect(Duration.milliseconds(350).loggedSeconds == "0.35 s")
        #expect(Duration.seconds(7).loggedSeconds == "7.00 s")
    }
}

@Suite struct TicksTests {
    @Test func secondsBecomeTenMillionTicks() {
        #expect(Ticks.from(.seconds(1)) == 10_000_000)
        #expect(Ticks.from(.milliseconds(1500)) == 15_000_000)
        #expect(Ticks.from(.zero) == 0)
    }

    @Test func ticksBecomeDurations() {
        #expect(Ticks.duration(10_000_000) == .seconds(1))
        #expect(Ticks.duration(23_040_000_000) == .seconds(2304))
    }

    @Test func aRoundTripKeepsWholeTicks() {
        let ticks = 57_600_123_400
        #expect(Ticks.from(Ticks.duration(ticks)) == ticks)
    }
}

/// Responses in the shape Jellyfin 10.10 returns, in `Fixtures/`.
enum Fixture {
    static func url(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
    }

    static func json(_ name: String) throws -> String {
        try String(contentsOf: try #require(url(name)), encoding: .utf8)
    }
}
