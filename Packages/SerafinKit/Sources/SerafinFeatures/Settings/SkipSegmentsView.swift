import SerafinCore
import SwiftUI

/// Which stretches the server marks skip by themselves, rather than offering a pill: intros, recaps, previews and
/// adverts, each off until turned on. Saved on this device.
struct SkipSegmentsView: View {
    var body: some View {
        Form {
            Section {
                ForEach(AutomaticSkips.kinds, id: \.self) { kind in
                    if let key = AutomaticSkips.key(for: kind) {
                        AutomaticSkipToggle(title: Self.title(for: kind), key: key)
                    }
                }
            } header: {
                Text(
                    String(
                        localized: "Skip Automatically", bundle: .module,
                        comment: "Settings section header: stretches the player skips without asking."))
            } footer: {
                Text(
                    String(
                        localized: """
                            Serafin skips these when the server marks them, and says so briefly. Otherwise it offers to \
                            skip them. Credits offer the next episode, which plays by itself when your account plays \
                            the next episode automatically.
                            """,
                        bundle: .module,
                        comment: "Settings footer under the stretches the player skips without asking."))
            }
        }
        .readableWidth()
        .navigationTitle(Self.title)
    }

    /// The screen's title, which is also its row in Settings.
    nonisolated static var title: String {
        String(
            localized: "Skip Segments", bundle: .module,
            comment: "Title of the settings for skipping marked stretches, such as intros, and its row in Settings.")
    }

    /// The switch's name for `kind`, such as "Intros".
    nonisolated static func title(for kind: PlaybackSegment.Kind) -> String {
        switch kind {
        case .intro:
            String(localized: "Intros", bundle: .module, comment: "Settings switch: skip intros by themselves.")
        case .recap:
            String(localized: "Recaps", bundle: .module, comment: "Settings switch: skip recaps by themselves.")
        case .preview:
            String(localized: "Previews", bundle: .module, comment: "Settings switch: skip previews by themselves.")
        case .advert: String(localized: "Ads", bundle: .module, comment: "Settings switch: skip adverts by themselves.")
        case .credits:
            String(localized: "Credits", bundle: .module, comment: "Settings switch: skip credits by themselves.")
        case .unknown:
            String(
                localized: "Other Segments", bundle: .module,
                comment: "Settings switch: skip stretches the server marked without naming them.")
        }
    }
}

/// One kind's switch, saved under `key`.
private struct AutomaticSkipToggle: View {
    let title: String
    @AppStorage private var isOn: Bool

    init(title: String, key: String) {
        self.title = title
        _isOn = AppStorage(wrappedValue: false, key)
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
    }
}

#Preview {
    NavigationStack {
        SkipSegmentsView()
    }
}
