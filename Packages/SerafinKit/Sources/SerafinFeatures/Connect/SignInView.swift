import NukeUI
import SerafinCore
import SerafinDesign
import SwiftUI

/// Signing in to a server: a username and password first, which the phone's Password AutoFill can fill, with the
/// server's users as pictures to tap when it lists them, and Quick Connect a button away.
struct SignInView: View {
    @State private var model: SignInModel
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    init(server: Server) {
        _model = State(initialValue: SignInModel(server: server))
    }

    var body: some View {
        Group {
            switch model.method {
            case .password:
                PasswordForm(model: model)
            case .quickConnect:
                QuickConnectPanel(model: model)
                    .task(id: model.quickConnectAttempt) { await model.runQuickConnect(with: session) }
            }
        }
        .task { await model.loadServerDetails(with: session) }
        // Signing in to a new account replaces the screens anyway; signing in as the current one changes nothing,
        // so the screen closes itself.
        .onChange(of: model.didSignIn) { _, didSignIn in
            if didSignIn { dismiss() }
        }
        .background(Color.background)
        .navigationTitle(model.server.displayName)
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

/// The username and password form, under the server's users when it lists them, with Quick Connect below.
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
            if !model.users.isEmpty {
                Section {
                    UserTiles(model: model) { user in
                        Task {
                            if await model.choose(user, with: session) {
                                field = .password
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text(
                        String(
                            localized: "Who's Watching?", bundle: .module,
                            comment: "Heading over the users a server lists on its sign-in screen.")
                    )
                }
            }
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
                    Button {
                        field = nil
                        model.method = .quickConnect
                    } label: {
                        Text(
                            String(
                                localized: "Sign In with Quick Connect",
                                bundle: .module,
                                comment: "Button that shows a Quick Connect code to approve on another device."
                            )
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets(top: Spacing.small, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
        }
        .readableWidth()
        .onAppear {
            // The name last used here is filled in already, so the password is next.
            field = model.username.isEmpty ? .username : .password
        }
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

/// The users a server lists on its sign-in screen, as pictures that fill in the name when tapped.
private struct UserTiles: View {
    let model: SignInModel
    let choose: (PublicUser) -> Void
    @ScaledMetric(relativeTo: .body) private var tileWidth = 88.0

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: tileWidth), spacing: Spacing.small, alignment: .top)],
            spacing: Spacing.medium
        ) {
            ForEach(model.users) { user in
                Button {
                    choose(user)
                } label: {
                    UserPicture(user: user, artwork: model.artwork, isSelected: user.name == model.username)
                }
                .buttonStyle(.plain)
                .disabled(model.isSigningIn)
                .accessibilityHint(
                    user.hasPassword
                        ? String(
                            localized: "Fills in this name", bundle: .module,
                            comment: "Hint on a user picture on the sign-in screen, for a user with a password.")
                        : String(
                            localized: "Signs in", bundle: .module,
                            comment: "Hint on a user picture on the sign-in screen, for a user without a password.")
                )
            }
        }
        .padding(.vertical, Spacing.xSmall)
    }
}

/// One user's tile, with their picture from the server once it loads.
private struct UserPicture: View {
    let user: PublicUser
    let artwork: Artwork?
    let isSelected: Bool
    @Environment(\.displayScale) private var scale

    var body: some View {
        if let artwork,
            let request = artwork.request(userImage: user.id, tag: user.imageTag, width: 72, scale: scale)
        {
            LazyImage(request: request) { state in
                UserTile(name: user.name, image: state.image, isSelected: isSelected)
            }
            .pipeline(artwork.pipeline)
        } else {
            UserTile(name: user.name, image: nil, isSelected: isSelected)
        }
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
    #Preview("Password") {
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
