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
