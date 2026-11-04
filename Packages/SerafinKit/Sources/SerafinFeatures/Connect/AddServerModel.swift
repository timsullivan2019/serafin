import Foundation
import Observation
import SerafinCore

/// Finding a server: the typed address, servers that answered on the local network, and the checks a connection
/// can need before it's saved. The same steps add another address to a saved server from Settings.
///
/// The plain-HTTP warning and the certificate check are sheets. Their buttons only close them; ``proceed(with:)``
/// carries out the answer once the sheet has gone, so the screen never moves on under a sheet that's still closing.
@Observable @MainActor final class AddServerModel {
    /// A certificate the user has to check before Serafin trusts the server.
    struct CertificateCheck: Identifiable {
        let fingerprint: CertificateFingerprint
        let address: ServerAddress
        var id: String { fingerprint.publicKeySHA256 }
    }

    /// The address a newly added server gives for itself at home or on the tailnet, offered before sign-in.
    struct AddressOffer: Identifiable {
        /// The server, saved and waiting for sign-in.
        let server: Server
        /// The server as it answered at the offered address.
        let connected: ConnectedServer
        var id: URL { connected.server.url }
    }

    /// Where adding goes once what answered is saved.
    enum Next: Equatable {
        /// Signing in to the server.
        case signIn(Server)
        /// The addresses of the saved server with this ID, which now include the one that answered. There's nothing
        /// to sign in to: the address was for ``target``, or for a server someone is signed in to already.
        case addresses(serverID: String)
    }

    /// The saved server another address is being added to, or nil when a server is being added.
    let target: Server?
    /// Whether a server that's saved already, with someone signed in to it, takes the address as one more of its own
    /// rather than going on to sign-in. Settings' Add Server does; the welcome screen, which is there to sign in,
    /// doesn't.
    let addsToSignedInServers: Bool

    /// What the address field holds.
    var address = ""
    private(set) var isConnecting = false
    private(set) var failure: UserMessage?
    /// Jellyfin servers that answered on the local network.
    private(set) var discovered: [DiscoveredServer] = []
    /// A server on the local network that answered over plain HTTP, waiting for the user to accept the warning.
    var unencrypted: ConnectedServer?
    /// A certificate waiting for the user to check it.
    var certificate: CertificateCheck?
    /// The address a newly added server gives for itself, waiting for the user to say whether to add it.
    var offer: AddressOffer?
    /// The offered plain-HTTP address the user said yes to, waiting for them to accept the warning.
    var unencryptedOffer: AddressOffer?
    /// What the user answered on the sheet that's closing, for ``proceed(with:)``.
    private var answer: Answer?

    /// Creates the model.
    ///
    /// - Parameters:
    ///   - target: The saved server to add another address to, or nil to add a server.
    ///   - addsToSignedInServers: Whether a server that's saved already, with someone signed in to it, takes the
    ///     address rather than going on to sign-in, as from Settings.
    init(adding target: Server? = nil, addsToSignedInServers: Bool = false) {
        self.target = target
        self.addsToSignedInServers = addsToSignedInServers
    }

    /// Whether the address field holds anything to connect to.
    var canConnect: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isConnecting
    }

    /// Connects to the typed address. Returns where adding goes next, or nil when the user has to accept a warning,
    /// check a certificate or answer the offer of another address first, or when it failed.
    func connect(with session: AppSession) async -> Next? {
        failure = nil
        let parsed: ServerAddress
        do {
            parsed = try ServerAddress.parse(address)
        } catch {
            failure = UserMessage(error)
            return nil
        }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let connected = try await session.connect(to: parsed)
            if connected.security == .unencryptedOnPrivateNetwork {
                unencrypted = connected
                return nil
            }
            return try await save(connected, with: session)
        } catch SerafinError.untrustedCertificate(let fingerprint) {
            certificate = CertificateCheck(fingerprint: fingerprint, address: parsed)
        } catch is CancellationError {
        } catch {
            failure = UserMessage(error)
        }
        return nil
    }

    /// Connects to a server that answered on the local network.
    func connect(to server: DiscoveredServer, with session: AppSession) async -> Next? {
        address = server.url.absoluteString
        return await connect(with: session)
    }

    /// Accepts the plain-HTTP warning, which closes it. The server is saved once it has closed.
    func acceptUnencrypted() {
        guard let connected = unencrypted else { return }
        keep(.acceptedUnencrypted(connected))
        unencrypted = nil
    }

    /// Trusts the certificate the user has checked, which closes the check. It's pinned and the server connected to
    /// again once the check has closed.
    func trustCertificate() {
        guard let check = certificate else { return }
        keep(.trusted(check))
        certificate = nil
    }

    /// Adds the offered address once the user has said yes. Returns sign-in for the server, or nil while the warning
    /// for a plain-HTTP address waits. The server goes on to sign-in whether or not the address could be added.
    func acceptOffer(_ offer: AddressOffer, with session: AppSession) async -> Next? {
        self.offer = nil
        if offer.connected.security == .unencryptedOnPrivateNetwork {
            unencryptedOffer = offer
            return nil
        }
        return await add(offer, with: session)
    }

    /// Leaves the offered address out. Returns sign-in for the server.
    func declineOffer(_ offer: AddressOffer) -> Next {
        self.offer = nil
        return .signIn(offer.server)
    }

    /// Accepts the warning for the offered plain-HTTP address, which closes it. The address is added once it has.
    func acceptUnencryptedOffer() {
        guard let offer = unencryptedOffer else { return }
        keep(.acceptedOffer(offer))
        unencryptedOffer = nil
    }

    /// Turns down the warning for the offered plain-HTTP address, which closes it, leaving the address out. Sign-in
    /// follows once it has closed.
    func declineUnencryptedOffer() {
        guard let offer = unencryptedOffer else { return }
        keep(.declinedOffer(offer))
        unencryptedOffer = nil
    }

    /// Carries out what the user answered on the warning or the certificate check, once the sheet has closed.
    /// Returns where adding goes next, or nil when the sheet was cancelled, another check is needed, or it failed.
    func proceed(with session: AppSession) async -> Next? {
        guard let answer else { return nil }
        self.answer = nil
        isConnecting = true
        defer { isConnecting = false }
        switch answer {
        case .acceptedUnencrypted(let connected):
            do {
                return try await save(connected, with: session)
            } catch {
                failure = UserMessage(error)
                return nil
            }
        case .trusted(let check):
            do {
                try await session.trust(check.fingerprint, for: check.address)
            } catch {
                failure = UserMessage(error)
                return nil
            }
            return await connect(with: session)
        case .acceptedOffer(let offer):
            return await add(offer, with: session)
        case .declinedOffer(let offer):
            return .signIn(offer.server)
        }
    }

    /// Saves what answered: a server of its own, or another address of ``target``, or of a saved server someone is
    /// signed in to when ``addsToSignedInServers`` is on. A new server that gives an address for itself at home or on
    /// its tailnet, where it answers too, has it offered first, and nil comes back meanwhile.
    private func save(_ connected: ConnectedServer, with session: AppSession) async throws -> Next? {
        if let target {
            try await session.addAddress(connected, to: target)
            return .addresses(serverID: target.id)
        }
        if addsToSignedInServers,
            let saved = session.servers.first(where: { $0.id == connected.server.id }), !saved.users.isEmpty
        {
            // Signing in again would only replace the sign-in the app is using.
            try await session.addAddress(connected, to: saved)
            return .addresses(serverID: saved.id)
        }
        let saved = try await session.add(connected)
        if let local = await session.suggestedAddress(for: saved, reportedBy: connected.info) {
            offer = AddressOffer(server: saved, connected: local)
            return nil
        }
        return .signIn(saved)
    }

    /// Adds an offered address. The server goes on to sign-in whether or not the address could be added.
    private func add(_ offer: AddressOffer, with session: AppSession) async -> Next {
        do {
            try await session.addAddress(offer.connected, to: offer.server)
        } catch {
            failure = UserMessage(error)
        }
        return .signIn(offer.server)
    }

    /// Listens for Jellyfin servers on the local network for a few seconds.
    func discover() async {
        for await server in LocalDiscovery.servers() where !discovered.contains(server) {
            discovered.append(server)
        }
    }

    /// Keeps what the user answered on a sheet for once it has closed, showing the work under way meanwhile.
    private func keep(_ given: Answer) {
        answer = given
        isConnecting = true
    }

    /// What the user answered on a sheet.
    private enum Answer {
        case acceptedUnencrypted(ConnectedServer)
        case trusted(CertificateCheck)
        case acceptedOffer(AddressOffer)
        case declinedOffer(AddressOffer)
    }
}
