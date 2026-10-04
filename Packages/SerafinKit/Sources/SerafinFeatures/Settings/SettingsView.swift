import Foundation
import SerafinDesign
import SwiftUI

/// The Settings tab. A static list in the app shell; each setting comes alive with its plan task.
struct SettingsView: View {
    var body: some View {
        Form {
            Section {
                Label(
                    String(localized: "Sample Media", bundle: .module, comment: "Settings row: the app shows samples."),
                    systemImage: "sparkles.tv"
                )
            } header: {
                Text(String(localized: "Server", bundle: .module, comment: "Settings section header."))
            } footer: {
                Text(
                    String(
                        localized: "Serafin is showing built-in sample titles until you connect a Jellyfin server.",
                        bundle: .module,
                        comment: "Settings footer under the server section."
                    )
                )
            }

            Section(String(localized: "Playback", bundle: .module, comment: "Settings section header.")) {
                LabeledContent(
                    String(localized: "Quality on Wi-Fi", bundle: .module, comment: "Settings row."),
                    value: String(localized: "Maximum", bundle: .module, comment: "Streaming quality: no cap.")
                )
                LabeledContent(
                    String(localized: "Quality on Cellular", bundle: .module, comment: "Settings row."),
                    value: String(localized: "8 Mbps", bundle: .module, comment: "Streaming quality cap.")
                )
            }

            Section(String(localized: "About", bundle: .module, comment: "Settings section header.")) {
                LabeledContent(
                    String(localized: "Version", bundle: .module, comment: "Settings row showing the app version."),
                    value: Self.version
                )
            }

            #if DEBUG
                Section {
                    NavigationLink {
                        ComponentGallery()
                    } label: {
                        Text(verbatim: "Component Gallery")
                    }
                    NavigationLink {
                        TokensPreview()
                    } label: {
                        Text(verbatim: "Design Tokens")
                    }
                    NavigationLink {
                        MockMediaPreview()
                    } label: {
                        Text(verbatim: "Sample Media")
                    }
                } header: {
                    Text(verbatim: "Design (debug builds only)")
                }
            #endif
        }
        .navigationTitle(String(localized: "Settings", bundle: .module, comment: "Title of the settings tab."))
    }

    /// The app version and build, such as "0.1.0 (1)".
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

#Preview("Light") {
    TabStack { SettingsView() }
}

#Preview("Dark") {
    TabStack { SettingsView() }
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TabStack { SettingsView() }
        .dynamicTypeSize(.accessibility5)
}
