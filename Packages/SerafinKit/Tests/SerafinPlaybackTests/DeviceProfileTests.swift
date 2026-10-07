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
        let json = try encoded(.serafin(maxBitrate: 8_000_000))
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

    @Test func av1AndDolbyVisionAreNotPlayedDirectly() throws {
        let profile = DeviceProfile.serafin()
        let direct = try #require(profile.directPlayProfiles?.first)
        #expect(direct.videoCodec?.contains("av1") == false)
        let hevc = try #require(profile.codecProfiles?.first { $0.codec == "hevc" })
        let ranges = try #require(hevc.conditions?.first { $0.property == .videoRangeType }?.value)
        #expect(!ranges.contains("DOVI"))
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
