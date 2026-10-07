import os

/// Marks how long Serafin takes from starting to showing something to use, as an interval in Instruments' Points of
/// Interest: Home with its rows, or the welcome screen when no one is signed in. It carries no data about the user.
@MainActor public enum LaunchSignpost {
    private static let signposter = OSSignposter(subsystem: Logger.serafinSubsystem, category: .pointsOfInterest)
    private static var interval: OSSignpostIntervalState?

    /// Starts the interval. The app calls this as it starts.
    public static func begin() {
        guard interval == nil else { return }
        interval = signposter.beginInterval("Launch")
    }

    /// Ends the interval, the first time something usable shows. Later calls do nothing.
    ///
    /// - Parameter screen: What showed, such as "Home".
    static func end(showing screen: StaticString) {
        guard let state = interval else { return }
        signposter.endInterval("Launch", state, "\(screen)")
        interval = nil
    }
}
