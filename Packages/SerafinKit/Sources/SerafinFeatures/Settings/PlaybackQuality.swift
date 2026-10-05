import Foundation

/// The most bandwidth a stream may use, set in Settings for each server, separately for Wi-Fi and cellular.
enum PlaybackQuality: Int, CaseIterable, Identifiable {
    case maximum = 0
    case mbps40 = 40_000_000
    case mbps20 = 20_000_000
    case mbps12 = 12_000_000
    case mbps8 = 8_000_000
    case mbps4 = 4_000_000
    case mbps2 = 2_000_000

    /// Where the Wi-Fi cap for every server was saved before each server had its own. It still stands for a server
    /// without one.
    static let wifiKey = "app.getserafin.serafin.playback.maxBitrate.wifi"
    /// Where the cellular cap for every server was saved before each server had its own.
    static let cellularKey = "app.getserafin.serafin.playback.maxBitrate.cellular"
    /// The Wi-Fi cap until the user picks one.
    static let wifiDefault = PlaybackQuality.maximum
    /// The cellular cap until the user picks one.
    static let cellularDefault = PlaybackQuality.mbps8

    /// Where a server's cap for Wi-Fi or cellular is saved.
    static func key(onCellular: Bool, server serverID: String) -> String {
        "\(onCellular ? cellularKey : wifiKey).\(serverID)"
    }

    /// The cap for streaming from a server over Wi-Fi or cellular: the one picked for that server, otherwise the one
    /// picked before each server had its own, otherwise the default.
    static func saved(onCellular: Bool, server serverID: String?, in defaults: UserDefaults) -> PlaybackQuality {
        func stored(_ key: String) -> PlaybackQuality? {
            guard defaults.object(forKey: key) != nil else { return nil }
            return PlaybackQuality(rawValue: defaults.integer(forKey: key))
        }
        if let serverID, let quality = stored(key(onCellular: onCellular, server: serverID)) {
            return quality
        }
        return stored(onCellular ? cellularKey : wifiKey) ?? (onCellular ? cellularDefault : wifiDefault)
    }

    /// Forgets a removed server's caps.
    static func forget(server serverID: String, in defaults: UserDefaults) {
        for onCellular in [false, true] {
            defaults.removeObject(forKey: key(onCellular: onCellular, server: serverID))
        }
    }

    var id: Int { rawValue }

    /// The cap in bits per second, or nil for no cap.
    var bitsPerSecond: Int? {
        self == .maximum ? nil : rawValue
    }

    /// The cap as Settings shows it, such as "8 Mbps".
    var title: String {
        guard let bitsPerSecond else {
            return String(localized: "Maximum", bundle: .module, comment: "Streaming quality: no cap.")
        }
        let megabits = bitsPerSecond / 1_000_000
        return String(
            localized: "\(megabits) Mbps",
            bundle: .module,
            comment: "Streaming quality cap in megabits per second, such as 8 Mbps."
        )
    }
}
