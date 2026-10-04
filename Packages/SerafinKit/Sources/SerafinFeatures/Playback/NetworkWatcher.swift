import Network

/// Watches the device's network, so playback can use the cellular streaming cap on cellular and personal hotspots.
@MainActor final class NetworkWatcher {
    /// The watcher the app shares, started when first used.
    static let shared = NetworkWatcher()

    private let monitor = NWPathMonitor()

    private init() {
        monitor.start(queue: DispatchQueue(label: "app.getserafin.serafin.network"))
    }

    /// Whether the current connection costs money by the byte, as cellular and personal hotspots do.
    var isExpensive: Bool {
        monitor.currentPath.isExpensive
    }
}
