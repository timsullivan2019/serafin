import Testing

@testable import SerafinDesign

@Suite struct PlaybackDeliveryWordingTests {
    /// The player and Settings must use these exact words.
    @Test func theThreeDeliveriesUseTheAgreedWording() {
        #expect(PlaybackDelivery.directPlay.title == "Direct play")
        #expect(PlaybackDelivery.repackaged.title == "Repackaged on server (no quality loss)")
        #expect(PlaybackDelivery.transcoding.title == "Transcoding on server")
    }

    @Test func everyDeliveryIsExplained() {
        for delivery in PlaybackDelivery.allCases {
            #expect(!delivery.explanation.isEmpty)
            #expect(!delivery.systemImage.isEmpty)
        }
    }
}

@Suite struct SkipSegmentWordingTests {
    @Test func eachStretchSaysWhatItSkips() {
        #expect(SkipSegmentButton.Kind.intro.title == "Skip Intro")
        #expect(SkipSegmentButton.Kind.recap.title == "Skip Recap")
        #expect(SkipSegmentButton.Kind.preview.title == "Skip Preview")
        #expect(SkipSegmentButton.Kind.advert.title == "Skip Ad")
        #expect(SkipSegmentButton.Kind.credits.title == "Skip Credits")
        #expect(SkipSegmentButton.Kind.unknown.title == "Skip")
    }

    @Test func theNoticeSaysWhatWasSkipped() {
        #expect(SkipSegmentButton.Kind.intro.skippedTitle == "Skipped intro")
        #expect(SkipSegmentButton.Kind.recap.skippedTitle == "Skipped recap")
        #expect(SkipSegmentButton.Kind.preview.skippedTitle == "Skipped preview")
        #expect(SkipSegmentButton.Kind.advert.skippedTitle == "Skipped ad")
    }

    @Test func thePillIsAsTallAsTheSpecSays() {
        // `.buttonStyle(.glass)` pads a label by 7 points above and below, measured on the iOS 27 simulator.
        #expect(SkipSegmentButton.height == 44)
        #expect(SkipSegmentButton.height - 2 * SkipSegmentButton.glassVerticalPadding == 30)
    }
}
