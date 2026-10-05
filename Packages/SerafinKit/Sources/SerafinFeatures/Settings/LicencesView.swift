import SwiftUI

/// The open-source software inside Serafin, each with its licence and a link to its source.
struct LicencesView: View {
    private struct Package: Identifiable {
        let name: String
        let licence: String
        let url: URL?
        var id: String { name }
    }

    private let packages = [
        Package(
            name: "Jellyfin SDK for Swift", licence: "MPL-2.0",
            url: URL(string: "https://github.com/jellyfin/jellyfin-sdk-swift")),
        Package(name: "Get", licence: "MIT", url: URL(string: "https://github.com/kean/Get")),
        Package(name: "Nuke", licence: "MIT", url: URL(string: "https://github.com/kean/Nuke")),
        Package(name: "SwiftNIO", licence: "Apache-2.0", url: URL(string: "https://github.com/apple/swift-nio")),
        Package(
            name: "SwiftNIO Transport Services", licence: "Apache-2.0",
            url: URL(string: "https://github.com/apple/swift-nio-transport-services")),
        Package(
            name: "Swift Atomics", licence: "Apache-2.0", url: URL(string: "https://github.com/apple/swift-atomics")),
        Package(
            name: "Swift Collections", licence: "Apache-2.0",
            url: URL(string: "https://github.com/apple/swift-collections")),
        Package(name: "Swift System", licence: "Apache-2.0", url: URL(string: "https://github.com/apple/swift-system")),
    ]

    var body: some View {
        List {
            Section {
                ForEach(packages) { package in
                    if let url = package.url {
                        Link(destination: url) {
                            LabeledContent(package.name, value: package.licence)
                        }
                        .foregroundStyle(.primary)
                    }
                }
            } footer: {
                Text(
                    String(
                        localized:
                            "Serafin is open source under the MIT licence. The Jellyfin SDK's files stay under the Mozilla Public License 2.0.",
                        bundle: .module,
                        comment: "Footer under the list of open-source licences."
                    )
                )
            }
        }
        .readableWidth()
        .navigationTitle(
            String(
                localized: "Licences", bundle: .module,
                comment: "Title of the licences screen, and its row in Settings."))
    }
}

#if DEBUG
    #Preview {
        NavigationStack { LicencesView() }
    }
#endif
