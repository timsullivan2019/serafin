import Foundation
import JellyfinAPI
import SerafinDesign
import Testing

@testable import SerafinFeatures

@Suite struct ItemInformationTests {
    private let english = Locale(identifier: "en_US")

    @Test func factsListTheReleaseRunTimeRatingGenresAndStudio() throws {
        let item = BaseItemDto(
            genres: ["Comedy", "Action"],
            id: "aaaa1111",
            name: "The General",
            officialRating: "NR",
            premiereDate: try Date("1926-12-31T00:00:00Z", strategy: .iso8601),
            productionYear: 1926,
            runTimeTicks: 79 * 60 * 10_000_000,
            studios: [NameIDPair(id: "s1", name: "Buster Keaton Productions")],
            type: .movie
        )
        let card = try #require(MediaItem(item)).card
        let rows = ItemInformation.facts(of: item, card: card, locale: english)
        #expect(rows.map(\.label) == ["Released", "Run Time", "Rated", "Genres", "Studio"])
        // Read in UTC, so a server's midnight release date never slips to the day before.
        #expect(rows[0].value == "December 31, 1926")
        #expect(rows[1].value == card.runtimeText)
        #expect(rows[2].value == "NR")
        #expect(rows[3].value == "Comedy, Action")
        #expect(rows[4].value == "Buster Keaton Productions")
    }

    @Test func aShowWithoutADateGivesTheYearItFirstAired() throws {
        let item = BaseItemDto(id: "show1111", name: "Sherlock Holmes", productionYear: 1954, type: .series)
        let card = try #require(MediaItem(item)).card
        let rows = ItemInformation.facts(of: item, card: card, locale: english)
        #expect(rows == [InformationColumns.Row(label: "First Aired", value: "1954")])
    }

    @Test func languagesAreListedOnceInTheFilesOrder() {
        let streams = [
            MediaStream(index: 0, type: .video),
            MediaStream(index: 1, language: "eng", type: .audio),
            MediaStream(index: 2, language: "fre", type: .audio),
            MediaStream(index: 3, language: "eng", type: .audio),
            MediaStream(index: 4, language: "und", type: .audio),
            MediaStream(index: 5, language: "spa", type: .subtitle),
            MediaStream(index: 6, language: "eng", type: .subtitle),
        ]
        let rows = ItemInformation.languages(in: streams, locale: english)
        #expect(
            rows == [
                InformationColumns.Row(label: "Audio", items: ["English", "French"], locale: english),
                InformationColumns.Row(label: "Subtitles", items: ["Spanish", "English"], locale: english),
            ])
        #expect(rows.map(\.value) == ["English, French", "Spanish, English"])
    }

    @Test func aRunTimeOfZeroIsLeftOut() throws {
        let item = BaseItemDto(
            id: "aaaa1111", name: "Earth", officialRating: "NR", productionYear: 1930, runTimeTicks: 0, type: .movie)
        let card = try #require(MediaItem(item)).card
        let rows = ItemInformation.facts(of: item, card: card, locale: english)
        #expect(rows.map(\.label) == ["Released", "Rated"])
    }

    @Test func aShowsRunTimeIsHowLongItsEpisodesRun() throws {
        let item = BaseItemDto(
            id: "show1111", name: "Sherlock Holmes", productionYear: 1954, runTimeTicks: 26 * 60 * 10_000_000,
            type: .series)
        let card = try #require(MediaItem(item)).card
        let runTime = try #require(ItemInformation.facts(of: item, card: card, locale: english).last)
        #expect(runTime.label == "Run Time")
        #expect(runTime.value == "\(try #require(card.runtimeText)) per episode")
    }

    @Test func rowsWithNothingToSayAreLeftOut() throws {
        let item = BaseItemDto(
            genres: ["", " "],
            id: "aaaa1111",
            mediaStreams: [MediaStream(codec: "", index: 1, type: .audio)],
            name: "Earth",
            officialRating: "",
            studios: [NameIDPair(id: "s1", name: "")],
            type: .movie
        )
        let card = try #require(MediaItem(item)).card
        let columns = ItemInformation.columns(for: item, card: card, locale: english)
        #expect(columns.allSatisfy { column in column.rows.allSatisfy { !$0.value.isEmpty } })
        #expect(columns.flatMap(\.rows).isEmpty)
    }

    @Test func formatDescribesTheVideoAndTheDefaultAudio() {
        let streams = [
            MediaStream(height: 1080, index: 0, type: .video, videoRangeType: .hdr10, width: 1920),
            MediaStream(channelLayout: "stereo", codec: "aac", index: 1, type: .audio),
            MediaStream(channelLayout: "5.1(side)", codec: "eac3", index: 2, type: .audio),
        ]
        let rows = ItemInformation.format(of: streams, defaultAudio: 2)
        #expect(
            rows == [
                InformationColumns.Row(label: "Video", value: "1080p · HDR10"),
                InformationColumns.Row(label: "Audio", value: "Dolby Digital Plus · 5.1"),
            ])
        #expect(ItemInformation.format(of: streams, defaultAudio: nil).last?.value == "AAC · Stereo")
    }

    @Test(arguments: [
        (3840, 2160, "4K"), (3840, 1600, "4K"), (1920, 1080, "1080p"), (1920, 800, "1080p"),
        (1280, 720, "720p"), (1280, 536, "720p"), (720, 480, "SD"),
    ])
    func resolutionsReadAsPeopleSayThem(width: Int, height: Int, name: String) {
        let video = MediaStream(height: height, type: .video, width: width)
        #expect(ItemInformation.resolution(of: video) == name)
    }

    @Test func aVideoWithoutASizeHasNoResolution() {
        #expect(ItemInformation.resolution(of: MediaStream(type: .video)) == nil)
        #expect(ItemInformation.resolution(of: MediaStream(height: 0, type: .video, width: 0)) == nil)
    }

    @Test func dynamicRangesAreNamedAndStandardRangeIsNot() {
        #expect(ItemInformation.rangeName(.dovi) == "Dolby Vision")
        #expect(ItemInformation.rangeName(.doviWithHDR10) == "Dolby Vision")
        #expect(ItemInformation.rangeName(.hdr10) == "HDR10")
        #expect(ItemInformation.rangeName(.hdr10Plus) == "HDR10+")
        #expect(ItemInformation.rangeName(.hlg) == "HLG")
        #expect(ItemInformation.rangeName(.sdr) == nil)
    }

    @Test func theFirstVersionsStreamsAreUsed() throws {
        let item = BaseItemDto(
            id: "aaaa1111",
            mediaSources: [
                MediaSourceInfo(
                    defaultAudioStreamIndex: 1,
                    mediaStreams: [
                        MediaStream(height: 2160, index: 0, type: .video, width: 3840),
                        MediaStream(codec: "ac3", index: 1, language: "ger", type: .audio),
                    ]
                )
            ],
            mediaStreams: [MediaStream(height: 480, index: 0, type: .video, width: 640)],
            name: "Metropolis",
            productionYear: 1927,
            type: .movie
        )
        let card = try #require(MediaItem(item)).card
        let columns = ItemInformation.columns(for: item, card: card, locale: english)
        #expect(columns.map(\.title) == ["Information", "Languages", "Format"])
        #expect(columns[1].rows == [InformationColumns.Row(label: "Audio", items: ["German"], locale: english)])
        #expect(columns[2].rows.map(\.value) == ["4K", "Dolby Digital"])
    }
}
