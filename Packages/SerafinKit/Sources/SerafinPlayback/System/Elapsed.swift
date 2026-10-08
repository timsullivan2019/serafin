import Foundation

extension Duration {
    /// The duration in seconds to two decimal places, such as "0.35 s", for the diagnostic logs that time how long
    /// playback takes to start.
    var loggedSeconds: String {
        let (seconds, attoseconds) = components
        return String(format: "%.2f s", Double(seconds) + Double(attoseconds) / 1e18)
    }
}
