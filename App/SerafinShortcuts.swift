import AppIntents
import SerafinFeatures

/// Includes the intents SerafinFeatures defines in the app's App Intents metadata.
struct SerafinAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [SerafinIntents.self] }
}

/// What Siri understands for Serafin without any setup, and the shortcuts Serafin offers in the Shortcuts app and
/// Spotlight.
struct SerafinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: [
                "Continue watching in \(.applicationName)",
                "Continue watching on \(.applicationName)",
                "Keep watching in \(.applicationName)",
                "Resume watching in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource(
                "Continue Watching",
                comment: "Shortcuts' name for the shortcut that plays the latest started movie or episode."),
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PlayMediaIntent(),
            phrases: [
                "Play \(\.$item) in \(.applicationName)",
                "Play \(\.$item) on \(.applicationName)",
                "Watch \(\.$item) in \(.applicationName)",
                "Watch \(\.$item) on \(.applicationName)",
                "Play something in \(.applicationName)",
                "Watch something in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource(
                "Play", comment: "Shortcuts' name for the shortcut that plays a movie, show or episode."),
            systemImageName: "play"
        )
        AppShortcut(
            intent: SearchLibraryIntent(),
            phrases: [
                "Search \(.applicationName)",
                "Search in \(.applicationName)",
                "Find something in \(.applicationName)",
            ],
            shortTitle: LocalizedStringResource(
                "Search", comment: "Shortcuts' name for the shortcut that searches the library."),
            systemImageName: "magnifyingglass"
        )
    }

    static var shortcutTileColor: ShortcutTileColor { .purple }
}
