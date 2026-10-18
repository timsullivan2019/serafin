import Foundation

/// How far a movie's or an episode's download has got, for the mark beside an episode's number on its card.
public enum DownloadMark: Hashable, Sendable {
    /// Waiting its turn, on its way or being made ready to play, with the share that has arrived while it's on its
    /// way and its size is known.
    case downloading(Double?)
    /// Saved on the device, so it plays with no connection.
    case downloaded

    /// What VoiceOver says for it, such as "Downloaded" or "Downloading, 40%".
    public var accessibilityText: String {
        accessibilityText(locale: .current)
    }

    func accessibilityText(locale: Locale) -> String {
        switch self {
        case .downloaded:
            return String(
                localized: "Downloaded", bundle: .module, locale: locale,
                comment: "Spoken state of a movie or an episode saved on the device.")
        case .downloading(let fraction?):
            let percent = fraction.formatted(.percent.precision(.fractionLength(0)).locale(locale))
            return String(
                localized: "Downloading, \(percent)", bundle: .module, locale: locale,
                comment: "Spoken state of a download on its way. The value is a percentage, such as 40%.")
        case .downloading(nil):
            return String(
                localized: "Downloading", bundle: .module, locale: locale,
                comment: "Spoken state of a download on its way or waiting, when how much has arrived isn't known.")
        }
    }
}
