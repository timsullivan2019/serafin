import Foundation
import SerafinCore
import SerafinPlayback

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

    /// The message for an error from SerafinCore or SerafinPlayback. Anything else reads as an unexpected answer.
    init(_ error: any Error) {
        if let error = error as? PlaybackError {
            self = Self.playback(error)
            return
        }
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
        case .offline:
            self.init(
                title: String(
                    localized: "You're Offline", bundle: .module,
                    comment: "Title when the device has no network connection."),
                message: String(
                    localized: "Connect to Wi-Fi or turn on cellular data to reach your server.",
                    bundle: .module,
                    comment: "Explanation when the device has no network connection."
                ),
                systemImage: "wifi.slash"
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

    private static func playback(_ error: PlaybackError) -> UserMessage {
        switch error {
        case .notPlayable:
            UserMessage(
                title: String(
                    localized: "Can't Play This", bundle: .module,
                    comment: "Title when the server has no version of an item that can play."),
                message: String(
                    localized:
                        "Your server has no version of this that Serafin can play, even by converting it. Check the file on the server.",
                    bundle: .module,
                    comment: "Explanation when the server has no version of an item that can play."
                ),
                systemImage: "play.slash"
            )
        case .notAllowed:
            UserMessage(
                title: String(
                    localized: "Playback Not Allowed", bundle: .module,
                    comment: "Title when the account may not play an item."),
                message: String(
                    localized: "Your account isn't allowed to play this. Ask the person who runs your server.",
                    bundle: .module,
                    comment: "Explanation when the account may not play an item."
                ),
                systemImage: "hand.raised"
            )
        case .tooManyStreams:
            UserMessage(
                title: String(
                    localized: "Too Many Streams", bundle: .module,
                    comment: "Title when the server is already playing as many streams as it allows."),
                message: String(
                    localized: "Your server is already playing as many streams as it allows. Try again when one ends.",
                    bundle: .module,
                    comment: "Explanation when the server is already playing as many streams as it allows."
                ),
                systemImage: "person.3"
            )
        case .playerFailed:
            UserMessage(
                title: String(
                    localized: "Playback Stopped", bundle: .module,
                    comment: "Title when the player can't play a stream."),
                message: String(
                    localized:
                        "Something went wrong playing this. Try again, or lower the streaming quality in Settings.",
                    bundle: .module,
                    comment: "Explanation when the player can't play a stream."
                )
            )
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
