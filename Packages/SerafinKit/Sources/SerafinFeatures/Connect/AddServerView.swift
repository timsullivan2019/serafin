import SerafinCore
import SerafinDesign
import SwiftUI

/// Where a Jellyfin server is added: type its address or pick one found on the network. On first launch it
/// welcomes the user, and servers already saved are listed, so signing back in is one tap.
struct AddServerView: View {
    /// Whether this is the first screen of the app, which greets the user instead of showing a title.
    var isWelcome = false
    /// Called with a saved server once it is ready for sign-in.
    let onServer: (Server) -> Void
    @State private var model = AddServerModel()
    @Environment(AppSession.self) private var session
    @FocusState private var addressFocused: Bool

    var body: some View {
        Form {
            Section {
                ServerAddressField(address: $model.address, isFocused: $addressFocused, submit: connect)
            } header: {
                if isWelcome {
                    WelcomeHeader()
                }
            } footer: {
                if let failure = model.failure {
                    FailureMessage(message: failure)
                }
            }
            Section {
                ProminentFormButton(
                    title: String(localized: "Connect", bundle: .module, comment: "Button that connects to a server."),
                    isWorking: model.isConnecting, action: connect
                )
                .disabled(!model.canConnect)
            }
            if !model.discovered.isEmpty {
                Section(String(localized: "On This Network", bundle: .module, comment: "Servers found nearby.")) {
                    ForEach(model.discovered) { server in
                        Button {
                            Task { if let saved = await model.connect(to: server, with: session) { onServer(saved) } }
                        } label: {
                            LabeledContent(server.displayName, value: server.url.host() ?? "")
                        }
                        .disabled(model.isConnecting)
                    }
                }
            }
            if isWelcome, !session.servers.isEmpty {
                SavedServersSection(onServer: onServer)
            }
        }
        .readableWidth()
        .navigationTitle(
            isWelcome
                ? ""
                : String(
                    localized: "Add Server", bundle: .module,
                    comment: "Title of the add server screen, and its row in Settings.")
        )
        .navigationBarTitleDisplayModeInline()
        .task { await model.discover() }
        .sheet(item: $model.unencrypted) { connected in
            UnencryptedConnectionSheet(server: connected.server) {
                Task { if let saved = await model.acceptUnencrypted(with: session) { onServer(saved) } }
            } cancel: {
                model.unencrypted = nil
            }
            .scrollIndicators(.never)
        }
        .sheet(item: $model.certificate) { check in
            CertificateSheet(fingerprint: check.fingerprint, host: check.address.url.host() ?? "") {
                Task { if let saved = await model.trustCertificate(with: session) { onServer(saved) } }
            } cancel: {
                model.certificate = nil
            }
            .scrollIndicators(.never)
        }
        .alert(
            model.offer.map { AddressKindText.offerTitle($0.connected.server.url) } ?? "",
            isPresented: Binding(get: { model.offer != nil }, set: { if !$0 { model.offer = nil } }),
            presenting: model.offer
        ) { offer in
            Button(AddAddressView.title) {
                Task { if let saved = await model.acceptOffer(offer, with: session) { onServer(saved) } }
            }
            Button(
                String(localized: "Not Now", bundle: .module, comment: "Button that turns down an offered address."),
                role: .cancel
            ) {
                onServer(model.declineOffer(offer))
            }
        } message: { offer in
            Text(AddressKindText.offerMessage(serverName: offer.server.displayName))
        }
        .sheet(item: $model.unencryptedOffer) { offer in
            UnencryptedConnectionSheet(server: offer.connected.server) {
                Task { if let saved = await model.acceptOffer(offer, with: session) { onServer(saved) } }
            } cancel: {
                onServer(model.declineOffer(offer))
            }
            .scrollIndicators(.never)
        }
    }

    private func connect() {
        guard model.canConnect else { return }
        addressFocused = false
        Task { if let saved = await model.connect(with: session) { onServer(saved) } }
    }
}

/// The greeting above the address field.
private struct WelcomeHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(String(localized: "Welcome to Serafin", bundle: .module, comment: "Greeting on the first screen."))
                .typography(.largeTitle)
                .foregroundStyle(.textPrimary)
            Text(
                String(
                    localized: "Connect to your Jellyfin server to start watching.",
                    bundle: .module,
                    comment: "Explanation on the first screen."
                )
            )
            .typography(.body)
            .foregroundStyle(.textSecondary)
        }
        .textCase(nil)
        .padding(.bottom, Spacing.medium)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The field a server's address is typed into, with the keyboard for addresses and Go to submit it.
struct ServerAddressField: View {
    @Binding var address: String
    var isFocused: FocusState<Bool>.Binding
    let submit: () -> Void

    var body: some View {
        TextField(
            String(localized: "Server Address", bundle: .module, comment: "Label of the server address field."),
            text: $address,
            prompt: Text(
                String(localized: "jellyfin.example.com", bundle: .module, comment: "Example in the address field.")
            )
        )
        .focused(isFocused)
        .autocorrectionDisabled()
        .textContentType(.URL)
        .serverAddressKeyboard()
        .submitLabel(.go)
        .onSubmit(submit)
    }
}

/// The full-width button under a form's fields, with a spinner beside its title while it works.
struct ProminentFormButton: View {
    let title: String
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xSmall) {
                if isWorking {
                    ProgressView()
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// A failure under a form's fields.
struct FailureMessage: View {
    let message: UserMessage

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Label(message.title, systemImage: message.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            Text(message.message)
                .font(.footnote)
                .foregroundStyle(.textSecondary)
        }
        .padding(.top, Spacing.xSmall)
        .accessibilityElement(children: .combine)
    }
}

/// The servers saved on this device: continue as anyone still signed in, or sign in to a server again.
private struct SavedServersSection: View {
    let onServer: (Server) -> Void
    @Environment(AppSession.self) private var session

    var body: some View {
        Section(String(localized: "Your Servers", bundle: .module, comment: "Servers saved on this device.")) {
            ForEach(session.servers) { server in
                ForEach(server.users) { user in
                    Button {
                        Task { try? await session.switchTo(SessionKey(serverID: server.id, userID: user.id)) }
                    } label: {
                        LabeledContent {
                            Text(server.displayName)
                        } label: {
                            Label(
                                String(
                                    localized: "Continue as \(user.name)",
                                    bundle: .module,
                                    comment: "Button that signs back in as a saved user, such as Continue as Alice."
                                ),
                                systemImage: "person.crop.circle"
                            )
                        }
                    }
                }
                Button {
                    onServer(server)
                } label: {
                    LabeledContent {
                        Text(server.url.host() ?? "")
                    } label: {
                        Label(
                            String(
                                localized: "Sign In to \(server.displayName)",
                                bundle: .module,
                                comment: "Button that opens sign-in for a saved server."
                            ),
                            systemImage: "server.rack"
                        )
                    }
                }
            }
        }
    }
}

extension View {
    /// The URL keyboard without automatic capitals, on platforms that have one.
    fileprivate func serverAddressKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.URL)
                .textInputAutocapitalization(.never)
        #else
            self
        #endif
    }

    /// An inline navigation title on iPhone and iPad.
    func navigationBarTitleDisplayModeInline() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }
}

#if DEBUG
    #Preview("Welcome") {
        NavigationStack { AddServerView(isWelcome: true) { _ in } }
            .environment(AppSession.preview())
    }

    #Preview("From Settings, dark") {
        NavigationStack { AddServerView { _ in } }
            .environment(AppSession.preview())
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        NavigationStack { AddServerView(isWelcome: true) { _ in } }
            .environment(AppSession.preview())
            .dynamicTypeSize(.accessibility5)
    }
#endif
