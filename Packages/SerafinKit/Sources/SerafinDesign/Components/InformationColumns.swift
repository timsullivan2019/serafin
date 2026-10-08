import SwiftUI

/// A detail screen's facts, laid out the way Apple's TV app does: titled columns of labelled values, side by side
/// when the screen is wide, and one above the other, each its own section, when it isn't.
///
/// Columns without any rows are left out, so a show without file details simply has fewer columns. Each column's
/// title is styled like a row title, since it heads its own section on a narrow screen.
public struct InformationColumns: View {
    /// One titled column, such as "Languages".
    public struct Column: Identifiable, Hashable, Sendable {
        /// The column's heading, already localized.
        public var title: String
        /// The labelled values in the column.
        public var rows: [Row]

        public var id: String { title }

        /// Creates a column.
        public init(title: String, rows: [Row]) {
            self.title = title
            self.rows = rows
        }
    }

    /// One labelled value, such as "Audio: English, French".
    public struct Row: Identifiable, Hashable, Sendable {
        /// What the value is, already localized, such as "Released".
        public var label: String
        /// The value, such as "December 31, 1926".
        public var value: String
        /// The items a listed value is made of, such as languages, or empty for a plain value. A list longer than
        /// ``InformationColumns/shownItems`` shows its first few and how many more there are.
        public var items: [String]

        public var id: String { label }

        /// Creates a row.
        public init(label: String, value: String) {
            self.label = label
            self.value = value
            items = []
        }

        /// Creates a row listing `items`, such as languages.
        ///
        /// - Parameters:
        ///   - label: What the items are, already localized, such as "Subtitles".
        ///   - items: The items, already localized, in order.
        ///   - locale: The locale that joins them into a list.
        public init(label: String, items: [String], locale: Locale = .current) {
            self.label = label
            self.items = items
            value = items.formatted(.list(type: .and, width: .narrow).locale(locale))
        }
    }

    /// How many items of a long list show before "and N more".
    public static let shownItems = 3

    /// The longest list that "and N more" opens in place; a longer one opens in a sheet.
    public static let inlineItems = 10

    /// The first few items of a long list, joined, and how many more there are; nil for a list short enough to show
    /// whole.
    public static func summary(of items: [String], locale: Locale = .current) -> (shown: String, more: Int)? {
        guard items.count > shownItems else { return nil }
        let shown = items.prefix(shownItems).formatted(.list(type: .and, width: .narrow).locale(locale))
        return (shown, items.count - shownItems)
    }

    private let columns: [Column]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Creates the information section.
    ///
    /// - Parameter columns: The columns, in order.
    public init(columns: [Column]) {
        self.columns = columns.filter { !$0.rows.isEmpty }
    }

    /// Whether the columns sit side by side.
    private var isWide: Bool {
        sizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
    }

    public var body: some View {
        if isWide {
            HStack(alignment: .top, spacing: Spacing.xLarge) {
                ForEach(columns) { column in
                    ColumnView(column: column)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                ForEach(columns) { column in
                    ColumnView(column: column)
                }
            }
        }
    }
}

/// One column: its heading, then each value under its label.
private struct ColumnView: View {
    let column: InformationColumns.Column

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(column.title)
                .typography(.title)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(column.rows) { row in
                RowView(row: row)
            }
        }
    }
}

/// One labelled value. A long list, such as fourteen subtitle languages, shows its first three and "and 11 more",
/// which shows the rest in place, or in a sheet when there are more than ``InformationColumns/inlineItems``.
private struct RowView: View {
    let row: InformationColumns.Row
    @State private var isExpanded = false
    @State private var showsAll = false

    var body: some View {
        let content = VStack(alignment: .leading, spacing: 2) {
            Text(row.label)
                .typography(.caption)
                .foregroundStyle(.textSecondary)
            value
                .typography(.body)
                .foregroundStyle(.textPrimary)
        }
        .sheet(isPresented: $showsAll) {
            AllItemsSheet(title: row.label, items: row.items)
        }
        if row.items.isEmpty {
            content.accessibilityElement(children: .combine)
        } else {
            // VoiceOver reads the whole list, so it has nothing to open.
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.label)
                .accessibilityValue(row.value)
        }
    }

    @ViewBuilder private var value: some View {
        if !isExpanded, let summary = InformationColumns.summary(of: row.items) {
            Text(collapsed(summary))
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        guard url == Self.moreLink else { return .discarded }
                        if row.items.count > InformationColumns.inlineItems {
                            showsAll = true
                        } else {
                            withAnimation(.snappy) { isExpanded = true }
                        }
                        return .handled
                    })
        } else {
            Text(row.value)
                .textSelection(.enabled)
        }
    }

    /// The first items, then "and N more" as a link that the row handles itself.
    private func collapsed(_ summary: (shown: String, more: Int)) -> AttributedString {
        var more = AttributedString(
            String(
                localized: "and \(summary.more) more", bundle: .module,
                comment: "Link after the first few items of a list, such as languages, that shows the rest: and 4 more."
            ))
        more.link = Self.moreLink
        return AttributedString(summary.shown + " ") + more
    }

    /// The address "and N more" links to, which never leaves the row.
    private static let moreLink = URL(string: "serafin-information:more")
}

/// Every item of a long list, such as all of a film's subtitle languages, in a sheet.
private struct AllItemsSheet: View {
    let title: String
    let items: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(items, id: \.self) { item in
                Text(item)
            }
            .scrollIndicators(.never)
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .close) { dismiss() }
                        .tint(.primary)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#if DEBUG
    private let sampleColumns: [InformationColumns.Column] = [
        InformationColumns.Column(
            title: "Information",
            rows: [
                InformationColumns.Row(label: "Released", value: "December 31, 1926"),
                InformationColumns.Row(label: "Run Time", value: "1 hr, 19 min"),
                InformationColumns.Row(label: "Rated", value: "NR"),
                InformationColumns.Row(label: "Genres", value: "Comedy, Action"),
            ]
        ),
        InformationColumns.Column(
            title: "Languages",
            rows: [
                InformationColumns.Row(label: "Audio", items: ["English", "French"]),
                InformationColumns.Row(
                    label: "Subtitles", items: ["English", "Spanish", "French", "German", "Italian", "Japanese"]),
            ]
        ),
        InformationColumns.Column(
            title: "Format",
            rows: [
                InformationColumns.Row(label: "Video", value: "1080p"),
                InformationColumns.Row(label: "Audio", value: "AAC · Stereo"),
            ]
        ),
    ]

    private struct InformationSample: View {
        var body: some View {
            ScrollView {
                InformationColumns(columns: sampleColumns)
                    .padding(Spacing.medium)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        InformationSample()
    }

    #Preview("Dark, wide", traits: .landscapeLeft) {
        InformationSample()
            .environment(\.horizontalSizeClass, .regular)
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        InformationSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
