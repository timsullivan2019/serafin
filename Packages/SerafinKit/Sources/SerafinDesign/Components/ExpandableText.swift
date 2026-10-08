import SwiftUI

/// A description kept to a few lines, with an inline More at the end of the last one that shows the rest in place, as
/// the App Store and the TV app do. Text short enough to fit shows whole, with no More.
///
/// VoiceOver reads the whole text either way.
public struct ExpandableText: View {
    private let text: String
    private let lineLimit: Int
    @State private var isExpanded = false
    @State private var isTruncated = false

    /// Creates the text.
    ///
    /// - Parameters:
    ///   - text: The text, already localized or from the server.
    ///   - lineLimit: How many lines show until More is tapped.
    public init(_ text: String, lineLimit: Int = 3) {
        self.text = text
        self.lineLimit = lineLimit
    }

    public var body: some View {
        Text(text)
            .lineLimit(isExpanded ? nil : lineLimit)
            .background {
                // Whether the whole text fits in the lines shown: the first view that fits is the whole text, or
                // nothing when it's too tall.
                ViewThatFits(in: .vertical) {
                    Text(text)
                        .hidden()
                        .onAppear { isTruncated = false }
                    Color.clear
                        .onAppear { isTruncated = true }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isTruncated, !isExpanded {
                    Button {
                        withAnimation(.snappy) { isExpanded = true }
                    } label: {
                        Text(String(localized: "More", bundle: .module, comment: "Shows the rest of a description."))
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                            .padding(.leading, Spacing.xLarge)
                            // The last line fades out under the button rather than running behind it.
                            .background {
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.background.opacity(0), location: 0),
                                        .init(color: Color.background, location: 0.45),
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        String(
                            localized: "Shows the whole description", bundle: .module,
                            comment: "Hint on the More button at the end of a shortened description.")
                    )
                }
            }
    }
}

#if DEBUG
    private struct ExpandableTextSample: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    ExpandableText(
                        "The consulting detective of Baker Street and his friend Dr Watson take on London's strangest "
                            + "cases: a king's stolen photograph, a league of red-headed men, five orange pips and a "
                            + "beggar who is not what he seems. Each one begins with a visitor on the stairs, and "
                            + "ends with Holmes explaining what Watson saw and did not observe."
                    )
                    ExpandableText(
                        "A stubborn llama in Patagonia keeps finding new obstacles between him and the grass.")
                }
                .typography(.body)
                .foregroundStyle(.textPrimary)
                .padding(Spacing.medium)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        ExpandableTextSample()
    }

    #Preview("Dark") {
        ExpandableTextSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        ExpandableTextSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
