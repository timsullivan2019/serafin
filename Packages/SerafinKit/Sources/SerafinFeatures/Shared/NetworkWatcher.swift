import Network
import Observation

/// Watches the device's network: whether it's connected at all, through what, and whether the connection costs money
/// by the byte.
@Observable @MainActor final class NetworkWatcher {
    /// What the device is connected through. It changes when the device joins or leaves a network, such as Wi-Fi at
    /// home, which may bring a server back within reach.
    struct Connection: Equatable {
        /// Whether the device can send anything at all.
        var isOnline: Bool
        /// The kinds of network it can send on, such as Wi-Fi and cellular.
        var interfaces: Set<NWInterface.InterfaceType>
    }

    /// The watcher the app shares, started when first used.
    static let shared = NetworkWatcher()

    /// What the device is connected through. Until the first answer from the system, it reads as online through
    /// nothing in particular, so nothing reports the device offline before knowing.
    private(set) var connection = Connection(isOnline: true, interfaces: [])

    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connection = Connection(
                isOnline: path.status == .satisfied, interfaces: Set(path.availableInterfaces.map(\.type)))
            MainActor.assumeIsolated {
                if self?.connection != connection {
                    self?.connection = connection
                }
            }
        }
        // Updates are rare, so they arrive on the main queue, where screens read them.
        monitor.start(queue: .main)
    }

    /// Whether the current connection costs money by the byte, as cellular and personal hotspots do.
    var isExpensive: Bool {
        monitor.currentPath.isExpensive
    }
}
