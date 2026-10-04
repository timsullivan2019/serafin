import Foundation

/// A signed-in user on a server: what the app is browsing as.
public struct Account: Hashable, Sendable {
    /// The server, as saved.
    public let server: Server
    /// The user.
    public let user: ServerUser

    /// Creates an account.
    public init(server: Server, user: ServerUser) {
        self.server = server
        self.user = user
    }

    /// The key of this account's token and of the current selection.
    public var key: SessionKey {
        SessionKey(serverID: server.id, userID: user.id)
    }
}

/// A Quick Connect sign-in waiting for approval.
///
/// The user types ``code`` into a Jellyfin app or web page where they are already signed in. Serafin then
/// exchanges the request's secret for a token. The secret never leaves SerafinCore.
public struct QuickConnectRequest: Sendable {
    /// The code to show the user.
    public let code: String
    /// The server the code belongs to.
    public let server: Server
    /// Exchanged for a token once the code is approved. Never shown or logged.
    let secret: String
}
