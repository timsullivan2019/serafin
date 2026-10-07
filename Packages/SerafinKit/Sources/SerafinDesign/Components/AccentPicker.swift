import SwiftUI

/// The accent colours as a grid of swatches, for a Settings row. The chosen swatch is ringed and checked.
///
/// VoiceOver reads each swatch by its colour's name, with the chosen one marked selected.
public struct AccentPicker: View {
    @Binding private var selection: Accent
    @ScaledMetric(relativeTo: .body) private var swatch = 32.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Creates the picker.
    ///
    /// - Parameter selection: The chosen colour.
    public init(selection: Binding<Accent>) {
        _selection = selection
    }

    public var body: some View {
        SwatchGrid(minimumWidth: swatch + Spacing.small, spacing: Spacing.small) {
            ForEach(Accent.allCases) { accent in
                Button {
                    withAnimation(Motion.animation(reduceMotion: reduceMotion)) { selection = accent }
                } label: {
                    AccentSwatch(color: accent.color, isSelected: accent == selection, size: swatch)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accent.name)
                .accessibilityAddTraits(accent == selection ? .isSelected : [])
                .help(accent.name)
            }
        }
        .padding(.vertical, Spacing.xSmall)
    }
}

/// Equal columns, as many as fit at `minimumWidth`, each subview centred in its cell.
///
/// Not a `LazyVGrid`: inside a list row a lazy grid can pile its cells on top of each other when the text size
/// changes, and seventeen swatches don't need laziness.
private struct SwatchGrid: Layout {
    let minimumWidth: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? minimumWidth * 6
        let grid = metrics(width: width, subviews: subviews)
        return CGSize(width: width, height: grid.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let grid = metrics(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let column = index % grid.columns
            let row = index / grid.columns
            let center = CGPoint(
                x: bounds.minX + CGFloat(column) * (grid.cellWidth + spacing) + grid.cellWidth / 2,
                y: bounds.minY + CGFloat(row) * (grid.rowHeight + spacing) + grid.rowHeight / 2
            )
            subview.place(
                at: center, anchor: .center, proposal: ProposedViewSize(width: grid.cellWidth, height: grid.rowHeight))
        }
    }

    private func metrics(width: CGFloat, subviews: Subviews)
        -> (columns: Int, cellWidth: CGFloat, rowHeight: CGFloat, height: CGFloat)
    {
        let columns = max(1, Int((width + spacing) / (minimumWidth + spacing)))
        let cellWidth = max(0, (width - spacing * CGFloat(columns - 1)) / CGFloat(columns))
        let rowHeight =
            subviews.map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }.max() ?? 0
        let rows = (subviews.count + columns - 1) / columns
        let height = rows == 0 ? 0 : CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing
        return (columns, cellWidth, rowHeight, height)
    }
}

/// One colour's circle, with a ring and a check when it's chosen.
private struct AccentSwatch: View {
    let color: Color
    let isSelected: Bool
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .padding(4)
            .overlay {
                Circle()
                    .strokeBorder(color, lineWidth: 2.5)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.circle)
    }
}

#if DEBUG
    private struct AccentPickerSample: View {
        @State private var accent = Accent.orange

        var body: some View {
            Form {
                Section {
                    LabeledContent {
                        Text(accent.name)
                    } label: {
                        Text(verbatim: "Accent Colour")
                    }
                    AccentPicker(selection: $accent)
                }
                Section {
                    Toggle(isOn: .constant(true)) { Text(verbatim: "A toggle") }
                    Button {
                    } label: {
                        Text(verbatim: "A link")
                    }
                }
            }
            .tint(accent.color)
        }
    }

    #Preview("Light") {
        AccentPickerSample()
    }

    #Preview("Dark") {
        AccentPickerSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        AccentPickerSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
