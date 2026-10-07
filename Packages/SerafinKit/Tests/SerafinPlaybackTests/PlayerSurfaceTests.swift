#if canImport(UIKit)
    import AVFoundation
    import Testing

    @testable import SerafinPlayback

    @MainActor
    @Suite struct PlayerSurfaceTests {
        @Test func thePictureFitsUntilItIsSetToFill() {
            let view = PlayerLayerView()
            #expect(view.playerLayer.videoGravity == .resizeAspect)
            #expect(!view.fillsBounds)

            view.setFillsBounds(true, animated: false)
            #expect(view.playerLayer.videoGravity == .resizeAspectFill)
            #expect(view.fillsBounds)

            view.setFillsBounds(false, animated: true)
            #expect(view.playerLayer.videoGravity == .resizeAspect)
            #expect(!view.fillsBounds)
        }
    }
#endif
