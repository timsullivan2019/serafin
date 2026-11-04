import SerafinCore
import SerafinDesign
import SwiftUI

/// The first tab: featured items at the top, then Continue Watching, Next Up and the newest items in each library.
///
/// The hero is the top of the screen, under the status bar, with no navigation bar over it; its text and buttons fade
/// out before they reach the status bar, and the top edge blurs once Home is scrolled at all. When the server can't
/// be reached, Home shows the downloads, which play without it, under a banner saying so, or with nothing downloaded,
/// the rows it last had. After a failure it asks again when the device joins a network or Serafin comes back to the
/// foreground. Each time the server answers, the progress made with downloads that it hasn't heard yet is sent.
struct HomeView: View {
    @State private var model = HomeModel()
    /// Whether Home has been scrolled at all, which brings the top edge's blur over whatever passes under the status
    /// bar.
    @State private var isScrolled = false
    /// Where the top safe area ends, below the status bar and the navigation bar, which the hero's text and buttons
    /// fade out before reaching.
    @State private var safeAreaTop: CGFloat = 0
    /// The hero's size, for prefetching the next page's artwork at the size it's drawn.
    @State private var heroSize: CGSize = .zero
    /// Whether pull to refresh is running, which the hero shows, since its stretched artwork covers the system's
    /// spinner.
    @State private var isRefreshing = false
    /// Changes each time Home asks again without pull to refresh, which starts a new load.
    @State private var attempt = 0
    @Environment(\.media) private var media
    @Environment(\.artwork) private var artwork
    @Environment(MediaActions.self) private var actions
    @Environment(DownloadCenter.self) private var downloads: DownloadCenter?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale
    private let network = NetworkWatcher.shared

    var body: some View {
        content
            .background(Color.background)
            .navigationTitle(String(localized: "Home", bundle: .module, comment: "Title of the home tab."))
            .toolbarTitleDisplayMode(.inline)
            // With the hero, the bar holds only the profile button, over the artwork; the title would sit on the
            // poster. The bar never changes while scrolling, which kept the scroll from settling.
            .toolbar(removing: showsTitle ? nil : .title)
            .profileToolbar()
            .overlay(alignment: .top) {
                if isRefreshing, showsHero {
                    ProgressView()
                        .padding(Spacing.xSmall)
                        .glassEffect(.regular, in: .circle)
                        .padding(.top, Spacing.xSmall)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: isRefreshing)
            .task(id: Load(revision: actions.revision, attempt: attempt)) {
                model.artwork = artwork
                await model.load(from: media)
                // The server answers, so progress made with downloads while it didn't can reach it now.
                guard !Task.isCancelled, model.failure == nil, let downloads else { return }
                if await downloads.syncPlayback() {
                    actions.reload()
                }
            }
            .task(id: model.revision) {
                prefetchNextPage()
                await hero.refreshShows(from: media)
            }
            .onChange(of: hero.selection) { prefetchNextPage() }
            .onChange(of: heroSize) { prefetchNextPage() }
            .onChange(of: network.connection) { _, connection in
                if connection.isOnline { tryAgainAfterAFailure() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { tryAgainAfterAFailure() }
            }
            .onChange(of: bannerAnnouncement) { old, new in
                // A banner appears above where VoiceOver may be, so it's read out.
                if let new, new != old {
                    AccessibilityNotification.Announcement(new).post()
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let offlineReason, let downloads {
            HomeDownloads(reason: offlineReason, items: downloads.offlineItems, isRetrying: model.isLoading) {
                attempt += 1
            }
            .refreshable { await model.refresh(from: media) }
            .onAppear { LaunchSignpost.end(showing: "Downloads") }
        } else {
            rowsOrState
        }
    }

    @ViewBuilder private var rowsOrState: some View {
        switch model.phase {
        case .loading:
            Skeleton(.rows)
        case .failed(let message):
            FailureState(message: message) { attempt += 1 }
        case .loaded(let home) where home.isEmpty:
            EmptyState(
                String(
                    localized: "Nothing Here Yet", bundle: .module,
                    comment: "Title when Home or the Library tab is empty."),
                message: String(
                    localized: "Movies and shows you add to your server appear here.",
                    bundle: .module,
                    comment: "Explanation when Home or the Library tab is empty."
                ),
                systemImage: "sparkles.tv"
            )
        case .loaded(let home):
            rows(home)
                .onAppear { LaunchSignpost.end(showing: "Home") }
        }
    }

    private func rows(_ home: HomeContent) -> some View {
        let hasHero = !hero.entries.isEmpty
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hasHero {
                    HomeHero(items: hero.items, selection: Bindable(hero).selection) { item in
                        if let entry = hero.entry(item.id) {
                            HomeHeroPage(entry: entry)
                        }
                    }
                    .onGeometryChange(for: CGSize.self) {
                        $0.size
                    } action: {
                        heroSize = $0
                    }
                }
                LazyVStack(alignment: .leading, spacing: Spacing.large) {
                    if let notice = model.notice {
                        HomeNoticeBanner(notice: notice, isRetrying: model.isLoading) { attempt += 1 }
                            .padding(.horizontal, Spacing.medium)
                    }
                    // An episode here plays when tapped; a movie opens its page.
                    if !home.continueWatching.isEmpty {
                        MediaRow(Self.continueWatchingTitle, style: .landscape, items: home.continueWatching) {
                            WatchingLink(item: $0, showsPlayedBadge: false)
                        }
                    }
                    if !home.nextUp.isEmpty {
                        MediaRow(Self.nextUpTitle, style: .landscape, items: home.nextUp) {
                            WatchingLink(item: $0)
                        }
                    }
                    ForEach(home.latest.filter { !$0.items.isEmpty }) { row in
                        LatestRowView(row: row)
                    }
                }
                // The first row rises into the hero's fade, so the page reads as one piece.
                .padding(.top, hasHero ? -HomeHeroLayout.rowOverlap : Spacing.medium)
                .padding(.bottom, Spacing.medium)
            }
            .heroScrollContent()
        }
        // The hero runs under the status bar; without one, the rows start under the bar as usual.
        .ignoresSafeArea(edges: hasHero ? .top : [])
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            let scrolled = HomeHeroLayout.isScrolled(offset: offset, wasScrolled: isScrolled)
            if scrolled != isScrolled {
                isScrolled = scrolled
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.top
        } action: {
            safeAreaTop = $0
        }
        .environment(\.heroSafeAreaTop, safeAreaTop)
        // Anything scrolling up under the status bar softens into it, the hero's artwork included, so nothing is ever
        // drawn sharp behind the clock. At rest the artwork runs clear to the top of the screen.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .scrollEdgeEffectHidden(hasHero && !isScrolled, for: .top)
        .refreshable {
            isRefreshing = true
            await model.refresh(from: media)
            isRefreshing = false
        }
    }

    private var hero: HomeHeroModel { model.hero }

    /// Why Home shows the downloads instead of the server's rows, or nil when it shows the rows: the server can't be
    /// reached, and something is downloaded.
    private var offlineReason: UserMessage? {
        guard let downloads, !downloads.offlineItems.isEmpty else { return nil }
        return model.offlineReason(isOnline: network.connection.isOnline)
    }

    /// Whether the hero shows at the top.
    private var showsHero: Bool {
        guard offlineReason == nil, case .loaded = model.phase else { return false }
        return !hero.entries.isEmpty
    }

    /// Whether the bar shows the title: not over the hero or its skeleton.
    private var showsTitle: Bool {
        if offlineReason != nil { return true }
        switch model.phase {
        case .loading: return false
        case .loaded: return hero.entries.isEmpty
        case .failed: return true
        }
    }

    /// What VoiceOver reads when a banner shows above the downloads or the rows, or nil when there's none.
    private var bannerAnnouncement: String? {
        if let offlineReason {
            return HomeNoticeBanner.announcement(offlineReason, detail: HomeDownloads.detail)
        }
        guard let notice = model.notice else { return nil }
        return HomeNoticeBanner.announcement(notice.message, detail: HomeNoticeBanner.lastUpdated(notice.date))
    }

    /// The title of Home's row of started movies and episodes. The row is the whole list: it has no screen of its own.
    static var continueWatchingTitle: String {
        String(
            localized: "Continue Watching", bundle: .module,
            comment: "Started movies and episodes: the Home row, and the shortcut that plays the latest of them.")
    }

    /// The title of Home's row of each show's next episode. The row is the whole list: it has no screen of its own.
    static var nextUpTitle: String {
        String(localized: "Next Up", bundle: .module, comment: "Home row of next episodes.")
    }

    private func prefetchNextPage() {
        hero.prefetchPage(after: hero.selection, size: heroSize, scale: displayScale, artwork: artwork)
    }

    /// Asks the server again when the last load failed and nothing is asking already.
    private func tryAgainAfterAFailure() {
        guard model.isWorthRetrying, !model.isLoading else { return }
        attempt += 1
    }

    /// What starts a load: something changing in the library, or asking again.
    private struct Load: Equatable {
        let revision: Int
        let attempt: Int
    }
}

/// The banner above Home's rows when they're out of date, or above the downloads Home shows when the server can't be
/// reached: what went wrong, a line on what's showing, and Try Again, or Sign In Again when the server has ended the
/// sign-in.
struct HomeNoticeBanner: View {
    let message: UserMessage
    /// The line under what went wrong, such as when the rows are from.
    let detail: String
    let isRetrying: Bool
    let retry: () -> Void
    @Environment(\.signInEnded) private var signInEnded

    /// The banner over out-of-date rows, saying when they're from.
    init(notice: HomeModel.Notice, isRetrying: Bool, retry: @escaping () -> Void) {
        self.init(message: notice.message, detail: Self.lastUpdated(notice.date), isRetrying: isRetrying, retry: retry)
    }

    /// A banner saying what went wrong, with `detail` under it.
    init(message: UserMessage, detail: String, isRetrying: Bool, retry: @escaping () -> Void) {
        self.message = message
        self.detail = detail
        self.isRetrying = isRetrying
        self.retry = retry
    }

    var body: some View {
        NoticeBanner(
            message.title,
            message: detail,
            systemImage: message.systemImage,
            action: action,
            isBusy: isRetrying
        )
    }

    private var action: StateAction {
        if message.needsSignIn {
            StateAction(
                String(localized: "Sign In Again", bundle: .module, comment: "Button after a sign-in has ended.")
            ) { signInEnded() }
        } else {
            StateAction(
                String(localized: "Try Again", bundle: .module, comment: "Button that retries a request."),
                perform: retry)
        }
    }

    /// What VoiceOver reads when a banner appears: what went wrong, then `detail`, the line under it.
    nonisolated static func announcement(_ message: UserMessage, detail: String) -> String {
        String(
            localized: "\(message.title). \(detail)",
            bundle: .module,
            comment:
                "Two sentences in a row: a title, then what follows it, such as Can't Reach the Server. Check that the server is running. Siri says this when something fails, and VoiceOver reads it when a banner appears on Home."
        )
    }

    /// When the rows are from, as the banner says it, such as "Last updated 9:41 AM".
    nonisolated static func lastUpdated(
        _ date: Date, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let time = date.updateTime(relativeTo: now, calendar: calendar, locale: locale)
        return String(
            localized: "Last updated \(time)",
            bundle: .module,
            locale: locale,
            comment:
                "Banner on Home when its rows are out of date. The argument is when they're from, such as 9:41 AM or Oct 3 at 9:41 PM."
        )
    }
}

extension Date {
    /// When something was last updated, as a banner names it: the time for today, the day and time for another day
    /// this year, and the date and time for an earlier year.
    func updateTime(relativeTo now: Date, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        if !calendar.isDate(self, inSameDayAs: now) {
            style = style.month(.abbreviated).day()
            if !calendar.isDate(self, equalTo: now, toGranularity: .year) {
                style = style.year()
            }
        }
        return formatted(style)
    }
}

/// "Latest in Movies": the newest posters of one library, with See All opening the library.
private struct LatestRowView: View {
    let row: HomeContent.LatestRow
    @Environment(\.navigate) private var navigate

    var body: some View {
        MediaRow(
            String(
                localized: "Latest in \(row.library.name)",
                bundle: .module,
                comment: "Home row of a library's newest items, such as Latest in Movies."
            ),
            style: .posters,
            items: row.items,
            seeAll: { navigate(.library(row.library)) }
        ) { PosterLink(item: $0) }
    }
}

#if DEBUG
    #Preview("Light") {
        TabStack { HomeView() }
            .previewEnvironment()
    }

    #Preview("Dark") {
        TabStack { HomeView() }
            .previewEnvironment()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        TabStack { HomeView() }
            .previewEnvironment()
            .dynamicTypeSize(.accessibility5)
    }
#endif
