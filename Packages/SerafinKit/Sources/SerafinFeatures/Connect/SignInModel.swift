import Foundation
import Observation
import SerafinCore

/// Signing in to one server: Quick Connect first, a password when the user prefers it or the server has Quick
/// Connect turned off.
@Observable @MainActor final class SignInModel {
    enum Method {
        case quickConnect
        case password
    }

    enum QuickConnectState: Equatable {
        case starting
        case waiting(code: String)
        case failed(UserMessage)
    }

    let server: Server
    var method = Method.quickConnect
    private(set) var quickConnect = QuickConnectState.starting
    /// False once the server says Quick Connect is off.
    private(set) var isQuickConnectAvailable = true
    /// Goes up by one to start Quick Connect over with a new code.
    private(set) var quickConnectAttempt = 0

    var username = ""
    /// The password as typed. Cleared the moment it is sent.
    var password = ""
    private(set) var isSigningIn = false
    private(set) var passwordFailure: UserMessage?

    init(server: Server) {
        self.server = server
    }

    /// Whether the password form can be sent.
    var canSignIn: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !isSigningIn
    }

    /// Gets a code and waits for it to be approved. On approval the session signs in, which leaves the connect flow.
    func runQuickConnect(with session: AppSession) async {
        quickConnect = .starting
        do {
            let request = try await session.startQuickConnect(on: server)
            quickConnect = .waiting(code: request.code)
            try await session.finishQuickConnect(request)
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
        } catch is CancellationError {
        } catch {
            passwordFailure = UserMessage(error)
        }
    }
}
