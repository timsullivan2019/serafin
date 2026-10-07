import SerafinCore
import SerafinDesign
import SwiftUI

/// Signing in to a server: a Quick Connect code to approve from another device, or a username and password.
struct SignInView: View {
    @State private var model: SignInModel
    @Environment(AppSession.self) private var session

    init(server: Server) {
        _model = State(initialValue: SignInModel(server: server))
    }

    var body: some View {
        Group {
            switch model.method {
            case .quickConnect:
                QuickConnectPanel(model: model)
                    .task(id: model.quickConnectAttempt) { await model.runQuickConnect(with: session) }
            case .password:
                PasswordForm(model: model)
            }
        }
        .background(Color.background)
        .navigationTitle(model.server.name)
        .navigationBarTitleDisplayModeInline()
    }
}

/// The Quick Connect code, large, with how to approve it.
private struct QuickConnectPanel: View {
    let model: SignInModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xLarge) {
                switch model.quickConnect {
                case .starting:
                    ProgressView()
                        .controlSize(.large)
                        .frame(minHeight: 200)
                case .waiting(let code):
                    waiting(for: code)
                case .failed(let failure):
                    VStack(spacing: Spacing.medium) {
                        FailureMessage(message: failure)
                        Button(
                            String(
                                localized: "Get a New Code", bundle: .module,
                                comment: "Button that restarts Quick Connect.")
                        ) { model.restartQuickConnect() }
                        .buttonStyle(.glassProminent)
                    }
                }
                Button(
                    String(
                        localized: "Sign In with a Password Instead",
                        bundle: .module,
                        comment: "Button that switches to password sign-in."
                    )
                ) { model.method = .password }
            }
            .padding(Spacing.large)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }

    private func waiting(for code: String) -> some View {
        VStack(spacing: Spacing.large) {
            Text(String(localized: "Quick Connect", bundle: .module, comment: "Title of the Quick Connect panel."))
                .typography(.title)
                .foregroundStyle(.textPrimary)
            Text(code)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .kerning(6)
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, Spacing.large)
                .padding(.vertical, Spacing.medium)
                .background(.surface, in: .rounded(.medium))
                .textSelection(.enabled)
                .accessibilityLabel(
                    String(localized: "Code", bundle: .module, comment: "VoiceOver label of the Quick Connect code.")
                )
                .accessibilityValue(code.map(String.init).joined(separator: " "))
            Text(
                String(
                    localized:
                        "On a phone, computer or TV where you're signed in to Jellyfin, open your profile, choose Quick Connect, and enter this code.",
                    bundle: .module,
                    comment: "How to approve a Quick Connect code."
                )
            )
            .typography(.body)
            .foregroundStyle(.textSecondary)
            .multilineTextAlignment(.center)
            HStack(spacing: Spacing.xSmall) {
                ProgressView()
                Text(String(localized: "Waiting for approval", bundle: .module, comment: "Quick Connect status."))
                    .typography(.caption)
                    .foregroundStyle(.textSecondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// The username and password form.
private struct PasswordForm: View {
    @Bindable var model: SignInModel
    @Environment(AppSession.self) private var session
    @FocusState private var field: Field?

    private enum Field {
        case username
        case password
    }

    var body: some View {
        Form {
            Section {
                TextField(
                    String(localized: "Username", bundle: .module, comment: "Label of the username field."),
                    text: $model.username
                )
                .textContentType(.username)
                .autocorrectionDisabled()
                .usernameKeyboard()
                .focused($field, equals: .username)
                .submitLabel(.next)
                .onSubmit { field = .password }
                SecureField(
                    String(localized: "Password", bundle: .module, comment: "Label of the password field."),
                    text: $model.password
                )
                .textContentType(.password)
                .focused($field, equals: .password)
                .submitLabel(.go)
                .onSubmit(signIn)
            } header: {
                if !model.isQuickConnectAvailable {
                    Text(
                        String(
                            localized: "Quick Connect is off on this server, so sign in with your password.",
                            bundle: .module,
                            comment: "Note when the server has Quick Connect turned off."
                        )
                    )
                    .textCase(nil)
                }
            } footer: {
                if let failure = model.passwordFailure {
                    FailureMessage(message: failure)
                }
            }
            Section {
                Button(action: signIn) {
                    HStack(spacing: Spacing.xSmall) {
                        if model.isSigningIn {
                            ProgressView()
                        }
                        Text(String(localized: "Sign In", bundle: .module, comment: "Button that signs in."))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!model.canSignIn)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                if model.isQuickConnectAvailable {
                    Button(
                        String(
                            localized: "Use Quick Connect Instead",
                            bundle: .module,
                            comment: "Button that switches back to Quick Connect."
                        )
                    ) { model.method = .quickConnect }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .readableWidth()
        .onAppear { field = .username }
        .onChange(of: model.passwordFailure) { _, failure in
            if failure != nil {
                field = .password
            }
        }
    }

    private func signIn() {
        guard model.canSignIn else { return }
        field = nil
        Task { await model.signIn(with: session) }
    }
}

extension View {
    /// A keyboard for usernames: no automatic capitals.
    fileprivate func usernameKeyboard() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.never)
        #else
            self
        #endif
    }
}

#if DEBUG
    #Preview("Quick Connect") {
        NavigationStack {
            SignInView(
                server: Server(
                    id: "s", name: "Living Room", url: URL(string: "https://media.example.com") ?? .temporaryDirectory))
        }
        .environment(AppSession.preview())
    }

    #Preview("Password, dark") {
        NavigationStack {
            SignInView(
                server: Server(
                    id: "s", name: "Living Room", url: URL(string: "https://media.example.com") ?? .temporaryDirectory))
        }
        .environment(AppSession.preview())
        .preferredColorScheme(.dark)
    }
#endif
