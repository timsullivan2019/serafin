#if canImport(UIKit)
    import Testing
    import UIKit

    @testable import SerafinPlayback

    /// A picture as the player screen fits it, on a screen with its corner radius, and how large the window should
    /// land on it.
    struct PictureLanding: Sendable {
        var picture: CGSize
        var screen: CGSize
        var cornerRadius: CGFloat
        var scale: CGFloat
    }

    let pictureLandings = [
        // An 11-inch iPad Pro upright: a 16:9 picture as wide as the screen lands a corner radius narrower.
        PictureLanding(
            picture: CGSize(width: 834, height: 469.125), screen: CGSize(width: 834, height: 1210),
            cornerRadius: 30,
            scale: 803 / 834),
        // An iPhone 17 Pro Max on its side: the picture as tall as the screen lands a corner radius shorter.
        PictureLanding(
            picture: CGSize(width: 782.2, height: 440), screen: CGSize(width: 956, height: 440), cornerRadius: 62,
            scale: 377 / 440),
        // The same iPhone upright.
        PictureLanding(
            picture: CGSize(width: 440, height: 247.5), screen: CGSize(width: 440, height: 956), cornerRadius: 62,
            scale: 377 / 440),
        // Clear of the screen's edges, the window lands square already.
        PictureLanding(
            picture: CGSize(width: 600, height: 337.5), screen: CGSize(width: 834, height: 1210), cornerRadius: 30,
            scale: 1),
        // Filling the screen, the window's corners land past the screen's.
        PictureLanding(
            picture: CGSize(width: 2151, height: 1210), screen: CGSize(width: 834, height: 1210), cornerRadius: 30,
            scale: 1),
        // A screen with square corners leaves the window square.
        PictureLanding(
            picture: CGSize(width: 834, height: 469.125), screen: CGSize(width: 834, height: 1210), cornerRadius: 0,
            scale: 1),
        // No picture, nothing to land on.
        PictureLanding(picture: .zero, screen: CGSize(width: 834, height: 1210), cornerRadius: 30, scale: 1),
    ]

    @MainActor @Suite struct PlayerLayerViewTests {
        private let view = PlayerLayerView(frame: CGRect(x: 0, y: 0, width: 834, height: 1210))

        @Test func theWindowLandsOnASmallerPictureInTheSamePlace() {
            view.landSmallerForHandBack(scale: 0.9)
            let landing = CGRect(x: 41.7, y: 60.5, width: 750.6, height: 1089)
            #expect(Self.isClose(view.playerLayer.frame, landing))
            // A layout pass while the window lands keeps it there.
            view.setNeedsLayout()
            view.layoutIfNeeded()
            #expect(Self.isClose(view.playerLayer.frame, landing))
        }

        @Test func thePictureGrowsToFullSizeOnceTheVideoIsBack() throws {
            view.landSmallerForHandBack(scale: 0.9)
            view.growAfterHandBack()
            #expect(view.playerLayer.frame == view.bounds)
            #expect(view.handBackScale == 1)
            let grow = try #require(view.playerLayer.animation(forKey: PlayerLayerView.growKey) as? CASpringAnimation)
            #expect(grow.keyPath == "transform.scale")
            let from = (grow.fromValue as? NSNumber)?.doubleValue
            let to = (grow.toValue as? NSNumber)?.doubleValue
            #expect(from == 0.9)
            #expect(to == 1)
        }

        @Test func aHandBackThatDoesntFinishPutsThePictureBackAtOnce() {
            view.landSmallerForHandBack(scale: 0.9)
            view.cancelHandBackLanding()
            #expect(view.playerLayer.frame == view.bounds)
            #expect(view.playerLayer.animation(forKey: PlayerLayerView.growKey) == nil)
        }

        @Test func withoutASmallerLandingNothingGrows() {
            view.layoutIfNeeded()
            view.growAfterHandBack()
            #expect(view.playerLayer.animation(forKey: PlayerLayerView.growKey) == nil)
            view.landSmallerForHandBack(scale: 1)
            #expect(view.playerLayer.frame == view.bounds)
        }

        @Test(arguments: pictureLandings)
        func theLandingStaysACornerRadiusShortOfTheScreen(_ landing: PictureLanding) {
            let scale = PlayerLayerView.landingScale(
                pictureSize: landing.picture, screenSize: landing.screen, cornerRadius: landing.cornerRadius)
            #expect(abs(scale - landing.scale) < 0.0001)
        }

        private static func isClose(_ a: CGRect, _ b: CGRect) -> Bool {
            abs(a.minX - b.minX) < 0.01 && abs(a.minY - b.minY) < 0.01 && abs(a.width - b.width) < 0.01
                && abs(a.height - b.height) < 0.01
        }
    }
#endif
