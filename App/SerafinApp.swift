import SerafinFeatures
import SwiftUI
import UIKit

@main
struct SerafinApp: App {
    @State private var session = AppSession.live(deviceName: UIDevice.current.model)

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.load() }
        }
    }
}
