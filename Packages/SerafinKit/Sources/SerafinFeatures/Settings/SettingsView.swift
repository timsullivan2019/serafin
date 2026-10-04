import Foundation
import SerafinCore
import SerafinDesign
import SwiftUI

/// The Settings tab: servers and accounts, streaming quality, the cache, and the app's details.
struct SettingsView: View {
    @AppStorage(PlaybackQuality.wifiKey) private var wifiQuality = PlaybackQuality.wifiDefault
    @AppStorage(PlaybackQuality.cellularKey) private var cellularQuality = PlaybackQuality.cellularDefault

    var body: some View {
        Form {
            AccountsSection()
            Section {
                Picker(
                    String(localized: "Quality on Wi-Fi", bundle: .module, comment: "Settings row."),
                    selection: $wifiQuality
                ) {
                    ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
                }
                Picker(
                    String(localized: "Quality on Cellular", bundle: .module, comment: "Settings row."),
                    selection: $cellularQuality
                ) {
                    ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text(String(localized: "Playback", bundle: .module, comment: "Settings section header."))
            } footer: {
                Text(
                    String(
                        localized: "Lower caps use less data. The server converts anything above the cap.",
                        bundle: .module,
                        comment: "Settings footer under the streaming quality caps."
                    )
                )
            }
            StorageSection()
            Section(String(localized: "About", bundle: .module, comment: "Settings section header.")) {
                NavigationLink(value: Route.licences) {
                    Text(
                        String(
                            localized: "Licences", bundle: .module,
                            comment: "Title of the licences screen, and its row in Settings."))
                }
                LabeledContent(
                    String(localized: "Version", bundle: .module, comment: "Settings row showing the app version."),
                    value: Self.version
                )
            }
            #if DEBUG
                DesignSection()
            #endif
        }
        .readableWidth()
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

/// Every server with its signed-in accounts: switch between them, add one, sign out, or remove a server.
private struct AccountsSection: View {
    @Environment(AppSession.self) private var session
    @State private var serverToRemove: Server?
    @State private var failure: UserMessage?

    var body: some View {
        ForEach(session.servers) { server in
            Section {
                ForEach(server.users) { user in
                    accountRow(user, on: server)
                }
                NavigationLink(value: Route.signIn(server)) {
                    Label(
                        String(
                            localized: "Add Account", bundle: .module, comment: "Settings row: sign in another user."),
                        systemImage: "person.crop.circle.badge.plus"
                    )
                }
                Button(role: .destructive) {
                    serverToRemove = server
                } label: {
                    Label(
                        String(localized: "Remove Server", bundle: .module, comment: "Settings row."),
                        systemImage: "trash"
                    )
                }
                .tint(.red)
            } header: {
                Text(server.name)
            } footer: {
                Text(server.url.absoluteString)
            }
        }
        Section {
            NavigationLink(value: Route.addServer) {
                Label(
                    String(
                        localized: "Add Server", bundle: .module,
                        comment: "Title of the add server screen, and its row in Settings."),
                    systemImage: "plus"
                )
            }
        } footer: {
            if let failure {
                FailureMessage(message: failure)
            }
        }
        .confirmationDialog(
            String(localized: "Remove this server?", bundle: .module, comment: "Title of the remove server dialog."),
            isPresented: Binding(get: { serverToRemove != nil }, set: { if !$0 { serverToRemove = nil } }),
            titleVisibility: .visible,
            presenting: serverToRemove
        ) { server in
            Button(
                String(localized: "Remove \(server.name)", bundle: .module, comment: "Button that removes a server."),
                role: .destructive
            ) {
                Task { await run { try await session.remove(server) } }
            }
        } message: { _ in
            Text(
                String(
                    localized: "Everyone signed in to it on this device is signed out.",
                    bundle: .module,
                    comment: "Message in the remove server dialog."
                )
            )
        }
    }

    private func accountRow(_ user: ServerUser, on server: Server) -> some View {
        let key = SessionKey(serverID: server.id, userID: user.id)
        let isCurrent = session.account?.key == key
        return Button {
            Task { await run { try await session.switchTo(key) } }
        } label: {
            HStack {
                Label(user.name, systemImage: "person.crop.circle")
                    .foregroundStyle(.textPrimary)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(isCurrent)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .swipeActions {
            Button(role: .destructive) {
                Task { await run { try await session.signOut(key) } }
            } label: {
                Label(
                    String(
                        localized: "Sign Out", bundle: .module, comment: "Button that signs a user out on this device."),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
            .tint(.red)
        }
        .contextMenu {
            Button(role: .destructive) {
                Task { await run { try await session.signOut(key) } }
            } label: {
                Label(
                    String(
                        localized: "Sign Out", bundle: .module, comment: "Button that signs a user out on this device."),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }
        }
    }

    private func run(_ change: () async throws -> Void) async {
        do {
            failure = nil
            try await change()
        } catch {
            failure = UserMessage(error)
        }
    }
}

/// Clearing the cached artwork and library answers.
private struct StorageSection: View {
    @Environment(\.artwork) private var artwork
    @Environment(\.media) private var media
    @State private var clearCount = 0

    var body: some View {
        Section {
            Button {
                artwork?.removeAllCachedImages()
                Task {
                    await media.refresh()
                    clearCount += 1
                }
            } label: {
                LabeledContent {
                    if clearCount > 0 {
                        Text(String(localized: "Cleared", bundle: .module, comment: "Shown after clearing the cache."))
                    }
                } label: {
                    Text(String(localized: "Clear Cache", bundle: .module, comment: "Settings button."))
                }
            }
            .sensoryFeedback(.success, trigger: clearCount)
        } header: {
            Text(String(localized: "Storage", bundle: .module, comment: "Settings section header."))
        } footer: {
            Text(
                String(
                    localized: "Removes saved artwork. It downloads again as you browse.",
                    bundle: .module,
                    comment: "Settings footer under Clear Cache."
                )
            )
        }
    }
}

#if DEBUG
    /// Links to the design module's galleries, in debug builds only.
    private struct DesignSection: View {
        var body: some View {
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
        }
    }
#endif

#Preview("Light") {
    TabStack { SettingsView() }
        .environment(AppSession.preview())
}

#Preview("Dark") {
    TabStack { SettingsView() }
        .environment(AppSession.preview())
        .preferredColorScheme(.dark)
}

#Preview("Largest text") {
    TabStack { SettingsView() }
        .environment(AppSession.preview())
        .dynamicTypeSize(.accessibility5)
}
