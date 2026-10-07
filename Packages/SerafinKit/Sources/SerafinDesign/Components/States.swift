import SwiftUI

/// A button shown under an empty or error state.
public struct StateAction {
    /// The button's title, already localized.
    public var title: String
    /// Called when the button is tapped.
    public var perform: () -> Void

    /// Creates a state action.
    ///
    /// - Parameters:
    ///   - title: The button's title, already localized.
    ///   - perform: Called when the button is tapped.
    public init(_ title: String, perform: @escaping () -> Void) {
        self.title = title
        self.perform = perform
    }
}

/// What a screen shows when there is nothing in it yet, such as an empty library or no search results.
public struct EmptyState: View {
    private let title: String
    private let message: String?
    private let systemImage: String
    private let action: StateAction?
    @Environment(\.accent) private var accent

    /// Creates an empty state.
    ///
    /// - Parameters:
    ///   - title: A short headline, already localized.
    ///   - message: An optional line saying why it is empty or what to do.
    ///   - systemImage: An SF Symbol that fits the content, such as "film" or "magnifyingglass".
    ///   - action: An optional button, such as one that clears filters.
    public init(_ title: String, message: String? = nil, systemImage: String, action: StateAction? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let action {
                Button(action.title, action: action.perform)
                    .buttonStyle(.bordered)
                    .tint(accent)
            }
        }
    }
}

/// What a screen shows when loading fails, with a way to try again.
public struct ErrorState: View {
    private let title: String
    private let message: String?
    private let systemImage: String
    private let retry: (() -> Void)?
    @Environment(\.accent) private var accent

    /// Creates an error state.
    ///
    /// - Parameters:
    ///   - title: A short headline, already localized, such as "Can't Reach Your Server".
    ///   - message: A plain-language explanation. Never a raw system error.
    ///   - systemImage: An SF Symbol for the kind of failure.
    ///   - retry: Called by the Try Again button. Pass nil to hide the button.
    public init(
        _ title: String,
        message: String? = nil,
        systemImage: String = "exclamationmark.triangle",
        retry: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let retry {
                Button(
                    String(localized: "Try Again", bundle: .module, comment: "Button that retries a failed load."),
                    action: retry
                )
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
    }
}

/// What a screen shows while it loads.
///
/// The spinner waits a moment before fading in, so fast loads never flash it.
public struct LoadingState: View {
    private let message: String?
    @State private var isVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates a loading state.
    ///
    /// - Parameter message: An optional line under the spinner, already localized.
    public init(_ message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: Spacing.small) {
            ProgressView()
                .controlSize(.large)
            if let message {
                Text(message)
                    .typography(.body)
                    .foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(Spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(isVisible ? 1 : 0)
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            withAnimation(Motion.animation(.easeIn(duration: 0.25), reduceMotion: reduceMotion)) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            message ?? String(localized: "Loading", bundle: .module, comment: "Spoken while content loads.")
        )
    }
}

#if DEBUG
    private struct StatesSample: View {
        var body: some View {
            ScrollView {
                VStack(spacing: Spacing.xLarge) {
                    EmptyState(
                        "No Unwatched Movies",
                        message: "Everything in this library has been watched. Clear the filter to see it all.",
                        systemImage: "film.stack",
                        action: StateAction("Clear Filter") {}
                    )
                    ErrorState(
                        "Can't Reach Your Server",
                        message: "Check that your Jellyfin server is running and on the same network.",
                        systemImage: "wifi.exclamationmark",
                        retry: {}
                    )
                    LoadingState("Loading your library")
                        .frame(height: 160)
                }
                .padding(.vertical, Spacing.xLarge)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        StatesSample()
    }

    #Preview("Dark") {
        StatesSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        StatesSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
