import SerafinDesign
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

extension View {
    /// Covers the window with the lock screen while `lock` is locked, and with a plain cover whenever the lock is on
    /// and the window isn't in use, as in the app switcher. Nil leaves the window alone, as in previews.
    func appLock(_ lock: AppLock?) -> some View {
        modifier(AppLockLayer(lock: lock))
    }
}

/// On iOS the lock screen is a window of its own above the app's, so it also covers the full-screen player and any
/// sheet, which iOS presents above the app's own window.
private struct AppLockLayer: ViewModifier {
    let lock: AppLock?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        #if canImport(UIKit)
            content.background {
                if let lock {
                    // Read here, rather than in the window, so a change to either updates the window.
                    LockWindowHost(lock: lock, shows: lock.isLocked || (lock.isEnabled && scenePhase != .active))
                }
            }
        #else
            content.overlay {
                if let lock, lock.isLocked {
                    LockScreen(lock: lock)
                }
            }
        #endif
    }
}

#if canImport(UIKit)
    /// Finds the window scene it's in, and shows the lock's window in that scene whenever there's something to
    /// cover.
    private struct LockWindowHost: UIViewRepresentable {
        let lock: AppLock
        let shows: Bool

        func makeUIView(context: Context) -> SceneFinder {
            SceneFinder()
        }

        func updateUIView(_ finder: SceneFinder, context: Context) {
            finder.update(lock: lock, shows: shows)
        }

        static func dismantleUIView(_ finder: SceneFinder, coordinator: ()) {
            finder.removeWindow()
        }
    }

    /// An empty view that learns its window scene once it's on screen, and owns the lock's window there.
    private final class SceneFinder: UIView {
        private var lockWindow: UIWindow?
        private var host: UIHostingController<LockLayerView>?
        private var lock: AppLock?
        private var shows = false

        func update(lock: AppLock, shows: Bool) {
            self.lock = lock
            self.shows = shows
            refresh()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            refresh()
        }

        func removeWindow() {
            lockWindow?.isHidden = true
            lockWindow = nil
            host = nil
        }

        private func refresh() {
            guard let lock, let scene = window?.windowScene ?? lockWindow?.windowScene else { return }
            guard shows else {
                if let lockWindow, !lockWindow.isHidden {
                    lockWindow.isHidden = true
                    // The app's own window takes the keyboard back, for its shortcuts.
                    window?.makeKey()
                }
                return
            }
            let content = LockLayerView(lock: lock)
            if let host {
                host.rootView = content
            } else {
                let host = UIHostingController(rootView: content)
                host.view.backgroundColor = .clear
                let lockWindow = UIWindow(windowScene: scene)
                lockWindow.windowLevel = .alert + 1
                lockWindow.rootViewController = host
                self.host = host
                self.lockWindow = lockWindow
            }
            if lockWindow?.isHidden != false {
                lockWindow?.makeKeyAndVisible()
            }
        }
    }
#endif

/// The lock's window: the lock screen while locked, otherwise the plain cover.
private struct LockLayerView: View {
    let lock: AppLock

    var body: some View {
        Group {
            if lock.isLocked {
                LockScreen(lock: lock)
            } else {
                PrivacyCover()
            }
        }
        .tint(.accentFallback)
    }
}
