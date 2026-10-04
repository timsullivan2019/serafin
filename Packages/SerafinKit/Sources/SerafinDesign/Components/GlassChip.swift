import SwiftUI

/// A selectable glass pill for a filter or sort option.
///
/// Unselected chips are clear glass whose label adapts to whatever scrolls behind it. The selected chip takes the
/// screen's tint with a white label. Put neighbouring chips in a ``GlassChipGroup`` so they merge and morph
/// together.
public struct GlassChip: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let tint: Color
    private let action: () -> Void

    /// Creates a chip.
    ///
    /// - Parameters:
    ///   - title: The chip's label, already localized.
    ///   - systemImage: An optional SF Symbol shown before the label.
    ///   - isSelected: Whether the option is active.
    ///   - tint: The glass tint when selected.
    ///   - action: Called when the chip is tapped.
    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        tint: Color = .accentFallback,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxSmall + 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                }
                Text(title)
            }
            .typography(.cardTitle)
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.xSmall + 2)
            .frame(minHeight: 44)
            .glassEffect(isSelected ? .regular.tint(tint).interactive() : .regular.interactive(), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .serafinAnimation(value: isSelected)
    }
}

/// Chips laid out in a row inside one glass container, so that neighbours merge and morph together.
public struct GlassChipGroup<Content: View>: View {
    private let content: Content

    /// Creates a chip group.
    ///
    /// - Parameter content: The chips.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        GlassEffectContainer(spacing: Spacing.xSmall) {
            HStack(spacing: Spacing.xSmall) {
                content
            }
        }
    }
}

#if DEBUG
    private struct GlassChipSample: View {
        @State private var sort = "Name"
        @State private var unplayedOnly = true
        private let sorts = ["Name", "Date Added", "Year", "Rating"]

        var body: some View {
            ZStack(alignment: .top) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Spacing.small)], spacing: Spacing.small)
                {
                    ForEach(MockMedia.movies) { card in
                        PosterCard(card: card, artwork: MockMedia.posterImage(for: card))
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.top, 72)
                ScrollView(.horizontal) {
                    GlassChipGroup {
                        GlassChip("Unplayed", systemImage: "circle.dashed", isSelected: unplayedOnly) {
                            unplayedOnly.toggle()
                        }
                        ForEach(sorts, id: \.self) { option in
                            GlassChip(option, isSelected: sort == option) { sort = option }
                        }
                    }
                    .padding(.horizontal, Spacing.medium)
                    .padding(.vertical, Spacing.xSmall)
                }
                .scrollIndicators(.hidden)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        ScrollView { GlassChipSample() }
    }

    #Preview("Dark") {
        ScrollView { GlassChipSample() }
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        ScrollView { GlassChipSample() }
            .dynamicTypeSize(.accessibility5)
    }
#endif
