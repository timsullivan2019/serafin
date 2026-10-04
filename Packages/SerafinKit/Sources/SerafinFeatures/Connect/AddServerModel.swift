import Foundation
import Observation
import SerafinCore

/// Finding a server: the typed address, servers that answered on the local network, and the checks a connection
/// can need before it's saved.
@Observable @MainActor final class AddServerModel {
    /// A certificate the user has to check before Serafin trusts the server.
    struct CertificateCheck: Identifiable {
        let fingerprint: CertificateFingerprint
        let address: ServerAddress
        var id: String { fingerprint.publicKeySHA256 }
    }

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

    /// Whether the address field holds anything to connect to.
    var canConnect: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isConnecting
    }

    /// Connects to the typed address. Returns the saved server when it is ready for sign-in, or nil when the user
    /// has to accept a warning or check a certificate first, or when it failed.
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
            return try await session.add(connected)
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
        do {
            return try await session.add(connected)
        } catch {
            failure = UserMessage(error)
            return nil
        }
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
