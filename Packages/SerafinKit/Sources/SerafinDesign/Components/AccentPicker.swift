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
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: swatch + Spacing.small), spacing: Spacing.small)],
            spacing: Spacing.small
        ) {
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
