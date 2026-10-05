import Foundation
import JellyfinAPI
import SerafinCore
import SerafinPlayback
import Testing

@testable import SerafinFeatures

@Suite struct ServerQualityTests {
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "app.getserafin.serafin.tests.\(UUID().uuidString)"))
    }

    @Test func eachServerKeepsItsOwnCaps() {
        defaults.set(PlaybackQuality.mbps4.rawValue, forKey: PlaybackQuality.key(onCellular: true, server: "far"))
        #expect(PlaybackQuality.saved(onCellular: true, server: "far", in: defaults) == .mbps4)
        #expect(PlaybackQuality.saved(onCellular: true, server: "near", in: defaults) == .mbps8)
        #expect(PlaybackQuality.saved(onCellular: false, server: "far", in: defaults) == .maximum)
    }

    @Test func aCapPickedBeforeEachServerHadItsOwnStillStands() {
        defaults.set(PlaybackQuality.mbps2.rawValue, forKey: PlaybackQuality.cellularKey)
        #expect(PlaybackQuality.saved(onCellular: true, server: "near", in: defaults) == .mbps2)
        defaults.set(PlaybackQuality.mbps12.rawValue, forKey: PlaybackQuality.key(onCellular: true, server: "near"))
        #expect(PlaybackQuality.saved(onCellular: true, server: "near", in: defaults) == .mbps12)
    }

    @Test func aRemovedServersCapsAreForgotten() {
        for onCellular in [false, true] {
            defaults.set(
                PlaybackQuality.mbps4.rawValue, forKey: PlaybackQuality.key(onCellular: onCellular, server: "gone"))
        }
        PlaybackQuality.forget(server: "gone", in: defaults)
        #expect(PlaybackQuality.saved(onCellular: false, server: "gone", in: defaults) == .maximum)
        #expect(PlaybackQuality.saved(onCellular: true, server: "gone", in: defaults) == .mbps8)
    }

    @MainActor
    @Test func playbackStreamsUnderItsServersCap() {
        defaults.set(PlaybackQuality.mbps20.rawValue, forKey: PlaybackQuality.key(onCellular: false, server: "home"))
        let atHome = PlaybackCoordinator(serverID: "home", defaults: defaults, isOnExpensiveNetwork: { false })
        let elsewhere = PlaybackCoordinator(serverID: "away", defaults: defaults, isOnExpensiveNetwork: { false })
        #expect(atHome.maxBitrate == 20_000_000)
        #expect(elsewhere.maxBitrate == nil)
    }

    @MainActor
    @Test func theSubtitleSizeLasts() {
        let playback = PlaybackCoordinator(defaults: defaults, isOnExpensiveNetwork: { false })
        #expect(playback.subtitleStyle == .standard)
        playback.subtitleStyle.size = .extraLarge
        #expect(
            PlaybackCoordinator(defaults: defaults, isOnExpensiveNetwork: { false }).subtitleStyle.size == .extraLarge)
    }
}

/// The account's preferences on a pretend server, which can refuse to save.
private actor FakeLanguageStore: LanguagePreferenceStore {
    var saved = LanguagePreferences(subtitles: "fre", subtitleMode: .smart)
    var refusesToSave = false
    private(set) var saves: [LanguagePreferences] = []

    func languages() async throws -> [Language] {
        [Language(code: "ger", name: "German"), Language(code: "eng", name: "English")]
    }

    func languagePreferences() async throws -> LanguagePreferences { saved }

    func setLanguagePreferences(_ preferences: LanguagePreferences) async throws {
        saves.append(preferences)
        if refusesToSave { throw SerafinError.serverUnreachable }
        saved = preferences
    }

    func refuse() { refusesToSave = true }
}

@MainActor
@Suite struct LanguagesModelTests {
    @Test func loadingShowsTheServersPreferencesAndItsLanguagesByName() async {
        let model = LanguagesModel(store: FakeLanguageStore(), locale: Locale(identifier: "en_GB"))
        await model.load()
        #expect(model.phase == .loaded)
        #expect(model.preferences.subtitles == "fre")
        // French was saved by another app and isn't in the server's list, but still shows as the one chosen.
        #expect(model.languages.map(\.code) == ["eng", "fre", "ger"])
        #expect(model.languages.map(\.name) == ["English", "French", "German"])
    }

    @Test func aChangeShowsAtOnceAndIsSaved() async {
        let store = FakeLanguageStore()
        let model = LanguagesModel(store: store)
        await model.load()
        model.setAudio("jpn")
        #expect(model.preferences.audio == "jpn")
        await model.finishSaving()
        #expect(await store.saved.audio == "jpn")
        #expect(await store.saved.subtitles == "fre")
    }

    @Test func quickChangesReachTheServerInOrder() async {
        let store = FakeLanguageStore()
        let model = LanguagesModel(store: store)
        await model.load()
        model.setSubtitleMode(.always)
        model.setSubtitles("eng")
        model.setSubtitles(nil)
        await model.finishSaving()
        #expect(await store.saved == LanguagePreferences(audio: nil, subtitles: nil, subtitleMode: .always))
    }

    @Test func choosingWhatIsAlreadyChosenSavesNothing() async {
        let store = FakeLanguageStore()
        let model = LanguagesModel(store: store)
        await model.load()
        model.setSubtitles("fre")
        await model.finishSaving()
        #expect(await store.saves.isEmpty)
    }

    @Test func whenASaveFailsTheServersPreferencesComeBack() async {
        let store = FakeLanguageStore()
        await store.refuse()
        let model = LanguagesModel(store: store)
        await model.load()
        model.setAudio("jpn")
        await model.finishSaving()
        #expect(model.preferences.audio == nil)
        #expect(model.failure?.title == "Can't Reach the Server")
    }

    @Test func modesReadAsSettingsListsThem() {
        #expect(
            SubtitlePlaybackMode.settingsOrder.map(\.title) == [
                "Automatic", "For Other Languages", "Always", "Forced Only", "Off",
            ])
    }
}
