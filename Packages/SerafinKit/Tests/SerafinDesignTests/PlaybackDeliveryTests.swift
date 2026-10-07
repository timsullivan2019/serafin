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

@Suite struct SkipPillWordingTests {
    @Test func eachStretchSaysWhatItSkips() {
        #expect(SkipPill.Kind.intro.title == "Skip Intro")
        #expect(SkipPill.Kind.recap.title == "Skip Recap")
        #expect(SkipPill.Kind.credits.title == "Skip Credits")
        #expect(SkipPill.Kind.preview.title == "Skip Preview")
        #expect(SkipPill.Kind.advert.title == "Skip Ad")
    }
}
