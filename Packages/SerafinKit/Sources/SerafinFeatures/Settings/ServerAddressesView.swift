import SerafinCore
import SerafinDesign
import SwiftUI

/// A server's addresses, from Settings: which one Serafin is connected through, adding and removing one, and a test of
/// which answer. Serafin moves between them by itself; this is where the user sees and changes the list.
struct ServerAddressesView: View {
    /// The server whose addresses show.
    let serverID: String
    @Environment(AppSession.self) private var session
    /// Which addresses answered the last test, or nil before one.
    @State private var answering: Set<URL>?
    @State private var isTesting = false
    @State private var failure: UserMessage?
    /// The address the server gives for itself at home or on the tailnet, offered when it isn't saved yet.
    @State private var suggestion: ConnectedServer?
    /// The suggested plain-HTTP address, waiting for the user to accept the warning.
    @State private var unencrypted: ConnectedServer?

    var body: some View {
        Form {
            if let server = session.servers.first(where: { $0.id == serverID }) {
                addresses(of: server)
                if let suggestion, server.address(matching: suggestion.server.url) == nil {
                    suggestionSection(suggestion, for: server)
                }
                actions(for: server)
            }
        }
        .readableWidth()
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayModeInline()
        .task(id: serverID) {
            guard let server = session.servers.first(where: { $0.id == serverID }) else { return }
            suggestion = await session.suggestedAddress(for: server)
        }
        .sheet(item: $unencrypted) { connected in
            UnencryptedConnectionSheet(server: connected.server) {
                unencrypted = nil
                Task { await add(connected) }
            } cancel: {
                unencrypted = nil
            }
            .scrollIndicators(.never)
        }
    }

    /// The title of this screen, and of its row in Settings.
    static var title: String {
        String(
            localized: "Addresses", bundle: .module,
            comment: "Title of the screen listing a server's addresses in Settings, and of its row.")
    }

    private func addresses(of server: Server) -> some View {
        Section {
            ForEach(server.addresses, id: \.self) { address in
                let canRemove = server.addresses.count > 1 && (address != server.url || canMove(server))
                AddressRow(
                    address: address, isInUse: address == server.url,
                    answers: isTesting ? nil : answering.map { $0.contains(address) }
                )
                .swipeActions {
                    if canRemove {
                        removeButton(address, from: server)
                    }
                }
                .contextMenu {
                    if canRemove {
                        removeButton(address, from: server)
                    }
                }
            }
        } footer: {
            Text(AddressKindText.connected(via: ServerAddressKind(server.url)))
        }
    }

    private func suggestionSection(_ suggestion: ConnectedServer, for server: Server) -> some View {
        Section {
            Button {
                if suggestion.security == .unencryptedOnPrivateNetwork {
                    unencrypted = suggestion
                } else {
                    Task { await add(suggestion) }
                }
            } label: {
                Label(
                    AddressKindText.offer(suggestion.server.url),
                    systemImage: "plus.circle"
                )
            }
        } footer: {
            Text(AddressKindText.offerReason(serverName: server.displayName))
        }
    }

    private func actions(for server: Server) -> some View {
        Section {
            NavigationLink(value: Route.addAddress(server)) {
                Label(AddAddressView.title, systemImage: "plus")
            }
            .disabled(server.addresses.count >= Server.maximumAddresses)
            Button {
                Task { await test(server) }
            } label: {
                HStack {
                    Label(
                        String(
                            localized: "Test Addresses", bundle: .module,
                            comment: "Button that checks which of a server's addresses answer."),
                        systemImage: "checkmark.circle"
                    )
                    Spacer()
                    if isTesting {
                        ProgressView()
                    }
                }
            }
            .disabled(isTesting)
        } footer: {
            if let failure {
                FailureMessage(message: failure)
            } else {
                Text(
                    String(
                        localized:
                            "Serafin uses whichever address answers best where you are: one at home on Wi-Fi, a remote one on cellular. Your sign-in works at all of them.",
                        bundle: .module,
                        comment: "Footer explaining how Serafin picks among a server's addresses."
                    )
                )
            }
        }
    }

    private func removeButton(_ address: URL, from server: Server) -> some View {
        Button(role: .destructive) {
            Task { await run { try await session.removeAddress(address, from: server) } }
        } label: {
            Label(
                String(
                    localized: "Remove", bundle: .module, comment: "Button that removes one of a server's addresses."),
                systemImage: "trash"
            )
        }
        .tint(.red)
    }

    /// Whether `server` may move off the address it's connected through: always, unless it's the current account's
    /// server and the player has something loaded, since a stream can't change address as it plays.
    private func canMove(_ server: Server) -> Bool {
        server.id != session.account?.server.id || session.isPlayerIdle
    }

    private func test(_ server: Server) async {
        isTesting = true
        defer { isTesting = false }
        answering = await session.answeringAddresses(of: server)
    }

    private func add(_ connected: ConnectedServer) async {
        guard let server = session.servers.first(where: { $0.id == serverID }) else { return }
        await run {
            try await session.addAddress(connected, to: server)
            suggestion = nil
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

/// One of a server's addresses: the address, with a lock for HTTPS, what kind it is, a check by the one in use, and
/// what the last test found.
private struct AddressRow: View {
    let address: URL
    let isInUse: Bool
    /// Whether the address answered the last test, or nil when there's no result to show.
    let answers: Bool?

    var body: some View {
        HStack(spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxSmall) {
                    if address.scheme?.lowercased() == "https" {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .accessibilityLabel(
                                String(
                                    localized: "Encrypted", bundle: .module,
                                    comment: "Spoken for the lock beside an HTTPS server's address in Settings."))
                    }
                    Text(AddressText.short(address))
                }
                .foregroundStyle(.textPrimary)
                Text(AddressKindText.kind(ServerAddressKind(address)))
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }
            Spacer(minLength: 0)
            if let answers {
                Image(systemName: answers ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(answers ? Color.green : Color.red)
                    .accessibilityLabel(answers ? AddressKindText.answers : AddressKindText.doesNotAnswer)
            }
            if isInUse {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel(
                        String(
                            localized: "In use", bundle: .module,
                            comment: "Spoken for the check by the address Serafin is connected through."))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isInUse ? .isSelected : [])
    }
}

/// The words for a server's addresses, by their kind.
enum AddressKindText {
    /// What kind of address it is, under the address.
    static func kind(_ kind: ServerAddressKind) -> String {
        switch kind {
        case .local:
            String(
                localized: "Home network", bundle: .module,
                comment: "Kind of a server address on the user's own network.")
        case .tailscale:
            String(
                localized: "Tailscale", bundle: .module,
                comment: "Kind of a server address on the user's tailnet. Tailscale is a product name.")
        case .remote:
            String(
                localized: "Remote address", bundle: .module,
                comment: "Kind of a server address reached over the internet.")
        }
    }

    /// Which kind of address Serafin is connected through.
    static func connected(via kind: ServerAddressKind) -> String {
        switch kind {
        case .local:
            String(
                localized: "Connected via home network.", bundle: .module,
                comment:
                    "Under a server's addresses: Serafin is connected through its address on the user's own network.")
        case .tailscale:
            String(
                localized: "Connected via Tailscale.", bundle: .module,
                comment: "Under a server's addresses: Serafin is connected through its Tailscale address.")
        case .remote:
            String(
                localized: "Connected via remote address.", bundle: .module,
                comment: "Under a server's addresses: Serafin is connected through its address on the internet.")
        }
    }

    /// The offer to add an address a server gives for itself, as a button among its addresses.
    static func offer(_ address: URL) -> String {
        let text = AddressText.short(address)
        return switch ServerAddressKind(address) {
        case .tailscale:
            String(
                localized: "Also use \(text) over Tailscale", bundle: .module,
                comment:
                    "Offer to add a server's Tailscale address. The argument is the address, such as 100.101.102.103:8096."
            )
        case .local, .remote:
            String(
                localized: "Also use \(text) at home", bundle: .module,
                comment:
                    "Offer to add a server's address on the user's own network. The argument is the address, such as 192.168.1.20:8096."
            )
        }
    }

    /// The offer to add an address a server gives for itself, as the title of the question asked once the server is
    /// added.
    static func offerTitle(_ address: URL) -> String {
        let text = AddressText.short(address)
        return switch ServerAddressKind(address) {
        case .tailscale:
            String(
                localized: "Also Use \(text) over Tailscale?", bundle: .module,
                comment:
                    "Title of the question, once a server is added, offering to add its Tailscale address. The argument is the address, such as 100.101.102.103:8096."
            )
        case .local, .remote:
            String(
                localized: "Also Use \(text) at Home?", bundle: .module,
                comment:
                    "Title of the question, once a server is added, offering to add its address on the user's own network. The argument is the address, such as 192.168.1.20:8096."
            )
        }
    }

    /// Why an address a server gives for itself is offered, under the offer among its addresses.
    static func offerReason(serverName: String) -> String {
        String(
            localized: "\(serverName) reports this as its own address, and answers there.", bundle: .module,
            comment:
                "Under the offer to add the address a server gives for itself on its own network. The argument is the server's name."
        )
    }

    /// Why an address a server gives for itself is offered, in the question asked once the server is added.
    static func offerMessage(serverName: String) -> String {
        String(
            localized:
                "\(serverName) reports this as its own address, and answers there. Serafin uses whichever address answers best where you are.",
            bundle: .module,
            comment:
                "Message of the question offering to add the address a server gives for itself, once it's added. The argument is the server's name."
        )
    }

    /// Spoken for an address that answered the test.
    static var answers: String {
        String(localized: "Answers", bundle: .module, comment: "Spoken for an address that answered the test.")
    }

    /// Spoken for an address that didn't answer the test.
    static var doesNotAnswer: String {
        String(
            localized: "Doesn't answer", bundle: .module, comment: "Spoken for an address that didn't answer the test.")
    }
}

/// How addresses read on screen.
enum AddressText {
    /// `url` without its scheme or a slash at the end, such as "media.example.com" or "192.168.1.20:8096".
    static func short(_ url: URL) -> String {
        var text = url.absoluteString
        if let scheme = url.scheme, text.hasPrefix("\(scheme)://") {
            text.removeFirst(scheme.count + 3)
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }
}

#if DEBUG
    #Preview("Addresses") {
        let session = AppSession.preview(servers: [.previewWithAddresses])
        NavigationStack { ServerAddressesView(serverID: Server.previewWithAddresses.id) }
            .environment(session)
            .task { await session.load() }
    }

    #Preview("Addresses, dark") {
        let session = AppSession.preview(servers: [.previewWithAddresses])
        NavigationStack { ServerAddressesView(serverID: Server.previewWithAddresses.id) }
            .environment(session)
            .task { await session.load() }
            .preferredColorScheme(.dark)
    }

    #Preview("Addresses, largest text") {
        let session = AppSession.preview(servers: [.previewWithAddresses])
        NavigationStack { ServerAddressesView(serverID: Server.previewWithAddresses.id) }
            .environment(session)
            .task { await session.load() }
            .dynamicTypeSize(.accessibility5)
    }
#endif
