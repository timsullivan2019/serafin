import SwiftUI

/// The header over a show's episodes: the season they're from, such as "Season 2", with the up and down chevrons,
/// opening a menu of every season with how many episodes each has, as the TV app does. A show with one season shows
/// its name alone.
public struct SeasonMenu: View {
    /// One season in the menu.
    public struct Season: Identifiable, Hashable, Sendable {
        /// The season's identifier.
        public var id: String
        /// Its name, such as "Season 2" or "Specials".
        public var title: String
        /// The line under the name, such as "10 episodes", or nil for none.
        public var detail: String?

        /// Creates a season for the menu.
        ///
        /// - Parameters:
        ///   - id: The season's identifier.
        ///   - title: Its name.
        ///   - detail: The line under the name, already localized.
        public init(id: String, title: String, detail: String? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
        }
    }

    private let seasons: [Season]
    @Binding private var selection: String

    /// Creates the header.
    ///
    /// - Parameters:
    ///   - seasons: The show's seasons, in the order the menu lists them.
    ///   - selection: The identifier of the season showing.
    public init(seasons: [Season], selection: Binding<String>) {
        self.seasons = seasons
        _selection = selection
    }

    public var body: some View {
        if seasons.count > 1 {
            Menu {
                // Toggles rather than a picker, whose options can't show a second line: a menu draws the checkmark
                // for the season showing and the episode count under each name.
                ForEach(seasons) { season in
                    Toggle(isOn: isSelected(season)) {
                        Text(season.title)
                        if let detail = season.detail {
                            Text(detail)
                        }
                    }
                }
            } label: {
                HStack(spacing: Spacing.xSmall) {
                    title
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.textSecondary)
                        .accessibilityHidden(true)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .modifier(PointerHighlight())
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(
                String(
                    localized: "Shows the other seasons", bundle: .module,
                    comment: "Hint on the season menu over a show's episodes.")
            )
        } else {
            title
                .accessibilityAddTraits(.isHeader)
        }
    }

    /// Whether `season` is the one showing. Choosing it again keeps it.
    private func isSelected(_ season: Season) -> Binding<Bool> {
        Binding {
            selection == season.id
        } set: { isOn in
            if isOn {
                selection = season.id
            }
        }
    }

    private var title: some View {
        Text(seasons.first { $0.id == selection }?.title ?? seasons.first?.title ?? "")
            .typography(.title)
            .foregroundStyle(.textPrimary)
            .lineLimit(1)
    }
}

#if DEBUG
    private struct SeasonMenuSample: View {
        @State private var many = "season-2"
        @State private var one = "season-1"

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.large) {
                SeasonMenu(
                    seasons: (1...16).map { Season(id: "season-\($0)", title: "Season \($0)", detail: "6 episodes") }
                        + [Season(id: "specials", title: "Specials", detail: "2 episodes")],
                    selection: $many
                )
                SeasonMenu(seasons: [Season(id: "season-1", title: "Season 1")], selection: $one)
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.background)
        }

        private typealias Season = SeasonMenu.Season
    }

    #Preview("Light") {
        SeasonMenuSample()
    }

    #Preview("Dark") {
        SeasonMenuSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        SeasonMenuSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
