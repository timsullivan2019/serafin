import NukeUI
import SerafinCore
import SerafinDesign
import SwiftUI

/// Opens Settings as a sheet, from the profile button in a root screen's toolbar.
struct ShowSettingsAction: Sendable {
    private let open: @MainActor @Sendable () -> Void

    init(_ open: @escaping @MainActor @Sendable () -> Void) {
        self.open = open
    }

    /// Opens Settings.
    @MainActor func callAsFunction() {
        open()
    }
}

extension EnvironmentValues {
    /// Opens Settings as a sheet. Does nothing outside the tabs, as in previews.
    @Entry var showSettings = ShowSettingsAction {}
}

extension View {
    /// Puts the profile button, which opens Settings, in the top-trailing corner of a root screen's toolbar.
    func profileToolbar() -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                ProfileButton()
            }
            // The picture is its own round control, so it goes without the toolbar's shared glass.
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

/// The signed-in user's picture, or their initial, which opens Settings.
struct ProfileButton: View {
    @Environment(AppSession.self) private var session: AppSession?
    @Environment(\.artwork) private var artwork
    @Environment(\.displayScale) private var scale
    @Environment(\.showSettings) private var showSettings
    @State private var imageTag: String?

    /// The avatar's diameter.
    static let size: CGFloat = 28

    var body: some View {
        Button {
            showSettings()
        } label: {
            avatar
                // At least 44 points to touch, though the picture is smaller.
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Settings", bundle: .module, comment: "Title of the settings screen."))
        .accessibilityHint(
            String(
                localized: "Accounts, playback, appearance and privacy", bundle: .module,
                comment: "Hint on the profile button, which opens Settings.")
        )
        .task(id: session?.account?.key) {
            imageTag = try? await session?.library?.profileImageTag()
        }
    }

    @ViewBuilder private var avatar: some View {
        let name = session?.account?.user.name ?? ""
        if let artwork, let user = session?.account?.user,
            let request = artwork.request(userImage: user.id, tag: imageTag, width: Self.size, scale: scale)
        {
            LazyImage(request: request) { state in
                ProfileAvatar(name: name, image: state.image, size: Self.size)
            }
            .pipeline(artwork.pipeline)
        } else {
            ProfileAvatar(name: name.isEmpty ? "S" : name, image: nil, size: Self.size)
        }
    }
}
