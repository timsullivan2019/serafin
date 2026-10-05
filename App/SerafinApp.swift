import SerafinFeatures
import SwiftUI
import UIKit

@main
struct SerafinApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: AppSession
    @State private var lock: AppLock
    @State private var requests: AppRequests
    @Environment(\.scenePhase) private var phase

    init() {
        let session = AppSession.live(deviceName: UIDevice.current.model)
        let lock = AppLock()
        let requests = AppRequests()
        _session = State(initialValue: session)
        _lock = State(initialValue: lock)
        _requests = State(initialValue: requests)
        // Before anything else, since Siri may start the app just to run an intent.
        SerafinIntents.register(session: session, lock: lock, requests: requests)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(lock)
                .environment(requests)
                .task { await session.load() }
        }
        .onChange(of: phase) { _, phase in
            lock.appMoved(to: phase)
            if phase == .background {
                // Siri offers Continue Watching and Next Up for "Play … in Serafin", and watching changes them.
                SerafinShortcuts.updateAppShortcutParameters()
            }
        }
        // Another account has another library, and the lock takes the titles away.
        .onChange(of: session.account) { SerafinShortcuts.updateAppShortcutParameters() }
        .onChange(of: lock.isEnabled) { SerafinShortcuts.updateAppShortcutParameters() }
    }
}
