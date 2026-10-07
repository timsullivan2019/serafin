import Foundation
import Observation
import SerafinCore

/// Signing in to one server: a username and password first, as the phone's Password AutoFill expects, with Quick
/// Connect beside it when the server has it turned on.
///
/// The server's sign-in screen users, if it shows any, appear as pictures; tapping one fills in the name.
@Observable @MainActor final class SignInModel {
    enum Method {
        case password
        case quickConnect
    }

    enum QuickConnectState: Equatable {
        case starting
        case waiting(code: String)
        case failed(UserMessage)
    }

    let server: Server
    var method = Method.password
    private(set) var quickConnect = QuickConnectState.starting
    /// False once the server says Quick Connect is off.
    private(set) var isQuickConnectAvailable = true
    /// Goes up by one to start Quick Connect over with a new code.
    private(set) var quickConnectAttempt = 0
    /// The users the server lists on its sign-in screen.
    private(set) var users: [PublicUser] = []
    /// Loads the users' pictures, once the server has answered.
    private(set) var artwork: Artwork?

    /// The name to sign in with, which starts as the one last used on this server.
    var username: String
    /// The password as typed. Cleared the moment it is sent.
    var password = ""
    private(set) var isSigningIn = false
    private(set) var passwordFailure: UserMessage?
    /// Whether a sign-in has worked, so the screen can close even when it signed in as the account already in use,
    /// which changes nothing else.
    private(set) var didSignIn = false

    init(server: Server, defaults: UserDefaults = .standard) {
        self.server = server
        username = LastUsername.name(forServer: server.id, in: defaults) ?? ""
    }

    /// Whether the password form can be sent.
    var canSignIn: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !isSigningIn
    }

    /// Asks the server for its sign-in screen users and whether Quick Connect is on. Neither is needed to sign in,
    /// so a failure leaves them out.
    func loadServerDetails(with session: AppSession) async {
        async let users = try? session.publicUsers(on: server)
        async let quickConnectEnabled = session.isQuickConnectEnabled(on: server)
        artwork = try? await session.signInArtwork(for: server)
        self.users = await users ?? []
        if await quickConnectEnabled == false {
            isQuickConnectAvailable = false
        }
    }

    /// Picks a user from the server's list: fills in their name, and signs in at once when they have no password.
    ///
    /// - Returns: Whether the user still needs to type a password.
    @discardableResult func choose(_ user: PublicUser, with session: AppSession) async -> Bool {
        username = user.name
        password = ""
        passwordFailure = nil
        guard user.hasPassword else {
            await signIn(with: session)
            return false
        }
        return true
    }

    /// Gets a code and waits for it to be approved. On approval the session signs in, which leaves the connect flow.
    func runQuickConnect(with session: AppSession) async {
        quickConnect = .starting
        do {
            let request = try await session.startQuickConnect(on: server)
            quickConnect = .waiting(code: request.code)
            try await session.finishQuickConnect(request)
            didSignIn = true
        } catch is CancellationError {
        } catch SerafinError.quickConnectDisabled {
            isQuickConnectAvailable = false
            method = .password
        } catch {
            quickConnect = .failed(UserMessage(error))
        }
    }

    /// Starts Quick Connect over with a new code.
    func restartQuickConnect() {
        quickConnectAttempt += 1
    }

    /// Signs in with the username and password. The password is cleared as it is sent, whatever the outcome.
    func signIn(with session: AppSession) async {
        guard canSignIn else { return }
        let password = password
        self.password = ""
        passwordFailure = nil
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            try await session.signIn(
                to: server,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            didSignIn = true
        } catch is CancellationError {
        } catch {
            passwordFailure = UserMessage(error)
        }
    }
}
