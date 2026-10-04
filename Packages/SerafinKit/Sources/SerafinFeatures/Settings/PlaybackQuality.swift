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
