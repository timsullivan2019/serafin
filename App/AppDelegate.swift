import SerafinFeatures
import UIKit

/// Tells UIKit which ways the interface may turn: upright on iPhone except while the player shows, every way on
/// iPad.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        InterfaceOrientations.supported
    }
}
