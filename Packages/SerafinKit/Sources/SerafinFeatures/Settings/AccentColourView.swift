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
            localized: "Accent Colour", bundle: .module,
            comment: "Title of the accent colour screen, and its row in Settings.")
    }

    var body: some View {
        Form {
            Section {
                AccentPicker(selection: $accent)
            } footer: {
                Text(
                    String(
                        localized:
                            "Buttons, links, selections and the tab bar take this colour. Colours taken from artwork stay as they are.",
                        bundle: .module,
                        comment: "Settings footer under the accent colour choices."
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

/// A play button, a favourite button, a progress bar and a selection, drawn in the accent colour. They don't respond
/// to touch: they're only there to show the colour.
private struct AccentSample: View {
    let accent: Accent

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            GlassEffectContainer {
                HStack(spacing: Spacing.small) {
                    Button {
                    } label: {
                        // Not a Label: a list row tints a label's icon with the accent, which would hide it here.
                        HStack(spacing: Spacing.xxSmall) {
                            Image(systemName: "play.fill")
                            Text(
                                String(
                                    localized: "Play", bundle: .module,
                                    comment:
                                        "Starts playback: a menu item, and a sample button in the accent colour preview."
                                )
                            )
                        }
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                    } label: {
                        Image(systemName: "heart.fill")
                    }
                    .buttonStyle(.glass)
                }
            }
            ProgressView(value: 0.4)
            Label {
                Text(accent.name)
                    .foregroundStyle(.textPrimary)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
            }
        }
        .padding(.vertical, Spacing.xSmall)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(
                localized: "Buttons, progress and selections in \(accent.name)", bundle: .module,
                comment: "Spoken for the accent colour preview, such as Buttons, progress and selections in Red.")
        )
    }
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
