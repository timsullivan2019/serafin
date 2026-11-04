import Testing

@testable import SerafinDesign

@Suite struct VersionChoiceTests {
    @Test func theLineUnderAVersionJoinsItsBadgesAndSize() {
        let restoration = VersionChoice(
            id: "restoration", title: "4K Restoration", badges: ["4K", "Dolby Vision"], size: "58.2 GB")
        #expect(restoration.detail == "4K · Dolby Vision · 58.2 GB")
        #expect(VersionChoice(id: "broadcast", title: "1080p · H.264 · AAC", size: "8.4 GB").detail == "8.4 GB")
        #expect(VersionChoice(id: "archive", title: "SD", badges: ["CC"]).detail == "CC")
        #expect(VersionChoice(id: "bare", title: "Version 3").detail == nil)
    }
}
