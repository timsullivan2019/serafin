#if os(iOS)
    import SerafinCore
    import UIKit
    import os

    /// Which ways Serafin's interface may turn. The app delegate hands ``supported`` to UIKit.
    ///
    /// iPad turns every way. iPhone stays upright, except that the player turns with the phone, to either side or
    /// upright, never upside down.
    @MainActor public enum InterfaceOrientations {
        private static let logger = Logger(serafinCategory: "orientation")
        private static var isPlayerShowing = false

        /// The orientations the interface may use now.
        public static var supported: UIInterfaceOrientationMask {
            guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
            return isPlayerShowing ? .allButUpsideDown : .portrait
        }

        /// Lets iPhone turn with the phone while the player shows.
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
            let isSideways = UIApplication.shared.connectedScenes.contains {
                ($0 as? UIWindowScene)?.effectiveGeometry.interfaceOrientation.isLandscape == true
            }
            let turns = isPlayerShowing && UIDevice.current.userInterfaceIdiom == .phone && isSideways
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
                    // UIKit turns the interface anyway once the screen allows only the orientations asked for.
                    logger.debug("Could not turn the interface: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
#endif
