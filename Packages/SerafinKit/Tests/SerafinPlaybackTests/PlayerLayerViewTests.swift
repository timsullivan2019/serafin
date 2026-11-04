#if canImport(UIKit)
    import Testing
    import UIKit

    @testable import SerafinPlayback

    @MainActor @Suite struct PlayerLayerViewTests {
        private let view = PlayerLayerView(frame: CGRect(x: 0, y: 0, width: 834, height: 1210))

        init() {
            view.layoutIfNeeded()
        }

        @Test func aHandBackHidesThePictureSoTheWindowHasNowhereToLand() {
            view.hideForHandBack()
            #expect(view.playerLayer.frame == CGRect(x: 417, y: 605, width: 0, height: 0))
            #expect(view.playerLayer.opacity == 0)
            // A layout pass while Picture in Picture looks for the picture keeps it hidden.
            view.setNeedsLayout()
            view.layoutIfNeeded()
            #expect(view.playerLayer.frame.isEmpty)
        }

        @Test func thePictureComesBackToFullSizeStillClearOnceLookedFor() {
            view.hideForHandBack()
            view.layOutAfterHandBack()
            #expect(view.playerLayer.frame == view.bounds)
            #expect(view.playerLayer.opacity == 0)
            #expect(view.handBack == .waiting)
        }

        @Test func thePictureFadesInOnceTheVideoIsBack() throws {
            view.hideForHandBack()
            view.showAfterHandBack()
            #expect(view.playerLayer.frame == view.bounds)
            #expect(view.playerLayer.opacity == 1)
            #expect(view.handBack == .none)
            let fade = try #require(view.playerLayer.animation(forKey: PlayerLayerView.fadeInKey) as? CABasicAnimation)
            let from = (fade.fromValue as? NSNumber)?.doubleValue
            let to = (fade.toValue as? NSNumber)?.doubleValue
            #expect(fade.keyPath == "opacity")
            #expect(from == 0)
            #expect(to == 1)
        }

        @Test func aHandBackThatDoesntFinishShowsThePictureAtOnce() {
            view.hideForHandBack()
            view.cancelHandBack()
            #expect(view.playerLayer.frame == view.bounds)
            #expect(view.playerLayer.opacity == 1)
            #expect(view.playerLayer.animation(forKey: PlayerLayerView.fadeInKey) == nil)
        }

        @Test func withoutAHandBackNothingFades() {
            view.showAfterHandBack()
            #expect(view.playerLayer.animation(forKey: PlayerLayerView.fadeInKey) == nil)
            #expect(view.playerLayer.frame == view.bounds)
            #expect(view.playerLayer.opacity == 1)
        }
    }
#endif
