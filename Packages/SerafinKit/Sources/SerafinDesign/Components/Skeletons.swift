import SwiftUI

/// What a screen shows while its cards load: plain shapes where the cards will be, so nothing jumps when they
/// arrive.
///
/// The shapes are the cards' own sizes, from the same rows and grids, and their text lines take the real type
/// styles, so they match at every Dynamic Type size. They pulse gently, or hold still under Reduce Motion. VoiceOver
/// reads the whole skeleton as one "Loading" element.
public struct Skeleton: View {
    /// The screen the skeleton stands in for.
    public enum Layout: Sendable {
        /// Home: the hero, then a row of thumbnails and rows of posters rising into its fade.
        case rows
        /// A library: a grid of posters at least `columnMinimum` points wide.
        case posterGrid(columnMinimum: CGFloat)
        /// A season: a grid of thumbnails at least `columnMinimum` points wide.
        case thumbnailGrid(columnMinimum: CGFloat)
        /// A detail screen: the hero, the overview and a row of posters.
        case detail
    }

    private let layout: Layout

    /// Creates a skeleton.
    ///
    /// - Parameter layout: The screen it stands in for.
    public init(_ layout: Layout) {
        self.layout = layout
    }

    public var body: some View {
        content
            .scrollDisabled(true)
            .modifier(SkeletonPulse())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(localized: "Loading", bundle: .module, comment: "Spoken while content loads.")
            )
    }

    @ViewBuilder private var content: some View {
        switch layout {
        case .rows:
            SkeletonHome()
        case .posterGrid(let columnMinimum):
            SkeletonGrid(columnMinimum: columnMinimum, aspectRatio: 2 / 3, spacing: Spacing.small)
        case .thumbnailGrid(let columnMinimum):
            SkeletonGrid(columnMinimum: columnMinimum, aspectRatio: 16 / 9, spacing: Spacing.medium)
        case .detail:
            SkeletonDetail()
        }
    }
}

/// A card-shaped placeholder: the artwork's rounded rectangle, then lines where the title and caption go.
///
/// Long grids show it in the places whose cards haven't loaded yet.
public struct SkeletonCard: View {
    private let aspectRatio: CGFloat

    /// Creates a placeholder card.
    ///
    /// - Parameter aspectRatio: The artwork's width over its height, such as 2:3 for a poster.
    public init(aspectRatio: CGFloat) {
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Rectangle()
                .fill(.surface)
                .aspectRatio(aspectRatio, contentMode: .fit)
                .clipShape(.rounded(.small))
            VStack(alignment: .leading, spacing: 2) {
                SkeletonText("Placeholder title", style: .cardTitle)
                SkeletonText("Year", style: .caption)
            }
        }
    }
}

/// A line of placeholder text in a real type style, so it is as tall as the text it stands in for.
struct SkeletonText: View {
    private let sample: String
    private let style: Typography

    init(_ sample: String, style: Typography) {
        self.sample = sample
        self.style = style
    }

    var body: some View {
        Text(verbatim: sample)
            .typography(style)
            .foregroundStyle(.textSecondary)
            .lineLimit(1)
            .redacted(reason: .placeholder)
    }
}

/// A titled row of placeholder cards, laid out exactly like a ``MediaRow`` of the same style.
struct SkeletonRow: View {
    let style: MediaRowStyle
    /// Whether the title has a chevron, as the rows it stands in for do.
    var hasChevron = false

    var body: some View {
        MediaRow("Placeholder row title", style: style, items: SkeletonSlot.row, seeAll: hasChevron ? {} : nil) { _ in
            SkeletonCard(aspectRatio: style == .landscape ? 16 / 9 : 2 / 3)
        }
        .redacted(reason: .placeholder)
        .modifier(SkeletonShade())
        .allowsHitTesting(false)
    }
}

/// A grid of placeholder cards, laid out like a library or season grid.
struct SkeletonGrid: View {
    let columnMinimum: CGFloat
    let aspectRatio: CGFloat
    let spacing: CGFloat

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: columnMinimum), spacing: spacing, alignment: .top)],
                spacing: Spacing.large
            ) {
                ForEach(SkeletonSlot.grid) { _ in
                    SkeletonCard(aspectRatio: aspectRatio)
                }
            }
            .modifier(SkeletonShade())
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
        }
    }
}

/// Home's skeleton: a plain hero as tall as the real one, with a title, a line and a Play button, then rows rising
/// into its fade.
struct SkeletonHome: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle()
                    .fill(.surface)
                    .containerRelativeFrame(.vertical) { height, _ in
                        height
                            * HomeHeroLayout.heightFraction(
                                isRegularWidth: sizeClass == .regular, dynamicTypeSize: dynamicTypeSize)
                    }
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: Color.background.opacity(0), location: 0.45),
                                .init(color: Color.background, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            SkeletonText("Placeholder", style: .largeTitle)
                            SkeletonText("1927 · 1 hr 32 min · NR", style: .cardTitle)
                            Capsule()
                                .fill(.textSecondary.opacity(0.25))
                                .frame(width: 180, height: HomeHeroLayout.actionHeight)
                                .padding(.top, Spacing.xSmall)
                        }
                        .padding(.horizontal, Spacing.medium)
                        .padding(.bottom, HomeHeroLayout.contentBottomPadding)
                    }
                    .modifier(SkeletonShade())
                VStack(alignment: .leading, spacing: Spacing.large) {
                    SkeletonRow(style: .landscape, hasChevron: true)
                    SkeletonRow(style: .posters, hasChevron: true)
                    SkeletonRow(style: .posters, hasChevron: true)
                }
                .padding(.top, -HomeHeroLayout.rowOverlap)
                .padding(.bottom, Spacing.medium)
            }
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// A detail screen's skeleton: a plain hero with a title and play pill, the overview's lines, then a row.
struct SkeletonDetail: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xLarge) {
                Rectangle()
                    .fill(.surface)
                    .containerRelativeFrame(.vertical) { height, _ in
                        height
                            * HomeHeroLayout.heightFraction(
                                isRegularWidth: sizeClass == .regular, dynamicTypeSize: dynamicTypeSize)
                    }
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: Color.background.opacity(0), location: 0.88),
                                .init(color: Color.background, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                    .overlay(alignment: .bottom) {
                        VStack(spacing: Spacing.medium) {
                            SkeletonText("Placeholder", style: .largeTitle)
                            SkeletonText("2024 · 1 hr, 40 min", style: .caption)
                            Capsule()
                                .fill(.textSecondary.opacity(0.25))
                                .frame(width: 150, height: 50)
                        }
                        .padding(.bottom, Spacing.xLarge + Spacing.large)
                    }
                    .modifier(SkeletonShade())
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    SkeletonText("A placeholder line of an overview, as wide as most lines.", style: .body)
                    SkeletonText("A placeholder line of an overview, as wide as most lines.", style: .body)
                    SkeletonText("A shorter placeholder line.", style: .body)
                }
                .padding(.horizontal, Spacing.medium)
                .modifier(SkeletonShade())
                SkeletonRow(style: .posters)
            }
            .padding(.bottom, Spacing.xLarge)
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// One placeholder card's place in a row or grid.
struct SkeletonSlot: Identifiable {
    let id: Int

    /// Enough cards to fill a row on the widest screen.
    static let row = (0..<8).map(SkeletonSlot.init)
    /// Enough cards to fill a grid on the tallest screen.
    static let grid = (0..<24).map(SkeletonSlot.init)
}

/// The skeleton's gentle pulse, held still under Reduce Motion.
///
/// One animator drives every shape through the environment, so the shapes pulse together and nothing else on the
/// screen, such as a large navigation title drawn with the content, dims with them.
private struct SkeletonPulse: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.phaseAnimator([1.0, 0.55]) { view, opacity in
                view.environment(\.skeletonOpacity, opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
        }
    }
}

/// Fades a skeleton shape with the pulse.
private struct SkeletonShade: ViewModifier {
    @Environment(\.skeletonOpacity) private var opacity

    func body(content: Content) -> some View {
        content.opacity(opacity)
    }
}

extension EnvironmentValues {
    /// How opaque skeleton shapes are at this point in the pulse.
    @Entry fileprivate var skeletonOpacity: Double = 1
}

#if DEBUG
    private struct SkeletonSample: View {
        let layout: Skeleton.Layout

        var body: some View {
            NavigationStack {
                Skeleton(layout)
                    .background(Color.background)
                    .navigationTitle(Text(verbatim: "Home"))
            }
        }
    }

    #Preview("Light") {
        SkeletonSample(layout: .rows)
    }

    #Preview("Dark") {
        SkeletonSample(layout: .posterGrid(columnMinimum: 104))
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        SkeletonSample(layout: .detail)
            .dynamicTypeSize(.accessibility5)
    }
#endif
