import Foundation
import JellyfinAPI
import SerafinCore
import SerafinDesign
import SerafinPlayback
import Testing

@testable import SerafinFeatures

/// Two versions of one movie: a 4K Dolby Vision file with Atmos and SDH subtitles, which the server names after its
/// file, and a 1080p file with French audio, which it doesn't name.
private enum Versions {
    static let uhd = MediaSourceInfo(
        defaultAudioStreamIndex: 1,
        id: "uhd",
        mediaStreams: [
            MediaStream(codec: "hevc", height: 2160, index: 0, type: .video, videoRangeType: .dovi, width: 3840),
            MediaStream(
                channels: 8, codec: "truehd", index: 1, language: "eng", profile: "Dolby TrueHD + Dolby Atmos",
                type: .audio),
            MediaStream(codec: "subrip", index: 2, isHearingImpaired: true, language: "eng", type: .subtitle),
        ],
        name: "4K Remux",
        size: 58_200_000_000
    )

    static let hd = MediaSourceInfo(
        defaultAudioStreamIndex: 1,
        id: "hd",
        mediaStreams: [
            MediaStream(codec: "h264", height: 1080, index: 0, type: .video, videoRangeType: .sdr, width: 1920),
            MediaStream(channels: 2, codec: "aac", index: 1, language: "fre", type: .audio),
        ],
        size: 8_400_000_000
    )

    static func dto(_ sources: [MediaSourceInfo], id: String = "movie", type: BaseItemKind = .movie) -> BaseItemDto {
        BaseItemDto(id: id, mediaSources: sources, name: "Sintel", type: type)
    }

    static func movie(_ sources: [MediaSourceInfo], id: String = "movie") throws -> MediaItem {
        try #require(MediaItem(dto(sources, id: id)))
    }
}

private func testDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "app.getserafin.serafin.tests.\(UUID().uuidString)"))
}

@Suite struct MediaVersionsTests {
    @Test func eachVersionShowsItsNameBadgesAndSize() {
        let choices = MediaVersions.choices(for: [Versions.uhd, Versions.hd])
        #expect(choices.map(\.id) == ["uhd", "hd"])
        #expect(choices.map(\.title) == ["4K Remux", "1080p · H.264 · AAC"])
        #expect(choices[0].badges == ["4K", "Dolby Vision", "Dolby Atmos", "7.1", "Lossless", "SDH"])
        #expect(choices[1].badges == ["HD"])
        let sizes: [String?] = [DownloadRow.size(58_200_000_000), DownloadRow.size(8_400_000_000)]
        #expect(choices.map(\.size) == sizes)
    }

    @Test func aVersionWithoutANameIsCalledByItsFormat() {
        var unnamed = Versions.uhd
        unnamed.name = nil
        #expect(MediaVersions.title(of: unnamed, number: 1) == "4K · HEVC · Dolby Vision · Atmos")
        unnamed.name = "  "
        #expect(MediaVersions.title(of: unnamed, number: 1) == "4K · HEVC · Dolby Vision · Atmos")
    }

    @Test func aVersionWithNeitherNameNorStreamsIsNumbered() {
        let bare = MediaSourceInfo(id: "bare")
        #expect(MediaVersions.format(of: bare) == nil)
        #expect(MediaVersions.title(of: bare, number: 3) == "Version 3")
    }

    @Test func theFormatNamesCodecsAsPeopleKnowThem() {
        #expect(MediaVersions.videoCodecName("h264") == "H.264")
        #expect(MediaVersions.videoCodecName("HEVC") == "HEVC")
        #expect(MediaVersions.videoCodecName("mpeg2video") == "MPEG-2")
        #expect(MediaVersions.videoCodecName("prores") == "PRORES")
        #expect(MediaVersions.videoCodecName(" ") == nil)
        #expect(MediaVersions.audioName(MediaStream(codec: "eac3", type: .audio)) == "Dolby Digital Plus")
        #expect(
            MediaVersions.audioName(
                MediaStream(codec: "eac3", profile: "Dolby Digital Plus + Dolby Atmos", type: .audio))
                == "Atmos")
        #expect(MediaVersions.audioName(MediaStream(type: .audio)) == nil)
    }

    @Test func aSizeTheServerDoesntKnowIsLeftOut() {
        var unknown = Versions.hd
        unknown.size = nil
        #expect(MediaVersions.size(of: unknown) == nil)
        unknown.size = 0
        #expect(MediaVersions.size(of: unknown) == nil)
    }

    @Test func aVersionWithoutAnIDCantBePickedSoIsLeftOut() {
        var anonymous = Versions.hd
        anonymous.id = nil
        #expect(MediaVersions.choices(for: [Versions.uhd, anonymous]).map(\.id) == ["uhd"])
    }

    @Test func eachVersionHasItsOwnBadges() {
        #expect(MediaBadges.badges(for: Versions.hd) == ["HD"])
        // An item's badges are its first version's.
        #expect(MediaBadges.badges(for: Versions.dto([Versions.hd, Versions.uhd])) == ["HD"])
    }
}

@Suite struct VersionInformationTests {
    private let english = Locale(identifier: "en_US")

    @Test func anItemWithSeveralVersionsHasNoFormatColumn() throws {
        let several = Versions.dto([Versions.uhd, Versions.hd])
        let card = try Versions.movie([Versions.uhd, Versions.hd]).card
        #expect(ItemInformation.columns(for: several, card: card, locale: english)[2].rows.isEmpty)
        let one = Versions.dto([Versions.hd])
        #expect(!ItemInformation.columns(for: one, card: card, locale: english)[2].rows.isEmpty)
    }

    @Test func theLanguagesAreThoseOfTheVersionAskedFor() throws {
        let item = Versions.dto([Versions.uhd, Versions.hd])
        let card = try Versions.movie([Versions.uhd, Versions.hd]).card
        #expect(
            ItemInformation.columns(for: item, card: card, version: Versions.hd, locale: english)[1].rows == [
                InformationColumns.Row(label: "Audio", items: ["French"], locale: english)
            ])
        // The first version's, when none is asked for.
        #expect(
            ItemInformation.columns(for: item, card: card, locale: english)[1].rows == [
                InformationColumns.Row(label: "Audio", items: ["English"], locale: english),
                InformationColumns.Row(label: "Subtitles", items: ["English"], locale: english),
            ])
    }
}

@Suite struct VersionMemoryTests {
    private let account = SessionKey(serverID: "server", userID: "user")

    @Test func theLastPickForAnItemIsKept() throws {
        let memory = VersionMemory(account: account, defaults: try testDefaults())
        #expect(memory.version(of: "movie") == nil)
        memory.remember("hd", for: "movie")
        #expect(memory.version(of: "movie") == "hd")
        memory.remember("uhd", for: "movie")
        #expect(memory.version(of: "movie") == "uhd")
        #expect(memory.version(of: "other") == nil)
    }

    @Test func theOldestPicksGoOnceTheLimitIsReached() throws {
        let memory = VersionMemory(account: account, defaults: try testDefaults())
        for index in 0..<VersionMemory.limit {
            memory.remember("version\(index)", for: "item\(index)")
        }
        // Picking again for the oldest makes it the newest, so the next oldest goes instead.
        memory.remember("again", for: "item0")
        memory.remember("new", for: "new")
        #expect(memory.version(of: "item0") == "again")
        #expect(memory.version(of: "item1") == nil)
        #expect(memory.version(of: "item2") == "version2")
        #expect(memory.version(of: "new") == "new")
    }

    @Test func eachAccountKeepsItsOwnPicks() throws {
        let defaults = try testDefaults()
        VersionMemory(account: account, defaults: defaults).remember("hd", for: "movie")
        let other = VersionMemory(account: SessionKey(serverID: "server", userID: "other"), defaults: defaults)
        #expect(other.version(of: "movie") == nil)
    }

    @Test func signingOutForgetsTheAccountsPicks() throws {
        let defaults = try testDefaults()
        let other = SessionKey(serverID: "server", userID: "other")
        VersionMemory(account: account, defaults: defaults).remember("hd", for: "movie")
        VersionMemory(account: other, defaults: defaults).remember("uhd", for: "movie")
        VersionMemory.forget(account, in: defaults)
        #expect(VersionMemory(account: account, defaults: defaults).version(of: "movie") == nil)
        #expect(VersionMemory(account: other, defaults: defaults).version(of: "movie") == "uhd")
    }

    @Test func removingAServerForgetsThePicksOfEveryAccountOnIt() throws {
        let defaults = try testDefaults()
        let elsewhere = SessionKey(serverID: "elsewhere", userID: "user")
        VersionMemory(account: account, defaults: defaults).remember("hd", for: "movie")
        VersionMemory(account: SessionKey(serverID: "server", userID: "other"), defaults: defaults)
            .remember("hd", for: "movie")
        VersionMemory(account: elsewhere, defaults: defaults).remember("uhd", for: "movie")
        VersionMemory.forget(server: "server", in: defaults)
        #expect(VersionMemory(account: account, defaults: defaults).version(of: "movie") == nil)
        #expect(
            VersionMemory(account: SessionKey(serverID: "server", userID: "other"), defaults: defaults)
                .version(of: "movie") == nil)
        #expect(VersionMemory(account: elsewhere, defaults: defaults).version(of: "movie") == "uhd")
    }

    @Test func withNoOneSignedInNothingIsKept() throws {
        let memory = VersionMemory(account: nil, defaults: try testDefaults())
        memory.remember("hd", for: "movie")
        #expect(memory.version(of: "movie") == nil)
    }
}

@MainActor @Suite struct DetailVersionsTests {
    private let account = SessionKey(serverID: "server", userID: "user")

    private func coordinator(_ defaults: UserDefaults) -> PlaybackCoordinator {
        PlaybackCoordinator(account: account, defaults: defaults, isOnExpensiveNetwork: { false })
    }

    @Test func aMovieWithOneVersionListsNone() async throws {
        let item = try Versions.movie([Versions.hd])
        let model = ItemDetailModel(showing: item, playable: nil)
        #expect(model.versions.isEmpty)
        #expect(model.versionChoices.isEmpty)
        await model.checkVersion(using: coordinator(try testDefaults()), downloaded: nil)
        #expect(model.checkedVersionID == nil)
        #expect(model.version(toPlay: item) == nil)
    }

    @Test func theVersionLastPickedIsChecked() async throws {
        let item = try Versions.movie([Versions.uhd, Versions.hd])
        let playback = coordinator(try testDefaults())
        playback.rememberVersion("hd", for: "movie")
        let model = ItemDetailModel(showing: item, playable: nil)
        #expect(model.versionChoices.map(\.id) == ["uhd", "hd"])

        await model.checkVersion(using: playback, downloaded: nil)
        #expect(model.checkedVersionID == "hd")
        #expect(model.version(toPlay: item) == "hd")
    }

    @Test func aDownloadedItemChecksTheVersionItsDownloadSaved() async throws {
        let item = try Versions.movie([Versions.uhd, Versions.hd])
        let playback = coordinator(try testDefaults())
        playback.rememberVersion("uhd", for: "movie")
        let model = ItemDetailModel(showing: item, playable: nil)

        // Its copy plays, whatever was picked before.
        await model.checkVersion(using: playback, downloaded: "hd")
        #expect(model.checkedVersionID == "hd")
        #expect(model.version(toPlay: item) == "hd")
        // A download of a version the server no longer lists checks nothing, so Play leaves it to the copy.
        await model.checkVersion(using: playback, downloaded: "renamed")
        #expect(model.checkedVersionID == nil)
        #expect(model.version(toPlay: item) == nil)
    }

    @Test func aDownloadPlaysItsCopyUnlessAnotherVersionIsAskedFor() {
        #expect(PlaybackCoordinator.playsCopy(of: "hd", for: nil))
        #expect(PlaybackCoordinator.playsCopy(of: "hd", for: "hd"))
        // As after picking the 4K version on the page of a movie downloaded in 1080p.
        #expect(!PlaybackCoordinator.playsCopy(of: "hd", for: "uhd"))
    }

    @Test func theBadgesAndLanguagesFollowTheCheckedVersion() async throws {
        let item = try Versions.movie([Versions.uhd, Versions.hd])
        let playback = coordinator(try testDefaults())
        let model = ItemDetailModel(showing: item, playable: nil)
        model.pickVersion("hd", playback: playback)
        #expect(model.badges == ["HD"])
        let source = try #require(item.source)
        #expect(model.information == ItemInformation.columns(for: source, card: item.card, version: Versions.hd))
    }

    @Test func aVersionPickedInTheListIsCheckedAndRemembered() async throws {
        let item = try Versions.movie([Versions.uhd, Versions.hd])
        let playback = coordinator(try testDefaults())
        let model = ItemDetailModel(showing: item, playable: nil)

        model.pickVersion("uhd", playback: playback)
        #expect(model.checkedVersionID == "uhd")
        #expect(playback.pickedVersion(of: "movie") == "uhd")
        // A version the item doesn't have isn't picked.
        model.pickVersion("gone", playback: playback)
        #expect(model.checkedVersionID == "uhd")
        #expect(playback.pickedVersion(of: "movie") == "uhd")
    }

    @Test func aPickForAVersionTheItemNoLongerHasIsPassedOver() async throws {
        let item = try Versions.movie([Versions.uhd, Versions.hd])
        let playback = coordinator(try testDefaults())
        playback.rememberVersion("renamed", for: "movie")
        let model = ItemDetailModel(showing: item, playable: nil)
        // Without a server to rank the versions, as in previews, nothing is checked and Play leaves it to the server.
        await model.checkVersion(using: playback, downloaded: nil)
        #expect(model.checkedVersionID == nil)
        #expect(model.version(toPlay: item) == nil)
    }

    @Test func onlyThePagesOwnItemPlaysTheCheckedVersion() async throws {
        let item = try Versions.movie([Versions.uhd, Versions.hd])
        let model = ItemDetailModel(showing: item, playable: nil)
        model.pickVersion("hd", playback: coordinator(try testDefaults()))
        #expect(model.version(toPlay: try Versions.movie([Versions.uhd, Versions.hd], id: "another")) == nil)
    }

    @Test func aShowsPageHasNoVersions() throws {
        let show = try #require(MediaItem(Versions.dto([Versions.uhd, Versions.hd], id: "show", type: .series)))
        let model = ItemDetailModel(showing: show, playable: nil)
        #expect(model.versions.isEmpty)
    }

    @Test func theCoordinatorRemembersPicksForTheAccount() throws {
        let defaults = try testDefaults()
        coordinator(defaults).rememberVersion("hd", for: "movie")
        #expect(coordinator(defaults).pickedVersion(of: "movie") == "hd")
        // Previews keep none.
        let preview = PlaybackCoordinator(defaults: defaults, isOnExpensiveNetwork: { false })
        preview.rememberVersion("uhd", for: "movie")
        #expect(preview.pickedVersion(of: "movie") == nil)
        #expect(coordinator(defaults).pickedVersion(of: "movie") == "hd")
    }
}
