import SwiftUI

/// One version of a movie or an episode the viewer can pick, such as its 4K file or its 1080p one.
public struct VersionChoice: Identifiable, Hashable, Sendable {
    /// The server's ID for the version.
    public var id: String
    /// The version's name, such as "4K Remux", or its format when it has none, such as "1080p · H.264 · AAC".
    public var title: String
    /// Its media badges, such as 4K, Dolby Vision and Dolby Atmos.
    public var badges: [String]
    /// How big its file is, such as "4.2 GB", or nil when the server doesn't say.
    public var size: String?

    /// Creates a version choice.
    public init(id: String, title: String, badges: [String] = [], size: String? = nil) {
        self.id = id
        self.title = title
        self.badges = badges
        self.size = size
    }

    /// Its badges and size on one line, such as "4K · Dolby Vision · 58.2 GB", for a row with one line under its
    /// title, or nil when there's neither.
    public var detail: String? {
        let parts = badges + [size].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A detail screen's versions of a movie or an episode, such as its 4K file and its 1080p one, under a heading styled
/// like the information columns'. Each row has the version's name, badges and size. A check marks the version Play
/// starts, and tapping another picks it.
public struct VersionList: View {
    private let versions: [VersionChoice]
    private let selection: String?
    private let select: (String) -> Void

    /// Creates the list.
    ///
    /// - Parameters:
    ///   - versions: The versions, in order.
    ///   - selection: The ``VersionChoice/id`` of the version Play starts, or nil while that isn't known.
    ///   - select: Called with the ``VersionChoice/id`` of the version picked.
    public init(versions: [VersionChoice], selection: String?, select: @escaping (String) -> Void) {
        self.versions = versions
        self.selection = selection
        self.select = select
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(
                String(
                    localized: "Versions", bundle: .module, comment: "Heading of a movie's or an episode's versions.")
            )
            .typography(.title)
            .foregroundStyle(.textPrimary)
            .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(versions) { version in
                    if version.id != versions.first?.id {
                        Divider()
                    }
                    VersionRow(version: version, isSelected: version.id == selection) {
                        select(version.id)
                    }
                }
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}

/// One version: its name, badges and size, with a checkmark when Play starts it.
private struct VersionRow: View {
    let version: VersionChoice
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: Spacing.medium) {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(version.title)
                        .typography(.body)
                        .foregroundStyle(.textPrimary)
                        .multilineTextAlignment(.leading)
                    if !version.badges.isEmpty {
                        MediaBadgeRow(badges: version.badges, isLeading: true)
                    }
                    if let size = version.size {
                        Text(size)
                            .typography(.caption)
                            .foregroundStyle(.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Spacing.small)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
    private struct VersionListSample: View {
        @State private var selection = "restoration"

        var body: some View {
            ScrollView {
                VersionList(
                    versions: [
                        VersionChoice(
                            id: "restoration", title: "4K Restoration",
                            badges: ["4K", "Dolby Vision", "Dolby Atmos", "SDH"], size: "58.2 GB"),
                        VersionChoice(
                            id: "broadcast", title: "1080p · H.264 · AAC", badges: ["HD", "5.1", "CC"],
                            size: "8.4 GB"),
                        VersionChoice(id: "archive", title: "SD · MPEG-2 · Dolby Digital", badges: []),
                    ],
                    selection: selection
                ) { selection = $0 }
                .padding(Spacing.medium)
            }
            .background(Color.background)
        }
    }

    #Preview("Light") {
        VersionListSample()
    }

    #Preview("Dark") {
        VersionListSample()
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        VersionListSample()
            .dynamicTypeSize(.accessibility5)
    }
#endif
