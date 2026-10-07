import SerafinFeatures
import SwiftUI
import UIKit

@main
struct SerafinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session = AppSession.live(deviceName: UIDevice.current.model)
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(lock)
                .task { await session.load() }
        }
        .onChange(of: phase) { _, phase in lock.appMoved(to: phase) }
    }
}
