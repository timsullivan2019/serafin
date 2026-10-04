import Foundation
import SerafinCore
import SerafinDesign
import Testing

@testable import SerafinFeatures

@MainActor
@Suite struct LibraryModelTests {
    private let model = LibraryModel(library: MockLibrary.libraries[0])

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
        let all = model.items.count
        #expect(all > 0)
        model.options.unplayedOnly = true
        await model.reload(from: SampleMediaSource())
        #expect(model.items.allSatisfy { !$0.card.isPlayed })
        #expect(model.items.count <= all)
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
            .insecureTransport, .serverUnreachable, .notJellyfin, .unsupportedServerVersion("10.9.11"),
            .invalidCredentials, .quickConnectDisabled, .quickConnectExpired, .notSignedIn, .notFound,
            .unexpectedResponse(status: 500),
        ]
        for error in errors {
            let message = UserMessage(error)
            #expect(!message.title.isEmpty && !message.message.isEmpty)
        }
    }
}
