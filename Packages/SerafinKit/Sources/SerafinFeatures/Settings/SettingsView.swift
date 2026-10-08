import Foundation
import SerafinCore
import SerafinDesign
import SwiftUI

/// The Settings tab: servers and accounts, playback, the lock, the cache, and the app's details.
struct SettingsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Form {
            AccountsSection()
            AppearanceSection()
            PlaybackSection(server: session.account?.server, isOneOfSeveral: session.servers.count > 1)
                // Each server keeps its own caps, so another server's section starts afresh.
                .id(session.account?.server.id)
            DeliverySection()
            LockSection()
            StorageSection()
            Section(String(localized: "About", bundle: .module, comment: "Settings section header.")) {
                NavigationLink(value: Route.licences) {
                    Text(
                        String(
                            localized: "Licenses", bundle: .module,
                            comment: "Title of the licenses screen, and its row in Settings."))
                }
                LabeledContent(
                    String(
                        localized: "Version", bundle: .module,
                        comment:
                            "Settings row showing a version: the app's in Settings, or a package's on the licences screen."
                    ),
                    value: Self.version
                )
            }
            #if DEBUG
                DesignSection()
            #endif
        }
        .readableWidth()
        .navigationTitle(String(localized: "Settings", bundle: .module, comment: "Title of the settings screen."))
        .task {
            await session.refreshServerNames()
        }
    }

    /// The app version and build, such as "0.1.0 (1)".
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(short) (\(build))"
    }
}

/// The accent colour, for buttons, links, selections and the tab bar, as a row that opens its own screen.
private struct AppearanceSection: View {
    @AppStorage(Accent.storageKey) private var accent = Accent.standard

    var body: some View {
        Section {
            NavigationLink(value: Route.accentColour) {
                LabeledContent(AccentColourView.title, value: accent.name)
            }
        } header: {
            Text(String(localized: "Appearance", bundle: .module, comment: "Settings section header."))
        }
    }
}

/// Audio and subtitles, which marked stretches skip by themselves, the current server's streaming caps on Wi-Fi and
/// cellular, and whether putting the player away carries a playing video on in Picture in Picture.
private struct PlaybackSection: View {
    let server: Server?
    let isOneOfSeveral: Bool
    @AppStorage private var wifiQuality: PlaybackQuality
    @AppStorage private var cellularQuality: PlaybackQuality
    @AppStorage private var minimizesToPictureInPicture: Bool

    /// Creates the section for `server`'s caps, or for the caps every server shares when there's no server, as in
    /// previews.
    init(server: Server?, isOneOfSeveral: Bool, defaults: UserDefaults = .standard) {
        self.server = server
        self.isOneOfSeveral = isOneOfSeveral
        func storage(onCellular: Bool) -> AppStorage<PlaybackQuality> {
            let saved = PlaybackQuality.saved(onCellular: onCellular, server: server?.id, in: defaults)
            let key =
                server.map { PlaybackQuality.key(onCellular: onCellular, server: $0.id) }
                ?? (onCellular ? PlaybackQuality.cellularKey : PlaybackQuality.wifiKey)
            return AppStorage(wrappedValue: saved, key, store: defaults)
        }
        _wifiQuality = storage(onCellular: false)
        _cellularQuality = storage(onCellular: true)
        _minimizesToPictureInPicture = AppStorage(
            wrappedValue: PlaybackCoordinator.minimizesToPictureInPicture(in: defaults),
            PlaybackCoordinator.minimizesToPictureInPictureKey, store: defaults)
    }

    var body: some View {
        Section {
            NavigationLink(value: Route.audioAndSubtitles) {
                Text(AudioAndSubtitlesView.title)
            }
            NavigationLink(value: Route.skipSegments) {
                Text(SkipSegmentsView.title)
            }
            Picker(
                String(localized: "Quality on Wi-Fi", bundle: .module, comment: "Settings row."),
                selection: $wifiQuality
            ) {
                ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
            }
            .rebuiltForAccent()
            Picker(
                String(localized: "Quality on Cellular", bundle: .module, comment: "Settings row."),
                selection: $cellularQuality
            ) {
                ForEach(PlaybackQuality.allCases) { Text($0.title).tag($0) }
            }
            .rebuiltForAccent()
            Toggle(
                String(
                    localized: "Minimize to Picture in Picture", bundle: .module,
                    comment:
                        "Settings switch: putting the player away while a video plays carries it on in Picture in Picture."
                ),
                isOn: $minimizesToPictureInPicture
            )
        } header: {
            Text(String(localized: "Playback", bundle: .module, comment: "Settings section header."))
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let caps = String(
            localized: "Lower caps use less data. The server converts anything above the cap.",
            bundle: .module,
            comment: "Settings footer under the streaming quality caps."
        )
        guard isOneOfSeveral, let server else { return caps }
        return String(
            localized: "\(caps) These caps are for \(server.displayName); each server keeps its own.",
            bundle: .module,
            comment: "Settings footer under the streaming quality caps with more than one server: the caps, then whose."
        )
    }
}

/// The optional lock: Face ID, Touch ID or the passcode when Serafin opens, and how long it may sit in the background
/// before it asks again. Changing either needs the owner to confirm.
private struct LockSection: View {
    @Environment(AppLock.self) private var lock: AppLock?

    var body: some View {
        if let lock {
            let check = lock.check
            Section {
                Toggle(
                    check.settingTitle,
                    isOn: Binding(get: { lock.isEnabled }, set: { on in Task { await lock.setEnabled(on) } })
                )
                .disabled(check == .unavailable || lock.isConfirming)
                if lock.isEnabled {
                    Picker(
                        String(
                            localized: "Lock Again", bundle: .module, comment: "Settings row: the lock's grace period."),
                        selection: Binding(get: { lock.grace }, set: { lock.setGrace($0) })
                    ) {
                        ForEach(LockGrace.allCases) { Text($0.title).tag($0) }
                    }
                    .rebuiltForAccent()
                }
            } header: {
                Text(String(localized: "Privacy", bundle: .module, comment: "Settings section header."))
            } footer: {
                Text(footer(lock: lock, check: check))
            }
        }
    }
}

extension LockSection {
    private func footer(lock: AppLock, check: OwnerCheck) -> String {
        if check == .unavailable {
            String(
                localized: "Set a passcode in the Settings app to lock Serafin.", bundle: .module,
                comment: "Settings footer when the device has no passcode.")
        } else if lock.isEnabled {
            String(
                localized:
                    "Serafin locks when it opens, and again once it has been in the background for this long. Spotlight and Siri don't show your library while the lock is on.",
                bundle: .module, comment: "Settings footer under the lock while it's on.")
        } else {
            String(
                localized:
                    "Keeps your library private when someone else picks up this device, and out of Spotlight and Siri.",
                bundle: .module, comment: "Settings footer under the lock while it's off.")
        }
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
                Text(server.displayName)
            } footer: {
                ServerAddressLine(url: server.url)
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
                String(
                    localized: "Remove \(server.displayName)", bundle: .module, comment: "Button that removes a server."
                ),
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

/// A server's address under its section: a lock for HTTPS, or "Local network" for plain HTTP, which Serafin allows
/// only on the user's own network and only after a warning, so it's plain why the server was accepted.
private struct ServerAddressLine: View {
    let url: URL

    var body: some View {
        switch try? TransportPolicy.security(of: url) {
        case .encrypted:
            Label {
                Text(address)
            } icon: {
                Image(systemName: "lock.fill")
                    .accessibilityLabel(
                        String(
                            localized: "Encrypted", bundle: .module,
                            comment: "Spoken for the lock beside an HTTPS server's address in Settings."))
            }
            .accessibilityElement(children: .combine)
        case .unencryptedOnPrivateNetwork:
            VStack(alignment: .leading, spacing: 2) {
                Text(address)
                Text(
                    String(
                        localized: "Local network", bundle: .module,
                        comment:
                            "Under a plain HTTP server's address in Settings: it's allowed because it's on the user's own network."
                    )
                )
                .font(.caption)
            }
            .accessibilityElement(children: .combine)
        case nil:
            Text(address)
        }
    }

    /// The address without its scheme, which the lock or the caption already gives, such as "media.example.com" or
    /// "192.168.1.20:8096".
    private var address: String {
        var text = url.absoluteString
        if let scheme = url.scheme, text.hasPrefix("\(scheme)://") {
            text.removeFirst(scheme.count + 3)
        }
        if text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }
}

/// The three ways a video can reach the player, in the words the player's audio and subtitle sheet uses.
private struct DeliverySection: View {
    var body: some View {
        Section {
            ForEach(PlaybackDelivery.allCases, id: \.self) { delivery in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(delivery.title)
                        Text(delivery.explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: delivery.systemImage)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(String(localized: "How Videos Play", bundle: .module, comment: "Settings section header."))
        } footer: {
            Text(
                String(
                    localized: "The player's Audio and Subtitles sheet shows which one is happening.",
                    bundle: .module,
                    comment: "Settings footer under the ways a video can play."
                )
            )
        }
    }
}

/// Clearing the cached artwork, saved Home and library answers.
private struct StorageSection: View {
    @Environment(AppSession.self) private var session
    @State private var clearCount = 0

    var body: some View {
        Section {
            Button {
                Task {
                    await session.clearCaches()
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
                    localized:
                        "Removes saved artwork, and the copy of Home that shows when your server can't be reached. Both download again as you browse.",
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

#if DEBUG
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
#endif
