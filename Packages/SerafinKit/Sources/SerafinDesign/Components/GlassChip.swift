import SwiftUI

/// A selectable glass pill for a filter.
///
/// Unselected chips are the system's clear glass button, whose label adapts to whatever scrolls behind it. The
/// selected chip is the system's prominent glass, tinted with the screen's tint, with a white label: tinted glass
/// that still catches the light, not a flat fill. Put neighbouring chips in a ``GlassChipGroup`` so their glass
/// merges. Make selection changes inside an animation, such as `withAnimation`, so the whole row moves together.
public struct GlassChip: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let tint: Color?
    private let action: () -> Void
    @Environment(\.accent) private var accent

    /// Creates a chip.
    ///
    /// - Parameters:
    ///   - title: The chip's label, already localized.
    ///   - systemImage: An optional SF Symbol shown before the label.
    ///   - isSelected: Whether the option is active.
    ///   - tint: The glass tint when selected, or nil for the accent colour chosen in Settings.
    ///   - action: Called when the chip is tapped.
    public init(
        _ title: String,
        systemImage: String? = nil,
        isSelected: Bool,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        // The system's own glass buttons, as the menu chips beside these use.
        if isSelected {
            button
                .buttonStyle(.glassProminent)
                .tint(tint ?? accent)
        } else {
            // The glass style colours its label with the tint, so a plain label needs a plain tint.
            button
                .buttonStyle(.glass)
                .tint(.primary)
        }
    }

    private var button: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxSmall + 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .contentTransition(.symbolEffect(.replace))
                }
                Text(title)
            }
            .typography(.cardTitle)
            .frame(minHeight: 32)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .serafinAnimation(value: isSelected)
    }
}

/// Chips laid out in a row inside one glass container, so that neighbours merge and morph together.
///
/// Keep menus out of the group: a `Menu` inside a glass container loses its own open and close morph.
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
                        GlassChip("Unwatched", systemImage: "circle.dashed", isSelected: unplayedOnly) {
                            withAnimation(.serafinSnappy) { unplayedOnly.toggle() }
                        }
                        ForEach(sorts, id: \.self) { option in
                            GlassChip(
                                option, systemImage: sort == option ? "arrow.up" : nil, isSelected: sort == option
                            ) {
                                withAnimation(.serafinSnappy) { sort = option }
                            }
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
