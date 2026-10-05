import JellyfinAPI
import SerafinCore
import SerafinPlayback
import SwiftUI

/// The audio and subtitle languages the account prefers, saved on the server, and how subtitles look on this device.
struct AudioAndSubtitlesView: View {
    @Environment(AppSession.self) private var session
    @Environment(PlaybackCoordinator.self) private var playback: PlaybackCoordinator?
    @State private var model: LanguagesModel?

    var body: some View {
        Form {
            if let model {
                LanguagesSection(model: model)
            }
            if let playback {
                SubtitleStyleSection(playback: playback)
            }
        }
        .readableWidth()
        .navigationTitle(Self.title)
        .task {
            guard model == nil else { return }
            let model = LanguagesModel(store: session.library ?? SampleLanguageStore())
            self.model = model
            await model.load()
        }
    }

    /// The screen's title, which is also its row in Settings.
    static var title: String {
        String(
            localized: "Audio and Subtitles", bundle: .module,
            comment: "Title of the audio and subtitles settings, and its row in Settings.")
    }
}

/// The languages the account prefers, and when subtitles show unasked.
private struct LanguagesSection: View {
    let model: LanguagesModel

    var body: some View {
        Section {
            switch model.phase {
            case .loading:
                LabeledContent(
                    String(
                        localized: "Languages", bundle: .module,
                        comment:
                            "Languages: a detail screen's column heading, and the Settings section for preferred languages."
                    )
                ) {
                    ProgressView()
                }
            case .failed:
                Button(String(localized: "Try Again", bundle: .module, comment: "Button that retries a request.")) {
                    Task { await model.load() }
                }
            case .loaded:
                pickers
            }
        } header: {
            Text(
                String(
                    localized: "Languages", bundle: .module,
                    comment:
                        "Languages: a detail screen's column heading, and the Settings section for preferred languages."
                ))
        } footer: {
            footer
        }
    }

    @ViewBuilder private var pickers: some View {
        Picker(
            String(
                localized: "Audio Language", bundle: .module, comment: "Settings row: the preferred audio language."),
            selection: Binding(get: { model.preferences.audio }, set: { model.setAudio($0) })
        ) {
            Text(String(localized: "Video's Default", bundle: .module, comment: "Audio language: each video's own."))
                .tag(String?.none)
            languageOptions
        }
        .listedOnItsOwnScreen()
        Picker(
            String(
                localized: "Subtitles", bundle: .module,
                comment:
                    "Subtitles: a detail fact listing subtitle languages, and the Settings row for when subtitles show."
            ),
            selection: Binding(get: { model.preferences.subtitleMode }, set: { model.setSubtitleMode($0) })
        ) {
            ForEach(SubtitlePlaybackMode.settingsOrder, id: \.self) { mode in
                Text(mode.title).tag(mode)
            }
        }
        if model.preferences.subtitleMode != .none {
            Picker(
                String(
                    localized: "Subtitle Language", bundle: .module,
                    comment: "Settings row: the preferred subtitle language."),
                selection: Binding(get: { model.preferences.subtitles }, set: { model.setSubtitles($0) })
            ) {
                Text(
                    String(
                        localized: "Any Language", bundle: .module, comment: "Subtitle language: none in particular.")
                )
                .tag(String?.none)
                languageOptions
            }
            .listedOnItsOwnScreen()
        }
    }

    private var languageOptions: some View {
        ForEach(model.languages) { language in
            Text(language.name).tag(Optional(language.code))
        }
    }

    @ViewBuilder private var footer: some View {
        switch model.phase {
        case .loading:
            EmptyView()
        case .failed(let message):
            FailureMessage(message: message)
        case .loaded:
            VStack(alignment: .leading, spacing: 0) {
                Text(
                    String(
                        localized:
                            "\(model.preferences.subtitleMode.explanation) Saved to your Jellyfin account, so your other Jellyfin apps follow them too.",
                        bundle: .module,
                        comment:
                            "Footer under the language settings: what the subtitle mode does, then where they're saved."
                    )
                )
                if let failure = model.failure {
                    FailureMessage(message: failure)
                }
            }
        }
    }
}

/// How big subtitles shown as text are on this device. The rest of their look is the system's caption style.
private struct SubtitleStyleSection: View {
    @Bindable var playback: PlaybackCoordinator

    var body: some View {
        Section {
            Picker(
                String(localized: "Subtitle Size", bundle: .module, comment: "Settings row: subtitle size."),
                selection: $playback.subtitleStyle.size
            ) {
                ForEach(SubtitleStyle.Size.allCases) { Text($0.title).tag($0) }
            }
        } header: {
            Text(String(localized: "Subtitle Style", bundle: .module, comment: "Settings section header."))
        } footer: {
            Text(
                String(
                    localized:
                        "For subtitles shown as text, on this device. Their font and background follow your caption style, in Settings > Accessibility > Subtitles & Captioning.",
                    bundle: .module,
                    comment: "Footer under the subtitle size setting. Use the names the Settings app uses."
                )
            )
        }
    }
}

extension View {
    /// Lists a long picker's choices on a screen of their own, where the platform has one.
    fileprivate func listedOnItsOwnScreen() -> some View {
        #if os(iOS)
            pickerStyle(.navigationLink)
        #else
            self
        #endif
    }
}

/// A few languages and no saved preferences, for previews.
private struct SampleLanguageStore: LanguagePreferenceStore {
    func languages() async throws -> [Language] {
        [
            Language(code: "eng", name: "English"), Language(code: "fre", name: "French"),
            Language(code: "ger", name: "German"), Language(code: "jpn", name: "Japanese"),
            Language(code: "spa", name: "Spanish"),
        ]
    }

    func languagePreferences() async throws -> LanguagePreferences {
        LanguagePreferences(subtitleMode: .smart)
    }

    func setLanguagePreferences(_ preferences: LanguagePreferences) async throws {}
}

#if DEBUG
    #Preview("Light") {
        TabStack { AudioAndSubtitlesView() }
            .environment(AppSession.preview())
            .previewEnvironment()
    }

    #Preview("Dark") {
        TabStack { AudioAndSubtitlesView() }
            .environment(AppSession.preview())
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TabStack { AudioAndSubtitlesView() }
            .environment(AppSession.preview())
            .previewEnvironment()
            .dynamicTypeSize(.accessibility5)
    }
#endif
