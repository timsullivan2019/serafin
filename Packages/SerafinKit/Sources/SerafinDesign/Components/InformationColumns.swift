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

        public var id: String { label }

        /// Creates a row.
        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .typography(.caption)
                        .foregroundStyle(.textSecondary)
                    Text(row.value)
                        .typography(.body)
                        .foregroundStyle(.textPrimary)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
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
                InformationColumns.Row(label: "Audio", value: "English, French"),
                InformationColumns.Row(label: "Subtitles", value: "English, Spanish"),
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
