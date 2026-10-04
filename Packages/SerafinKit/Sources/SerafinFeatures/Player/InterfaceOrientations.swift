#if os(iOS)
    import SerafinCore
    import UIKit
    import os

    /// Which ways Serafin's interface may turn. The app delegate hands ``supported`` to UIKit.
    ///
    /// iPad turns every way. iPhone stays upright, except that the player turns it to landscape while it shows.
    @MainActor public enum InterfaceOrientations {
        private static let logger = Logger(serafinCategory: "orientation")
        private static var isPlayerShowing = false

        /// The orientations the interface may use now.
        public static var supported: UIInterfaceOrientationMask {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
            return isPlayerShowing ? .landscape : .portrait
        }

        /// Turns iPhone to landscape for the player.
        static func playerAppeared() {
            isPlayerShowing = true
            update()
        }

        /// Turns iPhone back upright once the player closes.
        static func playerDisappeared() {
            isPlayerShowing = false
            update()
        }

        /// Turns iPhone back upright before the player closes, so the player shrinks away in the same orientation as
        /// the screen behind it. Returns whether the interface had to turn.
        static func playerWillClose() -> Bool {
            let turns = isPlayerShowing && UIDevice.current.userInterfaceIdiom == .phone
            playerDisappeared()
            return turns
        }

        private static func update() {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return }
            let mask = supported
            for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                var controller = scene.keyWindow?.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                    // UIKit turns the interface anyway once the presented player allows only landscape.
                    logger.debug("Could not turn the interface: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
#endif
