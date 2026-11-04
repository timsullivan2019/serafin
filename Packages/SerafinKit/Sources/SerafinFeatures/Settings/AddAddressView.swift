import SerafinCore
import SerafinDesign
import SwiftUI

/// Adding another address to a saved server, from its addresses in Settings: type one, or pick the server where it
/// answered on the local network. The address is saved only when the same server answers there, after the warning
/// for plain HTTP or the certificate check when it needs one, and the screen goes back to the addresses.
struct AddAddressView: View {
    /// The saved server the address is for.
    let server: Server
    @State private var model: AddServerModel
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @FocusState private var addressFocused: Bool

    /// Creates the screen.
    ///
    /// - Parameter server: The saved server to add an address to.
    init(server: Server) {
        self.server = server
        _model = State(initialValue: AddServerModel(adding: server))
    }

    var body: some View {
        Form {
            Section {
                ServerAddressField(address: $model.address, isFocused: $addressFocused, submit: add)
            } footer: {
                if let failure = model.failure {
                    FailureMessage(message: failure)
                } else {
                    Text(
                        String(
                            localized:
                                "Another address \(server.displayName) answers at, such as its address at home or on Tailscale.",
                            bundle: .module,
                            comment:
                                "Under the field for adding an address to a server. The argument is the server's name."
                        )
                    )
                }
            }
            Section {
                ProminentFormButton(
                    title: String(
                        localized: "Add", bundle: .module, comment: "Button that adds the typed address to a server."),
                    isWorking: model.isConnecting, action: add
                )
                .disabled(!model.canConnect)
            }
            if !nearby.isEmpty {
                Section(String(localized: "On This Network", bundle: .module, comment: "Servers found nearby.")) {
                    ForEach(nearby) { found in
                        Button {
                            Task { finish(await model.connect(to: found, with: session)) }
                        } label: {
                            LabeledContent(found.displayName, value: AddressText.short(found.url))
                        }
                        .disabled(model.isConnecting)
                    }
                }
            }
        }
        .readableWidth()
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayModeInline()
        .task { await model.discover() }
        // Each sheet's buttons only close it, and the screen goes back once it has gone.
        .sheet(item: $model.unencrypted, onDismiss: proceed) { connected in
            UnencryptedConnectionSheet(server: connected.server) {
                model.acceptUnencrypted()
            } cancel: {
                model.unencrypted = nil
            }
            .scrollIndicators(.never)
        }
        .sheet(item: $model.certificate, onDismiss: proceed) { check in
            CertificateSheet(fingerprint: check.fingerprint, host: check.address.url.host() ?? "") {
                model.trustCertificate()
            } cancel: {
                model.certificate = nil
            }
            .scrollIndicators(.never)
        }
    }

    /// The title of this screen, of its row among a server's addresses, and of the button that adds an offered
    /// address.
    static var title: String {
        String(
            localized: "Add Address", bundle: .module,
            comment:
                "Title of the screen that adds an address to a server, its row in Settings, and the button that adds an address a server gives for itself."
        )
    }

    /// The server where it answered on the local network, at an address it doesn't have yet. Other servers that
    /// answered aren't listed: they're added as servers of their own.
    private var nearby: [DiscoveredServer] {
        let saved = session.servers.first { $0.id == server.id } ?? server
        return model.discovered.filter { $0.id == server.id && saved.address(matching: $0.url) == nil }
    }

    private func add() {
        guard model.canConnect else { return }
        addressFocused = false
        Task { finish(await model.connect(with: session)) }
    }

    /// Carries out what was said on the sheet that has just closed.
    private func proceed() {
        Task { finish(await model.proceed(with: session)) }
    }

    /// Goes back to the addresses once the address is saved.
    private func finish(_ next: AddServerModel.Next?) {
        if next != nil {
            dismiss()
        }
    }
}

#if DEBUG
    #Preview("Add address") {
        NavigationStack { AddAddressView(server: .previewWithAddresses) }
            .environment(AppSession.preview())
    }

    #Preview("Add address, dark") {
        NavigationStack { AddAddressView(server: .previewWithAddresses) }
            .environment(AppSession.preview())
            .preferredColorScheme(.dark)
    }

    #Preview("Add address, largest text") {
        NavigationStack { AddAddressView(server: .previewWithAddresses) }
            .environment(AppSession.preview())
            .dynamicTypeSize(.accessibility5)
    }
#endif
