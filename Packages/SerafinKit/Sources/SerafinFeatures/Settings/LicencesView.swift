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
    /// Whether the licence file is Markdown, as the Jellyfin SDK's is.
    let markdown: Bool

    var id: String { identity }

    /// The licence's paragraphs, with the line breaks inside each one removed so the text wraps to the screen.
    var paragraphs: [LicenceParagraph] { LicenceParagraph.paragraphs(of: text) }

    /// The notice's paragraphs, wrapped the same way.
    var noticeParagraphs: [LicenceParagraph] { notice.map(LicenceParagraph.paragraphs(of:)) ?? [] }

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

/// A paragraph of licence text, reflowed from a file written for an 80-column terminal.
struct LicenceParagraph: Hashable {
    enum Kind: Hashable {
        /// A Markdown heading, or a title underlined with `=` or `-`.
        case heading
        /// A list item, which began with `*` or `-`.
        case item
        /// Running text.
        case body
    }

    let kind: Kind
    /// The paragraph's text, on one line apart from Markdown's hard line breaks.
    let text: String

    /// Splits text into paragraphs at blank lines, headings, list items and rules, and joins the lines of each one
    /// with single spaces.
    static func paragraphs(of text: String) -> [LicenceParagraph] {
        var paragraphs: [LicenceParagraph] = []
        var lines: [String] = []
        var kind = Kind.body

        func finish(as finished: Kind? = nil) {
            var joined = ""
            for (index, line) in lines.enumerated() {
                joined += line.trimmingCharacters(in: .whitespaces)
                if index < lines.count - 1 { joined += line.hasSuffix("  ") ? "\n" : " " }
            }
            if !joined.isEmpty { paragraphs.append(LicenceParagraph(kind: finished ?? kind, text: joined)) }
            lines = []
            kind = .body
        }

        for line in text.replacing("\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                finish()
            } else if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "=" }) || trimmed.allSatisfy({ $0 == "-" }) {
                // An underline makes the running text above it a heading; anything else, it just ends.
                finish(as: kind == .body && !lines.isEmpty ? .heading : nil)
            } else if trimmed.hasPrefix("#") {
                finish()
                lines = [String(trimmed.drop(while: { $0 == "#" }))]
                finish(as: .heading)
            } else if trimmed.hasPrefix("* ") || trimmed.hasPrefix("- ") {
                finish()
                lines = [String(trimmed.dropFirst(2))]
                kind = .item
            } else {
                lines.append(String(line))
            }
        }
        finish()
        return paragraphs
    }
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
                            "Serafin is open source under the MIT license. The Jellyfin SDK's files stay under the Mozilla Public License 2.0.",
                        bundle: .module,
                        comment: "Footer under the list of open-source licenses."
                    )
                )
            }
        }
        .readableWidth()
        .navigationTitle(
            String(
                localized: "Licenses", bundle: .module,
                comment: "Title of the licenses screen, and its row in Settings."))
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
                LicenceParagraphs(paragraphs: package.paragraphs, markdown: package.markdown)
            }
            if package.notice != nil {
                Section(String(localized: "Notice", bundle: .module, comment: "Heading of a package's notice file.")) {
                    LicenceParagraphs(paragraphs: package.noticeParagraphs, markdown: false)
                }
            }
        }
        .readableWidth()
        .navigationTitle(package.name)
    }
}

/// Paragraphs of licence text, wrapped to the width they're given.
private struct LicenceParagraphs: View {
    let paragraphs: [LicenceParagraph]
    /// Whether to show Markdown's bold and italics, rather than its asterisks.
    let markdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                switch paragraph.kind {
                case .heading:
                    styled(paragraph.text).bold()
                        .accessibilityAddTraits(.isHeader)
                case .item:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "•")
                            .accessibilityHidden(true)
                        styled(paragraph.text)
                    }
                case .body:
                    styled(paragraph.text)
                }
            }
        }
        .font(.footnote)
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }

    private func styled(_ text: String) -> Text {
        guard markdown,
            let attributed = try? AttributedString(
                markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        else { return Text(verbatim: text) }
        return Text(attributed)
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
