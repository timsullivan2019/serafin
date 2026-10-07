import Foundation
import SerafinCore

/// What a failure means to the user: a short title, a plain explanation and a symbol. Never a raw system error.
struct UserMessage: Equatable, Identifiable, Sendable {
    let title: String
    let message: String
    let systemImage: String
    /// Whether the server has ended the sign-in, so the way forward is signing in again rather than retrying.
    let needsSignIn: Bool

    var id: String { title + message }

    init(title: String, message: String, systemImage: String = "exclamationmark.triangle", needsSignIn: Bool = false) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.needsSignIn = needsSignIn
    }

    /// The message for an error from SerafinCore. Anything else reads as an unexpected answer.
    init(_ error: any Error) {
        guard let error = error as? SerafinError else {
            self = Self.unexpected
            return
        }
        switch error {
        case .invalidAddress:
            self.init(
                title: String(
                    localized: "Check the Address", bundle: .module, comment: "Title when a server address is wrong."),
                message: String(
                    localized: "Enter your server's address, such as jellyfin.example.com or 192.168.1.20:8096.",
                    bundle: .module,
                    comment: "Explanation when a server address can't be used."
                ),
                systemImage: "link"
            )
        case .insecureTransport:
            self.init(
                title: String(
                    localized: "This Server Needs HTTPS", bundle: .module,
                    comment: "Title when plain HTTP is refused."),
                message: String(
                    localized:
                        "Serafin only uses unencrypted connections on your own network. Use the server's https:// address instead.",
                    bundle: .module,
                    comment: "Explanation when plain HTTP to a public server is refused."
                ),
                systemImage: "lock.slash"
            )
        case .untrustedCertificate:
            self.init(
                title: String(
                    localized: "Unrecognized Certificate", bundle: .module,
                    comment: "Title when a certificate isn't trusted."),
                message: String(
                    localized: "The server's certificate has changed or isn't trusted. Check it before connecting.",
                    bundle: .module,
                    comment: "Explanation when a certificate isn't trusted."
                ),
                systemImage: "lock.trianglebadge.exclamationmark"
            )
        case .serverUnreachable:
            self.init(
                title: String(
                    localized: "Can't Reach the Server", bundle: .module,
                    comment: "Title when the server doesn't answer."),
                message: String(
                    localized: "Check that the server is running and that you're connected to the internet.",
                    bundle: .module,
                    comment: "Explanation when the server doesn't answer."
                ),
                systemImage: "wifi.exclamationmark"
            )
        case .plainHTTPBlocked:
            self.init(
                title: String(
                    localized: "iOS Blocked This Connection", bundle: .module,
                    comment: "Title when iOS refuses plain HTTP to an address."),
                message: String(
                    localized:
                        "iOS doesn't allow unencrypted connections to this kind of address. For a Tailscale address, enter the server's Tailscale machine name instead, or use HTTPS.",
                    bundle: .module,
                    comment: "Explanation when iOS refuses plain HTTP to an address, such as a Tailscale 100.x address."
                ),
                systemImage: "lock.shield"
            )
        case .notJellyfin:
            self.init(
                title: String(
                    localized: "That's Not a Jellyfin Server", bundle: .module,
                    comment: "Title when the address isn't Jellyfin."),
                message: String(
                    localized: "Something answered at that address, but it isn't Jellyfin. Check the address and port.",
                    bundle: .module,
                    comment: "Explanation when the address isn't a Jellyfin server."
                ),
                systemImage: "questionmark.diamond"
            )
        case .unsupportedServerVersion(let version):
            self.init(
                title: String(
                    localized: "This Server Needs an Update", bundle: .module,
                    comment: "Title when the server is too old."),
                message: String(
                    localized: "Serafin works with Jellyfin 10.10 or newer. This server runs \(version).",
                    bundle: .module,
                    comment: "Explanation when the server is too old. The argument is its version, such as 10.9.11."
                ),
                systemImage: "arrow.down.circle"
            )
        case .invalidCredentials:
            self.init(
                title: String(
                    localized: "Wrong Username or Password", bundle: .module,
                    comment: "Title when sign-in is refused."),
                message: String(
                    localized: "Check them and try again.",
                    bundle: .module,
                    comment: "Explanation when sign-in is refused."
                ),
                systemImage: "person.crop.circle.badge.xmark"
            )
        case .quickConnectDisabled:
            self.init(
                title: String(
                    localized: "Quick Connect Is Off", bundle: .module,
                    comment: "Title when Quick Connect is disabled."),
                message: String(
                    localized: "This server has Quick Connect turned off, so sign in with your password.",
                    bundle: .module,
                    comment: "Explanation when Quick Connect is disabled."
                ),
                systemImage: "qrcode"
            )
        case .quickConnectExpired:
            self.init(
                title: String(
                    localized: "The Code Expired", bundle: .module, comment: "Title when a Quick Connect code expires."),
                message: String(
                    localized: "Get a new code and enter it within a few minutes.",
                    bundle: .module,
                    comment: "Explanation when a Quick Connect code expires."
                ),
                systemImage: "clock.badge.xmark"
            )
        case .notSignedIn:
            self.init(
                title: String(localized: "Signed Out", bundle: .module, comment: "Title when a sign-in has ended."),
                message: String(
                    localized: "The server ended this sign-in. Sign in again to keep watching.",
                    bundle: .module,
                    comment: "Explanation when the server no longer accepts the sign-in."
                ),
                systemImage: "person.crop.circle.badge.exclamationmark",
                needsSignIn: true
            )
        case .notFound:
            self.init(
                title: String(
                    localized: "Can't Find This Item", bundle: .module, comment: "Title when an item is missing."),
                message: String(
                    localized: "It may have been removed from your library.",
                    bundle: .module,
                    comment: "Explanation when an item is missing."
                ),
                systemImage: "questionmark.square.dashed"
            )
        case .keychain, .keychainDataCorrupt:
            self.init(
                title: String(
                    localized: "Can't Use Your Saved Sign-In", bundle: .module,
                    comment: "Title when the Keychain fails."),
                message: String(
                    localized: "iOS couldn't read or save your sign-in. Restart your device and try again.",
                    bundle: .module,
                    comment: "Explanation when the Keychain fails."
                ),
                systemImage: "key"
            )
        case .serverStoreUnavailable:
            self.init(
                title: String(
                    localized: "Can't Read Your Servers", bundle: .module,
                    comment: "Title when the server list fails."),
                message: String(
                    localized: "Serafin couldn't open its list of servers. Unlock your device and try again.",
                    bundle: .module,
                    comment: "Explanation when the saved server list can't be read."
                ),
                systemImage: "externaldrive.badge.exclamationmark"
            )
        case .unexpectedResponse:
            self = Self.unexpected
        }
    }

    private static let unexpected = UserMessage(
        title: String(localized: "Something Went Wrong", bundle: .module, comment: "Title for an unexpected failure."),
        message: String(
            localized: "The server sent an answer Serafin didn't expect. Try again in a moment.",
            bundle: .module,
            comment: "Explanation for an unexpected failure."
        )
    )
}
