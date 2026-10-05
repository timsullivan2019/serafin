import Foundation
import SerafinDesign
import SwiftUI

/// An open-source package inside Serafin, with its licence, from `Licences.json`, which `scripts/licences.py` writes
/// from the packages Serafin builds with.
struct LicensedPackage: Decodable, Identifiable, Hashable {
    /// The package's identity in `Package.resolved`.
    let identity: String
    /// The name people know it by.
    let name: String
    /// The exact version Serafin builds with.
    let version: String
    /// Where its source is.
    let url: URL
    /// The licence's short name, such as MIT.
    let licence: String
    /// The licence's full text.
    let text: String
    /// The package's notice file, when it has one.
    let notice: String?

    var id: String { identity }

    /// The packages listed in the app's resources, or none if the list can't be read.
    static let bundled: [LicensedPackage] = {
        guard
            let url = Bundle.module.url(forResource: "Licences", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let packages = try? JSONDecoder().decode([LicensedPackage].self, from: data)
        else { return [] }
        return packages
    }()
}

/// The open-source software inside Serafin, each with its licence and a link to its source.
struct LicencesView: View {
    var body: some View {
        List {
            Section {
                ForEach(LicensedPackage.bundled) { package in
                    NavigationLink {
                        LicenceTextView(package: package)
                    } label: {
                        LabeledContent(package.name, value: package.licence)
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

/// One package's licence in full, with its version and a link to its source.
private struct LicenceTextView: View {
    let package: LicensedPackage

    var body: some View {
        List {
            Section {
                LabeledContent(
                    String(
                        localized: "Version", bundle: .module,
                        comment:
                            "Settings row showing a version: the app's in Settings, or a package's on the licences screen."
                    ),
                    value: package.version)
                Link(destination: package.url) {
                    Text(String(localized: "Source Code", bundle: .module, comment: "Link to a package's source."))
                }
            }
            Section {
                Text(package.text)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
            if let notice = package.notice {
                Section(String(localized: "Notice", bundle: .module, comment: "Heading of a package's notice file.")) {
                    Text(notice)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .readableWidth()
        .navigationTitle(package.name)
    }
}

#if DEBUG
    #Preview("Light") {
        NavigationStack { LicencesView() }
    }

    #Preview("Dark") {
        NavigationStack { LicencesView() }
            .preferredColorScheme(.dark)
    }

    #Preview("Largest text") {
        NavigationStack { LicencesView() }
            .dynamicTypeSize(.accessibility5)
    }
#endif
