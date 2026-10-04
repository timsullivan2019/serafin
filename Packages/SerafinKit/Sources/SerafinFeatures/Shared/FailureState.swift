import SerafinCore
import SerafinDesign
import SwiftUI

/// What a screen shows when loading fails: the failure in plain words, with Try Again, or Sign In Again when the
/// server has ended the sign-in.
struct FailureState: View {
    let message: UserMessage
    let retry: () -> Void
    @Environment(\.signInEnded) private var signInEnded

    var body: some View {
        if message.needsSignIn {
            EmptyState(
                message.title,
                message: message.message,
                systemImage: message.systemImage,
                action: StateAction(
                    String(localized: "Sign In Again", bundle: .module, comment: "Button after a sign-in has ended.")
                ) { signInEnded() }
            )
        } else {
            ErrorState(message.title, message: message.message, systemImage: message.systemImage, retry: retry)
        }
    }
}

/// Signs out the current account on this device, after the server has ended its sign-in.
struct SignInEndedAction: Equatable, Sendable {
    /// The account it signs out, which is also what makes two actions equal.
    let account: SessionKey?
    fileprivate let perform: @MainActor @Sendable () -> Void

    init(account: SessionKey?, perform: @escaping @MainActor @Sendable () -> Void) {
        self.account = account
        self.perform = perform
    }

    @MainActor func callAsFunction() {
        perform()
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.account == rhs.account
    }
}

extension EnvironmentValues {
    /// Signs out the current account on this device, after the server has ended its sign-in.
    @Entry var signInEnded = SignInEndedAction(account: nil) {}
}

#if DEBUG
    extension View {
        /// The environment every screen expects, with the built-in samples, for previews.
        func previewEnvironment() -> some View {
            environment(PlaybackCoordinator())
                .environment(MediaActions())
        }
    }
#endif
