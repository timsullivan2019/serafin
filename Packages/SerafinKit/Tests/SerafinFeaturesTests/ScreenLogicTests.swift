import Foundation
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

@MainActor
@Suite struct LibraryModelTests {
    private let model = LibraryModel(scope: .library(MockLibrary.libraries[0]))

    @Test func aNewSortStartsInItsNaturalDirection() {
        model.select(.dateAdded)
        #expect(model.options.sort == .dateAdded)
        #expect(!model.options.ascending)
        model.select(.name)
        #expect(model.options.ascending)
    }

    @Test func choosingTheSameSortAgainFlipsIt() {
        model.select(.rating)
        model.select(.rating)
        #expect(model.options.ascending)
    }

    @Test func theSamplesLoadAndFilter() async {
        await model.reload(from: SampleMediaSource())
        let all = model.total
        #expect(all > 0)
        model.options.unplayedOnly = true
        await model.reload(from: SampleMediaSource())
        #expect(model.slots.allSatisfy { $0?.card.isPlayed == false })
        #expect(model.total <= all)
    }
}

@Suite struct SettingsLogicTests {
    @Test func qualityCapsReadAsTheyShowAndSend() {
        #expect(PlaybackQuality.maximum.bitsPerSecond == nil)
        #expect(PlaybackQuality.mbps8.bitsPerSecond == 8_000_000)
        #expect(PlaybackQuality.mbps8.title == "8 Mbps")
    }

    @Test func gridOptionsKnowWhenAFilterIsOn() {
        var options = GridOptions()
        #expect(!options.isFiltered)
        options.genre = "Comedy"
        #expect(options.isFiltered)
    }
}

@Suite struct UserMessageTests {
    @Test func anEndedSignInAsksToSignInAgain() {
        #expect(UserMessage(SerafinError.notSignedIn).needsSignIn)
        #expect(!UserMessage(SerafinError.serverUnreachable).needsSignIn)
    }

    @Test func unknownErrorsNeverShowRawText() {
        let message = UserMessage(URLError(.badServerResponse))
        #expect(message.title == "Something Went Wrong")
        #expect(!message.message.contains("NSURLError"))
    }

    @Test func everyCoreErrorHasAMessage() {
        let errors: [SerafinError] = [
            .keychain(status: -25300), .keychainDataCorrupt, .serverStoreUnavailable, .invalidAddress,
            .insecureTransport, .offline, .serverUnreachable, .plainHTTPBlocked, .notAllowedFromThisNetwork,
            .notJellyfin, .unsupportedServerVersion("10.9.11"),
            .invalidCredentials, .quickConnectDisabled, .quickConnectExpired, .notSignedIn, .notFound,
            .unexpectedResponse(status: 500),
        ]
        for error in errors {
            let message = UserMessage(error)
            #expect(!message.title.isEmpty && !message.message.isEmpty)
        }
    }
}

@Suite struct LicencesTests {
    /// The packages pinned in `Package.resolved`, by identity, with their versions.
    private func pinned() throws -> [String: String] {
        let resolved = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Package.resolved")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: resolved)) as? [String: Any]
        let pins = try #require(object?["pins"] as? [[String: Any]])
        return Dictionary(
            uniqueKeysWithValues: pins.compactMap { pin in
                guard let identity = pin["identity"] as? String,
                    let version = (pin["state"] as? [String: Any])?["version"] as? String
                else { return nil }
                return (identity, version)
            })
    }

    @Test func licenceTextIsReflowedIntoParagraphs() {
        let text = "Permission is hereby granted,\r\n  free of charge.\n\n   \nTHE SOFTWARE IS PROVIDED\n\"AS IS\".\n"
        #expect(
            LicenceParagraph.paragraphs(of: text) == [
                LicenceParagraph(kind: .body, text: "Permission is hereby granted, free of charge."),
                LicenceParagraph(kind: .body, text: "THE SOFTWARE IS PROVIDED \"AS IS\"."),
            ])
    }

    @Test func markdownHeadingsItemsAndHardBreaksKeepTheirShape() {
        let text = """
            Mozilla Public License Version 2.0
            ==================================

            ### 1. Definitions

            **1.1. “Contributor”**  \n    means each individual
                or legal entity.

            * **(a)** that the initial
              Contributor
            * **(b)** that the Covered Software
            -------------------------------
            The end.
            """
        #expect(
            LicenceParagraph.paragraphs(of: text) == [
                LicenceParagraph(kind: .heading, text: "Mozilla Public License Version 2.0"),
                LicenceParagraph(kind: .heading, text: "1. Definitions"),
                LicenceParagraph(kind: .body, text: "**1.1. “Contributor”**\nmeans each individual or legal entity."),
                LicenceParagraph(kind: .item, text: "**(a)** that the initial Contributor"),
                LicenceParagraph(kind: .item, text: "**(b)** that the Covered Software"),
                LicenceParagraph(kind: .body, text: "The end."),
            ])
    }

    @Test func onlyTheJellyfinSDKLicenceIsMarkdown() {
        #expect(LicensedPackage.bundled.filter(\.markdown).map(\.identity) == ["jellyfin-sdk-swift"])
    }

    @Test func theLicencesScreenListsEveryPackageAtItsPinnedVersion() throws {
        let listed = Dictionary(uniqueKeysWithValues: LicensedPackage.bundled.map { ($0.identity, $0.version) })
        // When this fails, run scripts/licences.py after changing the packages.
        #expect(listed == (try pinned()))
    }

    @Test func everyPackageCarriesItsLicenceText() {
        #expect(!LicensedPackage.bundled.isEmpty)
        for package in LicensedPackage.bundled {
            #expect(["MIT", "Apache-2.0", "MPL-2.0"].contains(package.licence))
            #expect(package.text.count > 500)
        }
    }
}
