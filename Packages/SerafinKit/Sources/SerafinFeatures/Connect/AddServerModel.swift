import Foundation
import Observation
import SerafinCore

/// Finding a server: the typed address, servers that answered on the local network, and the checks a connection
/// can need before it's saved. The same steps add another address to a saved server from Settings.
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

    /// The saved server another address is being added to, or nil when a server is being added.
    let target: Server?

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

    /// Creates the model.
    ///
    /// - Parameter target: The saved server to add another address to, or nil to add a server.
    init(adding target: Server? = nil) {
        self.target = target
    }

    /// Whether the address field holds anything to connect to.
    var canConnect: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isConnecting
    }

    /// Connects to the typed address. Returns the saved server when it is ready for sign-in, or nil when the user
    /// has to accept a warning, check a certificate or answer the offer of another address first, or when it failed.
    func connect(with session: AppSession) async -> Server? {
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
    func connect(to server: DiscoveredServer, with session: AppSession) async -> Server? {
        address = server.url.absoluteString
        return await connect(with: session)
    }

    /// Saves the plain-HTTP server once the user has accepted the warning.
    func acceptUnencrypted(with session: AppSession) async -> Server? {
        guard let connected = unencrypted else { return nil }
        unencrypted = nil
        isConnecting = true
        defer { isConnecting = false }
        do {
            return try await save(connected, with: session)
        } catch {
            failure = UserMessage(error)
            return nil
        }
    }

    /// Adds the offered address once the user has said yes, and for plain HTTP accepted the warning too. Returns the
    /// server for sign-in, or nil while the warning waits. The server is ready for sign-in whether or not the address
    /// could be added.
    func acceptOffer(_ offer: AddressOffer, with session: AppSession) async -> Server? {
        self.offer = nil
        if offer.connected.security == .unencryptedOnPrivateNetwork, unencryptedOffer?.id != offer.id {
            unencryptedOffer = offer
            return nil
        }
        unencryptedOffer = nil
        do {
            try await session.addAddress(offer.connected, to: offer.server)
        } catch {
            failure = UserMessage(error)
        }
        return offer.server
    }

    /// Leaves the offered address out. Returns the server for sign-in.
    func declineOffer(_ offer: AddressOffer) -> Server {
        self.offer = nil
        unencryptedOffer = nil
        return offer.server
    }

    /// Saves what answered: a server of its own, or another address of ``target``. A new server that gives an address
    /// for itself at home or on its tailnet, where it answers too, has it offered first, and nil comes back meanwhile.
    private func save(_ connected: ConnectedServer, with session: AppSession) async throws -> Server? {
        if let target {
            try await session.addAddress(connected, to: target)
            return target
        }
        let saved = try await session.add(connected)
        if let local = await session.suggestedAddress(for: saved, reportedBy: connected.info) {
            offer = AddressOffer(server: saved, connected: local)
            return nil
        }
        return saved
    }

    /// Pins the certificate the user has checked, then connects again.
    func trustCertificate(with session: AppSession) async -> Server? {
        guard let check = certificate else { return nil }
        certificate = nil
        do {
            try await session.trust(check.fingerprint, for: check.address)
        } catch {
            failure = UserMessage(error)
            return nil
        }
        return await connect(with: session)
    }

    /// Listens for Jellyfin servers on the local network for a few seconds.
    func discover() async {
        for await server in LocalDiscovery.servers() where !discovered.contains(server) {
            discovered.append(server)
        }
    }
}
