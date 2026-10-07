import SwiftUI

/// A notice above content that's still worth showing while something is wrong, such as Home showing the rows it last
/// had while the server can't be reached.
///
/// It sits in the content and scrolls with it, so it's a plain panel rather than glass. The button sits beside the
/// text where it fits, and under it where it doesn't. At accessibility text sizes the symbol moves above the text,
/// so the text has the banner's whole width.
public struct NoticeBanner: View {
    private let title: String
    private let message: String?
    private let systemImage: String
    private let action: StateAction?
    private let isBusy: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates a notice banner.
    ///
    /// - Parameters:
    ///   - title: A short headline, already localized, such as "You're Offline".
    ///   - message: An optional line under it, such as when the content is from.
    ///   - systemImage: An SF Symbol for the kind of problem.
    ///   - action: An optional button, such as Try Again.
    ///   - isBusy: Whether the button's work is under way, which shows a spinner in it and turns it off.
    public init(
        _ title: String,
        message: String? = nil,
        systemImage: String,
        action: StateAction? = nil,
        isBusy: Bool = false
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.action = action
        self.isBusy = isBusy
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.small) {
                text
                Spacer(minLength: 0)
                button
            }
            VStack(alignment: .leading, spacing: Spacing.small) {
                text
                button
            }
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surface, in: .rounded(.medium))
    }

    private var text: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xSmall))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Spacing.small))
        return layout {
            Image(systemName: systemImage)
                .typography(.headline)
                .foregroundStyle(.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                    .typography(.headline)
                    .foregroundStyle(.textPrimary)
                if let message {
                    Text(message)
                        .typography(.body)
                        .foregroundStyle(.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var button: some View {
        if let action {
            Button(action: action.perform) {
                // The title keeps the button's size while the spinner shows.
                Text(action.title)
                    .opacity(isBusy ? 0 : 1)
                    .overlay {
                        if isBusy {
                            ProgressView()
                        }
                    }
            }
            .buttonStyle(.bordered)
            .tint(.accentFallback)
            .disabled(isBusy)
            .accessibilityLabel(action.title)
        }
    }
}

#if DEBUG
    private struct NoticeBannerSample: View {
        var body: some View {
            ScrollView {
                VStack(spacing: Spacing.medium) {
                    NoticeBanner(
                        "You're Offline",
                        message: "Last updated 9:41 AM",
                        systemImage: "wifi.slash",
                        action: StateAction("Try Again") {}
                    )
                    NoticeBanner(
                        "Can't Reach the Server",
                        message: "Last updated Oct 3, 9:41 PM",
                        systemImage: "wifi.exclamationmark",
                        action: StateAction("Try Again") {},
                        isBusy: true
                    )
                    NoticeBanner(
                        "Signed Out",
                        message: "Last updated 9:41 AM",
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        action: StateAction("Sign In Again") {}
                    )
                    NoticeBanner("Showing What's Saved", systemImage: "externaldrive")
                }
                .padding(Spacing.medium)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        NoticeBannerSample()
    }

    #Preview("Dark") {
        NoticeBannerSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        NoticeBannerSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
