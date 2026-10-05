import Foundation
import JellyfinAPI
import Testing

@testable import SerafinCore

@Suite struct LanguagePreferencesTests {
    /// A user's settings as Jellyfin sends them, with one this version of Serafin doesn't know.
    private static let me = #"""
        {"Name":"Alice","Id":"user-1","Configuration":{"AudioLanguagePreference":"","SubtitleLanguagePreference":"fre",
        "SubtitleMode":"Smart","PlayDefaultAudioTrack":true,"OrderedViews":["a","b"],"SomethingNewer":{"Level":3}}}
        """#

    private func library(on host: String) throws -> LibraryRepository {
        let configuration = JellyfinClient.Configuration(
            url: try #require(URL(string: "https://\(host)")),
            accessToken: "token-1",
            client: "Serafin",
            deviceName: "iPhone",
            deviceID: "device-1",
            version: "0.1.0"
        )
        let client = JellyfinClient(configuration: configuration, sessionConfiguration: StubURLProtocol.configuration())
        let errors = ServerErrors(pinning: PinningDelegate(pins: PinStore(secrets: InMemorySecretStore())))
        return LibraryRepository(client: client, userID: "user-1", errors: errors)
    }

    @Test func theAccountsPreferencesAreReadFromTheServer() async throws {
        let host = "languages-read.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Users/Me", .json(200, Self.me))
        let preferences = try await library(on: host).languagePreferences()
        #expect(preferences == LanguagePreferences(audio: nil, subtitles: "fre", subtitleMode: .smart))
    }

    @Test func savingChangesOnlyThePreferencesAndKeepsEveryOtherSetting() async throws {
        let host = "languages-save.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Users/Me", .json(200, Self.me))
        StubURLProtocol.stub("\(host):443", path: "/Users/Configuration", .json(204, ""))
        try await library(on: host).setLanguagePreferences(
            LanguagePreferences(audio: "jpn", subtitles: nil, subtitleMode: .always))

        let sent = try #require(StubURLProtocol.requests(to: "\(host):443", path: "/Users/Configuration").first)
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.query("userId") == "user-1")
        let body = try #require(JSONSerialization.jsonObject(with: sent.body) as? [String: Any])
        #expect(body["AudioLanguagePreference"] as? String == "jpn")
        #expect(body["SubtitleLanguagePreference"] is NSNull)
        #expect(body["SubtitleMode"] as? String == "Always")
        #expect(body["PlayDefaultAudioTrack"] as? Bool == true)
        #expect(body["OrderedViews"] as? [String] == ["a", "b"])
        #expect((body["SomethingNewer"] as? [String: Any])?["Level"] as? Int == 3)
    }

    @Test func noLanguageSavedAsAnEmptyStringStaysAsItIs() {
        let configuration: [String: AnyJSON] = [
            "AudioLanguagePreference": .string(""), "SubtitleMode": .string("None"),
        ]
        let preferences = LanguagePreferences(configuration: configuration)
        #expect(preferences.audio == nil)
        #expect(preferences.subtitleMode == SubtitlePlaybackMode.none)
        let applied = preferences.applied(to: configuration)
        #expect(applied["AudioLanguagePreference"] == .string(""))
        #expect(applied["SubtitleLanguagePreference"] == nil)
    }

    @Test func aModeThisVersionDoesntKnowReadsAsTheDefault() {
        let preferences = LanguagePreferences(configuration: ["SubtitleMode": .string("Telepathic")])
        #expect(preferences.subtitleMode == .default)
    }

    @Test func languagesComeOnceEachWithTheirThreeLetterCodes() async throws {
        let host = "cultures.example.com"
        let cultures = #"""
            [{"DisplayName":"English","ThreeLetterISOLanguageName":"eng"},
             {"DisplayName":"French","ThreeLetterISOLanguageName":"fre"},
             {"DisplayName":"French (Canada)","ThreeLetterISOLanguageName":"fre"},
             {"DisplayName":"Invariant","ThreeLetterISOLanguageName":""}]
            """#
        StubURLProtocol.stub("\(host):443", path: "/Localization/Cultures", .json(200, cultures))
        let languages = try await library(on: host).languages()
        #expect(languages == [Language(code: "eng", name: "English"), Language(code: "fre", name: "French")])
    }

    @Test func aSettingsAnswerWithoutSettingsIsUnexpected() async throws {
        let host = "languages-odd.example.com"
        StubURLProtocol.stub("\(host):443", path: "/Users/Me", .json(200, #"{"Name":"Alice"}"#))
        await #expect(throws: SerafinError.unexpectedResponse(status: nil)) {
            try await library(on: host).languagePreferences()
        }
    }
}
