import SerafinCore
import SwiftUI

/// What shows while no one is signed in: add a server, then sign in to it.
struct ConnectFlow: View {
    @State private var path: [Server] = []

    var body: some View {
        NavigationStack(path: $path) {
            AddServerView(isWelcome: true) { server in path.append(server) }
                .navigationDestination(for: Server.self) { server in
                    SignInView(server: server)
                }
        }
        .onAppear { LaunchSignpost.end(showing: "Welcome") }
    }
}
