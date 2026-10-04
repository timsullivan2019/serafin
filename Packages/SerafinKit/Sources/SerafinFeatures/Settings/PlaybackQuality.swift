import Foundation

/// The most bandwidth a stream may use, set separately for Wi-Fi and cellular in Settings.
enum PlaybackQuality: Int, CaseIterable, Identifiable {
    case maximum = 0
    case mbps40 = 40_000_000
    case mbps20 = 20_000_000
    case mbps12 = 12_000_000
    case mbps8 = 8_000_000
    case mbps4 = 4_000_000
    case mbps2 = 2_000_000

    /// Where the Wi-Fi cap is saved.
    static let wifiKey = "app.getserafin.serafin.playback.maxBitrate.wifi"
    /// Where the cellular cap is saved.
    static let cellularKey = "app.getserafin.serafin.playback.maxBitrate.cellular"
    /// The Wi-Fi cap until the user picks one.
    static let wifiDefault = PlaybackQuality.maximum
    /// The cellular cap until the user picks one.
    static let cellularDefault = PlaybackQuality.mbps8

    /// The cap the user picked in Settings for the network the device is on, or the default.
    static func saved(onCellular: Bool, in defaults: UserDefaults) -> PlaybackQuality {
        let fallback = onCellular ? cellularDefault : wifiDefault
        let key = onCellular ? cellularKey : wifiKey
        guard defaults.object(forKey: key) != nil else { return fallback }
        return PlaybackQuality(rawValue: defaults.integer(forKey: key)) ?? fallback
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
