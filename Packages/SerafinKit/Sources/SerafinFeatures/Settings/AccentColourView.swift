import SerafinDesign
import SwiftUI

/// The accent colour, from Settings: every colour as a swatch, and a preview of the controls that take it.
///
/// A new colour applies at once, here and behind the sheet, so the preview and the app change together.
struct AccentColourView: View {
    @AppStorage(Accent.storageKey) private var accent = Accent.standard

    /// The screen's title, which is also its row in Settings.
    static var title: String {
        String(
            localized: "Accent Color", bundle: .module,
            comment: "Title of the accent color screen, and its row in Settings.")
    }

    var body: some View {
        Form {
            Section {
                AccentPicker(selection: $accent)
            } footer: {
                Text(
                    String(
                        localized:
                            "Buttons, links, selections and the tab bar take this color. Colors taken from artwork stay as they are.",
                        bundle: .module,
                        comment: "Settings footer under the accent color choices."
                    )
                )
            }
            Section {
                AccentSample(accent: accent)
            } header: {
                Text(
                    String(
                        localized: "Preview", bundle: .module,
                        comment: "Header over sample controls in the chosen accent colour.")
                )
            }
        }
        .readableWidth()
        .navigationTitle(Self.title)
    }
}

/// The accent on what takes it: a detail screen's play pill with the tab bar over it, then a Settings value as its
/// row shows it. None of it responds to touch.
private struct AccentSample: View {
    let accent: Accent

    var body: some View {
        AccentPreview(
            card: Self.card,
            artwork: MockMedia.backdropImage(for: Self.card),
            tabs: [
                AccentPreview.TabItem(
                    title: String(localized: "Home", bundle: .module, comment: "Title of the home tab."),
                    systemImage: "house"),
                AccentPreview.TabItem(
                    title: String(localized: "Library", bundle: .module, comment: "Title of the library tab."),
                    systemImage: "square.grid.2x2"),
            ],
            searchTitle: String(localized: "Search", bundle: .module, comment: "Title of the search tab.")
        )
        .environment(\.accent, accent.color)
        .listRowInsets(EdgeInsets())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                localized: "The play button, the selected tab and a Settings value in \(accent.name)", bundle: .module,
                comment:
                    "Spoken for the accent colour preview, such as The play button, the selected tab and a Settings value in Red."
            )
        )
        LabeledContent {
            HStack(spacing: Spacing.xxSmall) {
                Text(PlaybackQuality.maximum.title)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
            }
            .foregroundStyle(accent.color)
        } label: {
            Text(String(localized: "Quality on Wi-Fi", bundle: .module, comment: "Settings row."))
        }
        // The card above already says what the preview shows.
        .accessibilityHidden(true)
    }

    /// A film part watched, so the pill reads "Resume" with its progress line.
    private static let card = MockMedia.movies.first(where: \.isInProgress) ?? MockMedia.movies[0]
}

#if DEBUG
    #Preview("Light") {
        TabStack { AccentColourView() }
    }

    #Preview("Dark") {
        TabStack { AccentColourView() }
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TabStack { AccentColourView() }
            .dynamicTypeSize(.accessibility5)
    }
#endif
