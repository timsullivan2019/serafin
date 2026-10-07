import SerafinDesign
import SwiftUI

/// The first tab: Continue Watching, Next Up and the newest items in each library.
///
/// When the server can't be reached, Home shows the rows it last had, under a banner saying so. After a failure it
/// asks again when the device joins a network or Serafin comes back to the foreground.
struct HomeView: View {
    @State private var model = HomeModel()
    /// Changes each time Home asks again without pull to refresh, which starts a new load.
    @State private var attempt = 0
    @Environment(\.media) private var media
    @Environment(MediaActions.self) private var actions
    @Environment(\.scenePhase) private var scenePhase
    private let network = NetworkWatcher.shared

    var body: some View {
        content
            .background(Color.background)
            .navigationTitle(String(localized: "Home", bundle: .module, comment: "Title of the home tab."))
            .task(id: Load(revision: actions.revision, attempt: attempt)) { await model.load(from: media) }
            .onChange(of: network.connection) { _, connection in
                if connection.isOnline { tryAgainAfterAFailure() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { tryAgainAfterAFailure() }
            }
            .onChange(of: model.notice) { old, new in
                // The banner appears above where VoiceOver may be, so it's read out.
                if old == nil, let new {
                    let announcement = String(
                        localized: "\(new.message.title). \(HomeNoticeBanner.lastUpdated(new.date))",
                        bundle: .module,
                        comment:
                            "Two sentences in a row: a title, then what follows it, such as Can't Reach the Server. Check that the server is running. Siri says this when something fails, and VoiceOver reads it when Home's out-of-date banner appears."
                    )
                    AccessibilityNotification.Announcement(announcement).post()
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            Skeleton(.rows)
        case .failed(let message):
            FailureState(message: message) { attempt += 1 }
        case .loaded(let home) where home.isEmpty:
            EmptyState(
                String(localized: "Nothing Here Yet", bundle: .module, comment: "Title when the home screen is empty."),
                message: String(
                    localized: "Movies and shows you add to your server appear here.",
                    bundle: .module,
                    comment: "Explanation when the home screen is empty."
                ),
                systemImage: "sparkles.tv"
            )
        case .loaded(let home):
            rows(home)
                .onAppear { LaunchSignpost.end(showing: "Home") }
        }
    }

    private func rows(_ home: HomeContent) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xLarge) {
                if let notice = model.notice {
                    HomeNoticeBanner(notice: notice, isRetrying: model.isLoading) { attempt += 1 }
                        .padding(.horizontal, Spacing.medium)
                }
                if !home.continueWatching.isEmpty {
                    MediaRow(
                        String(
                            localized: "Continue Watching", bundle: .module,
                            comment:
                                "Started movies and episodes: the Home row, and the shortcut that plays the latest of them."
                        ),
                        style: .landscape,
                        items: home.continueWatching
                    ) { LandscapeLink(item: $0) }
                }
                if !home.nextUp.isEmpty {
                    MediaRow(
                        String(localized: "Next Up", bundle: .module, comment: "Home row of next episodes."),
                        style: .landscape,
                        items: home.nextUp
                    ) { LandscapeLink(item: $0) }
                }
                ForEach(home.latest.filter { !$0.items.isEmpty }) { row in
                    LatestRowView(row: row)
                }
            }
            .padding(.vertical, Spacing.medium)
        }
        .refreshable { await model.refresh(from: media) }
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

/// The banner above Home's rows when they're out of date: what went wrong, when the rows are from, and Try Again, or
/// Sign In Again when the server has ended the sign-in.
struct HomeNoticeBanner: View {
    let notice: HomeModel.Notice
    let isRetrying: Bool
    let retry: () -> Void
    @Environment(\.signInEnded) private var signInEnded

    var body: some View {
        NoticeBanner(
            notice.message.title,
            message: Self.lastUpdated(notice.date),
            systemImage: notice.message.systemImage,
            action: action,
            isBusy: isRetrying
        )
    }

    private var action: StateAction {
        if notice.message.needsSignIn {
            StateAction(
                String(localized: "Sign In Again", bundle: .module, comment: "Button after a sign-in has ended.")
            ) { signInEnded() }
        } else {
            StateAction(
                String(localized: "Try Again", bundle: .module, comment: "Button that retries a request."),
                perform: retry)
        }
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
