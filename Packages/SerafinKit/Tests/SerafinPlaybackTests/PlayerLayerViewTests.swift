#if canImport(UIKit)
    import AVFoundation
    import Testing
    import UIKit

    @testable import SerafinPlayback

    @MainActor @Suite struct PlayerLayerViewTests {
        private let view = PlayerLayerView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))

        @Test func bothLayersHoldThePlayerTogether() {
            let player = AVPlayer()
            view.player = player
            #expect(view.playerLayer.player === player)
            #expect(view.underlay.player === player)
            view.player = nil
            #expect(view.playerLayer.player == nil)
            #expect(view.underlay.player == nil)
        }

        @Test func thePictureUnderneathShowsOnlyOnceTheWindowLands() async throws {
            #expect(view.underlay.opacity == 0)
            view.fillHandBack(from: .milliseconds(20))
            // Not while the window is in flight.
            #expect(view.underlay.opacity == 0)
            try await Task.sleep(for: .milliseconds(200))
            #expect(view.underlay.opacity == 1)
        }

        @Test func endingTheHandBackHidesItAndStopsItShowing() async throws {
            view.fillHandBack(from: .milliseconds(20))
            view.endHandBack()
            #expect(view.underlay.opacity == 0)
            try await Task.sleep(for: .milliseconds(100))
            #expect(view.underlay.opacity == 0)
        }

        @Test func thePictureUnderneathStaysAMomentAfterTheVideoIsBack() async throws {
            view.fillHandBack(from: .zero)
            try await Task.sleep(for: .milliseconds(50))
            view.endHandBack(after: .milliseconds(50))
            #expect(view.underlay.opacity == 1)
            try await Task.sleep(for: .milliseconds(250))
            #expect(view.underlay.opacity == 0)
        }

        @Test func thePictureUnderneathFitsAndFillsLikeTheOneAbove() {
            view.setFillsBounds(true, animated: false)
            #expect(view.underlay.videoGravity == .resizeAspectFill)
            view.setFillsBounds(false, animated: false)
            #expect(view.underlay.videoGravity == .resizeAspect)
        }
    }
#endif
