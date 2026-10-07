import AppIntents

/// Serafin's App Intents: Continue Watching, Play, Search and Open, for Siri, Shortcuts and Spotlight.
///
/// The app target lists this package in its own `AppIntentsPackage`, and calls ``register(session:lock:requests:)``
/// as it starts.
public struct SerafinIntents: AppIntentsPackage {
    /// Hands the intents the app's session, lock and requests. The app calls this as it starts, before any intent
    /// can run.
    @MainActor public static func register(session: AppSession, lock: AppLock, requests: AppRequests) {
        AppDependencyManager.shared.add(dependency: session)
        AppDependencyManager.shared.add(dependency: lock)
        AppDependencyManager.shared.add(dependency: requests)
    }
}

/// Plays what the user was watching last, or the next episode of a show they're part way through.
public struct ContinueWatchingIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "Continue Watching",
        comment: "Started movies and episodes: the Home row, and the shortcut that plays the latest of them."
    )
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Plays the movie or episode you were last watching in Serafin, or the next episode of a show you're watching.",
            comment: "Description of the Continue Watching shortcut."
        )
    )
    /// Starts in the background to find what to play, so Siri can say when there's nothing without opening the app.
    public static let supportedModes: IntentModes = .foreground(.dynamic)

    @Dependency private var session: AppSession
    @Dependency private var requests: AppRequests

    /// Creates the intent.
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult {
        let item = try await IntentLibrary.current(in: session).continueWatching()
        try await continueInForeground(alwaysConfirm: false)
        requests.send(.play(itemID: item.id))
        return .result()
    }
}

/// Plays a movie or episode where the user left off, or a show's next episode.
public struct PlayMediaIntent: AppIntent {
    public static let title = LocalizedStringResource(
        "Play Movie or Show", comment: "Title of the shortcut that plays a title from the library.")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Plays a movie or episode in Serafin from where you left off, or a show from its next episode.",
            comment: "Description of the Play shortcut."
        )
    )
    public static let supportedModes: IntentModes = .foreground(.immediate)

    /// What to play.
    @Parameter(
        title: LocalizedStringResource("Title", comment: "The movie, show or episode a shortcut plays or opens."),
        requestValueDialog: IntentDialog(
            LocalizedStringResource("What do you want to watch?", comment: "Siri's question when Play has no title.")
        )
    )
    public var item: MediaEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Play \(\.$item)")
    }

    @Dependency private var requests: AppRequests

    /// Creates the intent.
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult {
        requests.send(.play(itemID: item.id))
        return .result()
    }
}

/// Shows the search results for a term in Serafin.
public struct SearchLibraryIntent: ShowInAppSearchResultsIntent {
    public static let title = LocalizedStringResource(
        "Search Serafin", comment: "Title of the shortcut that searches the library.")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Searches your movies, shows and episodes in Serafin.", comment: "Description of the Search shortcut.")
    )
    public static let searchScopes: [StringSearchScope] = [.general]
    public static let supportedModes: IntentModes = .foreground(.immediate)

    /// What to search for.
    @Parameter(
        title: LocalizedStringResource("Search For", comment: "What the Search shortcut looks for."),
        requestValueDialog: IntentDialog(
            LocalizedStringResource("What do you want to find?", comment: "Siri's question when Search has no term.")
        )
    )
    public var criteria: StringSearchCriteria

    @Dependency private var requests: AppRequests

    /// Creates the intent.
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult {
        requests.send(.search(criteria.term))
        return .result()
    }
}

/// Opens a movie's, show's or episode's page in Serafin. Spotlight runs it when a result is tapped.
public struct OpenMediaIntent: OpenIntent {
    public static let title = LocalizedStringResource(
        "Open Movie or Show", comment: "Title of the shortcut that opens a title's page.")
    public static let supportedModes: IntentModes = .foreground(.immediate)

    /// What to open.
    @Parameter(
        title: LocalizedStringResource("Title", comment: "The movie, show or episode a shortcut plays or opens."))
    public var target: MediaEntity

    @Dependency private var requests: AppRequests

    /// Creates the intent.
    public init() {}

    @MainActor public func perform() async throws -> some IntentResult {
        requests.send(.show(itemID: target.id))
        return .result()
    }
}
