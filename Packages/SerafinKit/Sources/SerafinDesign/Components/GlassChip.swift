import SwiftUI

/// A selectable glass pill for a filter or sort option.
///
/// Unselected chips are clear glass whose label adapts to whatever scrolls behind it. The selected chip takes the
/// screen's tint with a white label. Put neighbouring chips in a ``GlassChipGroup`` so they merge and morph
/// together: when a chip grows or shrinks, as when a sort gains its direction arrow, its neighbours' glass flows
/// with it. Make selection changes inside an animation, such as `withAnimation`, so the whole row moves together.
public struct GlassChip: View {
    private let title: String
    private let systemImage: String?
    private let isSelected: Bool
    private let tint: Color?
    private let action: () -> Void
    @Environment(\.glassChipNamespace) private var namespace
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
            .foregroundStyle(isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.xSmall + 2)
            .frame(minHeight: 44)
            .glassEffect(
                isSelected ? .regular.tint(tint ?? accent).interactive() : .regular.interactive(), in: .capsule
            )
            .modifier(ChipGlassID(id: title, namespace: namespace))
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .serafinAnimation(value: isSelected)
    }
}

/// Chips laid out in a row inside one glass container, so that neighbours merge and morph together.
///
/// Keep menus out of the group: a `Menu` inside a glass container loses its own open and close morph.
public struct GlassChipGroup<Content: View>: View {
    private let content: Content
    @Namespace private var namespace

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
        .environment(\.glassChipNamespace, namespace)
    }
}

extension EnvironmentValues {
    /// The namespace of the ``GlassChipGroup`` a chip is in, which identifies its glass for morphing.
    @Entry var glassChipNamespace: Namespace.ID?
}

/// Identifies a chip's glass within its group, so the group morphs it rather than redrawing it.
private struct ChipGlassID: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.glassEffectID(id, in: namespace)
        } else {
            content
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
