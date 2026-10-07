import SwiftUI

/// Sizes and identifiers that Home's hero and the screen around it share.
public enum HomeHeroLayout {
    /// The hero's height as a fraction of the screen's, from the top down to the home indicator: 58% in a compact
    /// width, such as iPhone, and 48% in a regular width, such as iPad.
    ///
    /// The screen, rather than the space a scroll view has above the tab bar, so the hero keeps its size when the mini
    /// player comes and goes.
    ///
    /// - Parameter isRegularWidth: Whether the horizontal size class is regular.
    public static func heightFraction(isRegularWidth: Bool) -> CGFloat {
        isRegularWidth ? 0.48 : 0.58
    }

    /// The hero's height as a fraction of the screen's, taller at accessibility text sizes so the larger title and
    /// buttons still sit over the fade.
    ///
    /// - Parameters:
    ///   - isRegularWidth: Whether the horizontal size class is regular.
    ///   - dynamicTypeSize: The text size.
    public static func heightFraction(isRegularWidth: Bool, dynamicTypeSize: DynamicTypeSize) -> CGFloat {
        guard dynamicTypeSize.isAccessibilitySize else { return heightFraction(isRegularWidth: isRegularWidth) }
        return isRegularWidth ? 0.62 : 0.77
    }

    /// How far the first row under the hero rises into its fade, so the page reads as one piece.
    public static let rowOverlap: CGFloat = Spacing.xLarge

    /// How far below the top safe area a hero's text and buttons start to fade, in points. They're gone by the time
    /// they reach it, so nothing sits under the status bar or the navigation bar.
    public static let topFadeDistance: CGFloat = 80

    /// The shortest distance a hero's text or button fades over, for one that rests too near the top for the whole
    /// ``topFadeDistance``, as in a short iPad window.
    static let shortestTopFade: CGFloat = 24

    /// The name of the coordinate space of a hero screen's scrolling content, which tells the hero's text and buttons
    /// where they rest. A screen gives it to its content with `heroScrollContent()`.
    static let scrollContentSpace = "serafin.hero.scroll-content"

    /// How visible a hero's text or button is when its top edge is `top` points from the top of the window.
    ///
    /// It's fully shown at rest and anywhere ``topFadeDistance`` or more below the top safe area, and fades to
    /// nothing as it reaches the safe area. One that rests nearer the top than that, as in a short iPad window,
    /// fades over the room it has, and one that rests under the bars fades over its first few points of travel.
    ///
    /// - Parameters:
    ///   - top: Where the view's top edge is, in the window's coordinates.
    ///   - restingTop: Where the view's top edge is with the page at rest.
    ///   - safeAreaTop: Where the top safe area ends, below the status bar and any navigation bar.
    public static func topFadeOpacity(top: CGFloat, restingTop: CGFloat, safeAreaTop: CGFloat) -> Double {
        let start = min(safeAreaTop + topFadeDistance, restingTop)
        let end = min(safeAreaTop, start - shortestTopFade)
        return Double(min(max((top - end) / (start - end), 0), 1))
    }

    /// Whether a page with a hero at its top has been scrolled at all, so the top edge effect should cover what
    /// passes under the status bar. At rest the artwork runs clear to the top of the screen.
    ///
    /// The page counts as scrolled once it has moved 8 points, and back at rest under 2. The gap means resting near
    /// either never flips back and forth.
    ///
    /// - Parameters:
    ///   - offset: How far the page has scrolled, in points.
    ///   - wasScrolled: The answer last time.
    public static func isScrolled(offset: CGFloat, wasScrolled: Bool) -> Bool {
        wasScrolled ? offset > 2 : offset > 8
    }

    /// The source a featured item's detail screen zooms in from, distinct from the item's cards in the rows below.
    ///
    /// - Parameter id: The featured card's identifier.
    public static func zoomID(for id: String) -> String {
        "home-hero-\(id)"
    }

    /// The source the full-screen player grows out of when a featured item's Play button starts it.
    ///
    /// - Parameter id: The featured card's identifier.
    public static func playZoomID(for id: String) -> String {
        "home-hero-play-\(id)"
    }

    /// The space under the text and buttons: the rows' overlap, then a step.
    static let contentBottomPadding: CGFloat = rowOverlap + Spacing.large
    /// How tall the buttons are, which the page dots line up with.
    static let actionHeight: CGFloat = 50
    /// The width one page dot takes, its tappable area included.
    static let dotSlotWidth: CGFloat = 14

    /// The width the page dots take beside the buttons, with a gap, or nothing for a single page.
    static func indicatorReserve(pageCount: Int) -> CGFloat {
        guard pageCount > 1 else { return 0 }
        return CGFloat(pageCount) * dotSlotWidth + 2 * Spacing.xSmall + Spacing.small
    }
}

/// The top of Home: featured items, a page each, swiped through sideways.
///
/// Each page is full-bleed artwork under the status bar that dissolves into the screen below, with its title, one
/// line of details and a Play button. A small glass capsule of dots in the bottom-trailing corner shows the page,
/// and tapping a dot goes to its page. Pages never advance on their own.
///
/// Put the hero first in a vertical `ScrollView` that ignores the top safe area, inside a tab view marked with
/// `heroScreen()`, and give it ``HeroPage`` views. It is ``HomeHeroLayout/heightFraction(isRegularWidth:)`` of the
/// screen's height. VoiceOver says "Page 2 of
/// 4" when the page changes.
public struct HomeHero<Page: View>: View {
    private let items: [HeroItem]
    @Binding private var selection: String?
    private let page: (HeroItem) -> Page
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.heroSafeAreaTop) private var safeAreaTop

    /// Creates a hero.
    ///
    /// - Parameters:
    ///   - items: The featured items, in order: three to five reads best.
    ///   - selection: The identifier of the page showing, or nil for the first.
    ///   - page: Draws one item's page, typically a ``HeroPage``.
    public init(
        items: [HeroItem],
        selection: Binding<String?>,
        @ViewBuilder page: @escaping (HeroItem) -> Page
    ) {
        self.items = items
        _selection = selection
        self.page = page
    }

    public var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(items) { item in
                    page(item)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $selection)
        .scrollIndicators(.hidden)
        // The artwork stretches upward when Home is pulled down, so the pager clips only at its sides.
        .scrollClipDisabled()
        .mask { Rectangle().padding(.vertical, -2000) }
        .heroFrame()
        .overlay(alignment: .bottomTrailing) {
            if items.count > 1 {
                HeroPageIndicator(count: items.count, current: currentIndex, select: select)
                    .frame(height: HomeHeroLayout.actionHeight)
                    .fadesBeforeTopSafeArea(safeAreaTop)
                    .padding(.trailing, Spacing.medium)
                    .padding(.bottom, HomeHeroLayout.contentBottomPadding)
            }
        }
        .environment(\.heroIndicatorReserve, HomeHeroLayout.indicatorReserve(pageCount: items.count))
        .onChange(of: selection) {
            AccessibilityNotification.PageScrolled(Self.pageDescription(currentIndex, of: items.count)).post()
        }
    }

    private var currentIndex: Int {
        items.firstIndex { $0.id == selection } ?? 0
    }

    private func select(_ index: Int) {
        guard items.indices.contains(index) else { return }
        // Under Reduce Motion the page changes without sliding.
        withAnimation(reduceMotion ? nil : .serafinSnappy) {
            selection = items[index].id
        }
    }

    /// "Page 2 of 4", for the page dots and VoiceOver.
    static func pageDescription(_ index: Int, of count: Int) -> String {
        String(
            localized: "Page \(index + 1) of \(count)",
            bundle: .module,
            comment: "Which featured item on Home is showing, such as Page 2 of 4."
        )
    }
}

/// One featured item's page in ``HomeHero``.
///
/// The backdrop fills the page under the status bar, moving a little slower than the scroll and stretching when
/// Home is pulled down, both still under Reduce Motion. Without a backdrop, the poster stands in, enlarged and
/// blurred. Over the fade in the bottom-leading corner sit the logo or title, a line of details, two lines of the
/// overview (hidden at accessibility text sizes), then a Play button tinted with the artwork's colour and a round
/// button for the detail screen. Under Reduce Transparency the buttons are plain material instead of glass.
///
/// Tapping the artwork opens the detail screen and touching and holding the page opens its context menu. VoiceOver
/// reads the page as one element, such as "Featured: Sherlock Holmes, A Case of Identity, 9 minutes left", with
/// actions to play and to show the details.
public struct HeroPage<Menu: View>: View {
    private let item: HeroItem
    private let backdrop: Image?
    private let backdropIsPoster: Bool
    private let logo: Image?
    private let tint: Color
    private let zoomNamespace: Namespace.ID?
    private let playZoomNamespace: Namespace.ID?
    private let play: () -> Void
    private let showDetails: () -> Void
    private let menu: Menu
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.heroSafeAreaTop) private var safeAreaTop

    /// Creates a page.
    ///
    /// - Parameters:
    ///   - item: The featured item.
    ///   - backdrop: The backdrop, or nil while it loads.
    ///   - backdropIsPoster: Whether `backdrop` is the poster standing in for a missing backdrop, which is drawn
    ///     enlarged and blurred.
    ///   - logo: The title logo, drawn instead of the title when present.
    ///   - tint: The Play button's tint, typically ``ArtworkTint`` of the backdrop.
    ///   - zoomNamespace: The namespace in which the artwork is the source of the detail screen's zoom, keyed by
    ///     ``HomeHeroLayout/zoomID(for:)``. Pass nil for no zoom.
    ///   - playZoomNamespace: The namespace in which the Play button is the source of the player's zoom, keyed by
    ///     ``HomeHeroLayout/playZoomID(for:)``. Pass nil for no zoom.
    ///   - play: Called when Play is tapped.
    ///   - showDetails: Called when the artwork or the info button is tapped.
    ///   - menu: The context menu's items.
    public init(
        item: HeroItem,
        backdrop: Image?,
        backdropIsPoster: Bool = false,
        logo: Image? = nil,
        tint: Color = .accentFallback,
        zoomNamespace: Namespace.ID? = nil,
        playZoomNamespace: Namespace.ID? = nil,
        play: @escaping () -> Void,
        showDetails: @escaping () -> Void,
        @ViewBuilder menu: () -> Menu
    ) {
        self.item = item
        self.backdrop = backdrop
        self.backdropIsPoster = backdropIsPoster
        self.logo = logo
        self.tint = tint
        self.zoomNamespace = zoomNamespace
        self.playZoomNamespace = playZoomNamespace
        self.play = play
        self.showDetails = showDetails
        self.menu = menu()
    }

    public var body: some View {
        HeroPageBackdrop(image: backdrop, isPoster: backdropIsPoster, kind: item.card.kind)
            .modifier(HeroZoomSource(id: HomeHeroLayout.zoomID(for: item.id), namespace: zoomNamespace))
            // Taps and the context menu belong to a clear layer over the artwork. Touching and holding lifts this
            // layer, which iOS hides while the menu shows, so the artwork stays in view behind the menu.
            .overlay {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: showDetails)
                    .cardContextMenu(menu) {
                        HeroPageBackdrop.preview(backdrop, kind: item.card.kind)
                    }
            }
            .overlay(alignment: .bottomLeading) { details }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { showDetails() }
            .accessibilityAction(named: Text(item.playActionName), play)
            .accessibilityAction(named: Text(Self.showDetailsTitle), showDetails)
            // The context menu's items, which VoiceOver can't reach inside the combined element otherwise.
            .accessibilityActions { menu }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            // Each piece fades out on its own as it nears the status bar, so none of it ever sits under the clock.
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                heading
                    .animation(.easeOut(duration: 0.3), value: logo != nil)
                    .fadesBeforeTopSafeArea(safeAreaTop)
                Text(item.metadata(includesSeries: logo != nil))
                    .typography(.cardTitle)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .fadesBeforeTopSafeArea(safeAreaTop)
                if !dynamicTypeSize.isAccessibilitySize, let overview = item.card.overview, !overview.isEmpty {
                    Text(overview)
                        .typography(.body)
                        .foregroundStyle(.textPrimary.opacity(contrast == .increased ? 1 : 0.85))
                        .lineLimit(2)
                        .fadesBeforeTopSafeArea(safeAreaTop)
                }
            }
            // The text is part of the artwork: touches pass through it to the layer under it.
            .allowsHitTesting(false)
            HeroActions(
                item: item,
                tint: tint,
                menu: menu,
                playZoomNamespace: playZoomNamespace,
                play: play,
                showDetails: showDetails
            )
            .fadesBeforeTopSafeArea(safeAreaTop)
            .padding(.top, Spacing.xSmall)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, HomeHeroLayout.contentBottomPadding)
    }

    @ViewBuilder private var heading: some View {
        if let logo {
            logo
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 72, alignment: .bottomLeading)
                .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in width * 0.7 }
                // Logos are drawn for dark backgrounds; a soft shadow keeps a light one readable on a light fade.
                .shadow(color: .black.opacity(colorScheme == .light ? 0.6 : 0.25), radius: 6, y: 1)
                .padding(.bottom, Spacing.xxSmall)
                .transition(.opacity)
        } else {
            Text(item.heading)
                .typography(.largeTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .transition(.opacity)
        }
    }

    static var showDetailsTitle: String {
        String(
            localized: "Show Details", bundle: .module,
            comment: "Button and accessibility action that opens a featured item's detail screen on Home.")
    }
}

/// The Play button and the round info button, glass that merges as one group, or plain material under Reduce
/// Transparency. Touching and holding either lifts just that button with the item's context menu.
private struct HeroActions<Menu: View>: View {
    let item: HeroItem
    let tint: Color
    let menu: Menu
    let playZoomNamespace: Namespace.ID?
    let play: () -> Void
    let showDetails: () -> Void
    @State private var playCount = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.heroIndicatorReserve) private var indicatorReserve
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Side by side when they fit, otherwise one above the other, with the page dots on a line of their
                // own.
                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    ViewThatFits(in: .horizontal) {
                        buttons
                            .fixedSize()
                        GlassEffectContainer(spacing: Spacing.small) {
                            VStack(alignment: .leading, spacing: Spacing.small) {
                                playButton
                                infoButton
                            }
                        }
                        // Play's title wraps rather than running off the screen.
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    dotsLine
                }
            } else {
                // Beside the page dots when there's room, otherwise a line above them.
                ViewThatFits(in: .horizontal) {
                    buttons
                        .fixedSize()
                        .padding(.trailing, indicatorReserve)
                    VStack(alignment: .leading, spacing: Spacing.xSmall) {
                        buttons
                            .fixedSize()
                        dotsLine
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: playCount)
    }

    private var buttons: some View {
        GlassEffectContainer(spacing: Spacing.small) {
            HStack(spacing: Spacing.small) {
                playButton
                infoButton
            }
        }
    }

    /// Room under the buttons for the page dots, which the hero draws.
    private var dotsLine: some View {
        Color.clear
            .frame(height: indicatorReserve > 0 ? HomeHeroLayout.actionHeight : 0)
    }

    @ViewBuilder private var playButton: some View {
        let button = Button {
            playCount += 1
            play()
        } label: {
            // At accessibility sizes the title drops the time left, which VoiceOver still says.
            Label(dynamicTypeSize.isAccessibilitySize ? item.playActionName : item.playTitle, systemImage: "play.fill")
                .typography(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .padding(.horizontal, Spacing.xxSmall)
        }
        .modifier(HeroPlayZoomSource(id: HomeHeroLayout.playZoomID(for: item.id), namespace: playZoomNamespace))
        Group {
            if reduceTransparency {
                button.buttonStyle(HeroMaterialButtonStyle(fill: tint, shape: .capsule))
            } else {
                button.buttonStyle(.glassProminent).tint(tint).controlSize(.large)
            }
        }
        .contextMenu { menu }
    }

    @ViewBuilder private var infoButton: some View {
        let button = Button(action: showDetails) {
            Image(systemName: "info")
                .typography(.headline)
                .frame(width: 22, height: 22)
        }
        .accessibilityLabel(HeroPage<EmptyView>.showDetailsTitle)
        Group {
            if reduceTransparency {
                button.buttonStyle(HeroMaterialButtonStyle(fill: nil, shape: .circle))
            } else {
                // The glass style colours its symbol with the tint, so a plain symbol needs a plain tint.
                button.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large).tint(.primary)
            }
        }
        .contextMenu { menu }
    }
}

/// A plain material button for Reduce Transparency: a solid tint for Play, the regular material for the rest.
private struct HeroMaterialButtonStyle: ButtonStyle {
    enum Shape { case capsule, circle }

    let fill: Color?
    let shape: Shape

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(fill == nil ? Color.textPrimary : .white)
            .padding(shape == .capsule ? Spacing.small : Spacing.xSmall - 1)
            .background {
                switch shape {
                case .capsule:
                    if let fill { Capsule().fill(fill) } else { Capsule().fill(.regularMaterial) }
                case .circle:
                    if let fill { Circle().fill(fill) } else { Circle().fill(.regularMaterial) }
                }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The backdrop: artwork that crossfades in under a faint scrim for the status bar, then a fade into the screen.
private struct HeroPageBackdrop: View {
    let image: Image?
    let isPoster: Bool
    let kind: MediaCard.Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let moves = !reduceMotion
        // The page's frame comes from the clear colour; the artwork filling it spills past its sides.
        Color.clear
            .overlay {
                ZStack {
                    Rectangle().fill(.surface)
                    if let image {
                        artwork(image)
                            .transition(.opacity)
                    }
                    // Stretches with the artwork, so it stays under the status bar when Home is pulled down.
                    statusBarScrim
                }
                .animation(.easeOut(duration: 0.3), value: image != nil)
                // The artwork spills past the page's sides, over the pages beside it, and would take their touches:
                // after swiping back, the next page's artwork lay over this one's info button. The page's own taps
                // belong to the clear layer over it.
                .allowsHitTesting(false)
            }
            .visualEffect { content, proxy in
                let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
                let height = max(proxy.size.height, 1)
                return
                    content
                    // Slower than the scroll going up; stretched to fill the gap when pulled down.
                    .offset(y: moves && minY < 0 ? -minY * 0.3 : 0)
                    .scaleEffect(moves && minY > 0 ? (height + minY) / height : 1, anchor: .bottom)
            }
            // Clipped to the page's sides and bottom, so it never covers the next page while swiping, but open at the
            // top, so the stretch can reach the top of the screen.
            .mask { Rectangle().padding(.top, -2000) }
            .overlay { HeroFade() }
            .accessibilityHidden(true)
    }

    @ViewBuilder private func artwork(_ image: Image) -> some View {
        if isPoster {
            image
                .resizable()
                .scaledToFill()
                .blur(radius: 30, opaque: true)
                .scaleEffect(1.15)
        } else {
            image
                .resizable()
                .scaledToFill()
        }
    }

    /// A faint scrim at the top, so the status bar stays legible over bright artwork.
    private var statusBarScrim: some View {
        LinearGradient(
            stops: [
                .init(color: Color.background.opacity(0.5), location: 0),
                .init(color: Color.background.opacity(0), location: 0.2),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The context menu's preview: the artwork at 16:9.
    static func preview(_ image: Image?, kind: MediaCard.Kind) -> some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let image {
                    image.resizable().scaledToFill()
                } else {
                    ArtworkPlaceholder(kind: kind)
                }
            }
            .clipped()
            .frame(width: 340)
    }
}

/// The artwork frosting from 30% down, behind the text, and fading into the screen from 45% down. The detail screen
/// starts with it when it zooms in from Home's hero, and fades it away, so the two read as one movement.
struct HeroFade: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .mask {
                    LinearGradient(
                        stops: [.init(color: .clear, location: 0.3), .init(color: .black, location: 0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            LinearGradient(
                stops: [
                    .init(color: Color.background.opacity(0), location: 0.45),
                    .init(color: Color.background.opacity(0.75), location: 0.8),
                    .init(color: Color.background, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The capsule of page dots: the current page's dot is longer, and tapping a dot goes to its page.
private struct HeroPageIndicator: View {
    let count: Int
    let current: Int
    let select: (Int) -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.primary : Color.primary.opacity(0.35))
                    .frame(width: index == current ? 12 : 6, height: 6)
                    .frame(width: HomeHeroLayout.dotSlotWidth, height: 30)
                    .contentShape(.rect)
                    .onTapGesture { select(index) }
            }
        }
        .animation(Motion.animation(reduceMotion: reduceMotion), value: current)
        .padding(.horizontal, Spacing.xSmall)
        .modifier(IndicatorBackground(reduceTransparency: reduceTransparency))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "Featured", bundle: .module, comment: "Spoken name of Home's featured items' page dots.")
        )
        .accessibilityValue(HomeHero<EmptyView>.pageDescription(current, of: count))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: select(current + 1)
            case .decrement: select(current - 1)
            @unknown default: break
            }
        }
    }
}

/// Glass behind the page dots, or the regular material under Reduce Transparency.
private struct IndicatorBackground: ViewModifier {
    let reduceTransparency: Bool

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.regularMaterial, in: .capsule)
        } else {
            content.glassEffect(.regular.interactive(), in: .capsule)
        }
    }
}

/// Makes the artwork the source of the detail screen's zoom, when there is a namespace for it.
private struct HeroZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace)
        } else {
            content
        }
    }
}

/// Makes the Play button the source of the player's zoom, when there is a namespace for it.
private struct HeroPlayZoomSource: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(.rect(cornerRadius: HomeHeroLayout.actionHeight / 2, style: .continuous))
            }
        } else {
            content
        }
    }
}

extension EnvironmentValues {
    /// The width the hero's page dots take, which each page's buttons leave free.
    @Entry fileprivate var heroIndicatorReserve: CGFloat = 0
}

extension EnvironmentValues {
    /// Where the top safe area ends on the screen showing a hero, measured by that screen: below the status bar and
    /// any navigation bar. A hero's text and buttons fade out before they reach it.
    @Entry public var heroSafeAreaTop: CGFloat = 0

    /// The height of the screen a hero is on, from the top down to the home indicator, measured by `heroScreen()`.
    /// Zero until measured.
    @Entry var heroScreenHeight: CGFloat = 0
}

extension View {
    /// Measures the screen for the heroes inside this view, which are a share of its height: from the top of the
    /// window down to this view's bottom. Put it on the tab view, which reaches down to the home indicator: the tab
    /// bar and the mini player sit inside it and never change its size, so a hero keeps its size as they come and go.
    public func heroScreen() -> some View {
        modifier(HeroScreen())
    }

    /// Makes a hero, or its skeleton, ``HomeHeroLayout/heightFraction(isRegularWidth:dynamicTypeSize:)`` of the
    /// screen's height. Before the screen is measured, as in previews, it's that fraction of the scroll view's space.
    func heroFrame() -> some View {
        modifier(HeroFrame())
    }
}

private struct HeroScreen: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .environment(\.heroScreenHeight, height)
            .onGeometryChange(for: CGFloat.self) {
                $0.frame(in: .global).maxY
            } action: {
                height = $0
            }
    }
}

private struct HeroFrame: ViewModifier {
    @Environment(\.heroScreenHeight) private var screenHeight
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let fraction = HomeHeroLayout.heightFraction(
            isRegularWidth: sizeClass == .regular, dynamicTypeSize: dynamicTypeSize)
        content.containerRelativeFrame(.vertical) { [screenHeight] height, _ in
            (screenHeight > 0 ? screenHeight : height) * fraction
        }
    }
}

extension View {
    /// Marks the content of a scroll view that starts with a hero, so the hero's text and buttons know where they
    /// rest and fade only as the page scrolls. Put it on the content inside the `ScrollView`, which ignores the top
    /// safe area so the content starts at the top of the window.
    public func heroScrollContent() -> some View {
        coordinateSpace(.named(HomeHeroLayout.scrollContentSpace))
    }

    /// Fades the view out as scrolling takes its top edge up to `safeAreaTop`, over the last
    /// ``HomeHeroLayout/topFadeDistance`` points or what room it has, so it never sits under the status bar. Drawn by
    /// the renderer as the page scrolls, with no state.
    func fadesBeforeTopSafeArea(_ safeAreaTop: CGFloat) -> some View {
        visualEffect { [safeAreaTop] content, proxy in
            content.opacity(
                HomeHeroLayout.topFadeOpacity(
                    top: proxy.frame(in: .global).minY,
                    // Outside a hero screen's scroll content, as in a preview, this is where the view is, so it
                    // never fades.
                    restingTop: proxy.frame(in: .named(HomeHeroLayout.scrollContentSpace)).minY,
                    safeAreaTop: safeAreaTop
                )
            )
        }
    }
}

#if DEBUG
    /// A hero over a few rows, as Home draws it.
    private struct HomeHeroSample: View {
        @State private var selection: String?
        let items: [HeroItem]

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HomeHero(items: items, selection: $selection) { item in
                        HeroPage(
                            item: item,
                            backdrop: MockMedia.backdropImage(for: item.card),
                            logo: item.card.kind == .movie ? HomeHeroSample.logo(item.heading) : nil,
                            tint: MockMedia.tint(for: item.card),
                            play: {},
                            showDetails: {}
                        ) {
                            PreviewMenuItems()
                        }
                    }
                    MediaRow("Continue Watching", style: .landscape, items: MockLibrary.continueWatching, seeAll: {}) {
                        card in
                        LandscapeCard(card: card, artwork: MockMedia.backdropImage(for: card))
                    }
                    .padding(.top, -HomeHeroLayout.rowOverlap)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Color.background)
        }

        /// A stand-in title logo: the title set white and heavy, as logos usually are.
        @MainActor static func logo(_ title: String) -> Image? {
            let renderer = ImageRenderer(
                content: Text(verbatim: title.uppercased())
                    .font(.system(size: 64, weight: .black, design: .serif))
                    .foregroundStyle(.white)
            )
            renderer.scale = 2
            return renderer.cgImage.map { Image(decorative: $0, scale: 2) }
        }
    }

    #Preview("Light") {
        HomeHeroSample(items: MockLibrary.hero)
    }

    #Preview("Dark") {
        HomeHeroSample(items: MockLibrary.hero)
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        HomeHeroSample(items: MockLibrary.hero)
            .dynamicTypeSize(.accessibility5)
    }
#endif
