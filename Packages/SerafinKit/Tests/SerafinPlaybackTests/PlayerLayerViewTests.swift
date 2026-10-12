#if canImport(UIKit)
    import Testing
    import UIKit

    @testable import SerafinPlayback

    @MainActor @Suite struct PlayerLayerViewTests {
        private let view = PlayerLayerView(frame: CGRect(x: 0, y: 0, width: 834, height: 1210))

        @Test func theHandBackRoundsAllFourCornersInBlack() {
            view.roundCornersForHandBack(radius: 30)
            #expect(view.handBackCorners.count == 4)
            #expect(view.handBackCorners.allSatisfy { $0.fillColor == UIColor.black.cgColor })
            // Above the picture, so they show over it.
            #expect(view.layer.sublayers?.last === view.handBackCorners.last)
            // One at each corner, shrinking into it.
            #expect(
                view.handBackCorners.map(\.anchorPoint) == [
                    CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1),
                ])
        }

        @Test func withoutAPictureTheCornersStayHidden() {
            // No video, so nothing to round, as when the picture fills the view past its edges.
            view.roundCornersForHandBack(radius: 30)
            #expect(view.handBackCorners.allSatisfy { $0.isHidden })
        }

        @Test func theCornersShrinkAwayOnceTheVideoIsBack() async throws {
            view.roundCornersForHandBack(radius: 30)
            let corners = view.handBackCorners
            view.squareCornersAfterHandBack(reduceMotion: false)
            #expect(view.handBackCorners.isEmpty)
            #expect(corners.allSatisfy { $0.transform.m11 < 0.1 && $0.transform.m22 < 0.1 })
            try await Task.sleep(for: .milliseconds(600))
            #expect(corners.allSatisfy { $0.superlayer == nil })
        }

        @Test func withReduceMotionTheCornersFadeInstead() {
            view.roundCornersForHandBack(radius: 30)
            let corners = view.handBackCorners
            view.squareCornersAfterHandBack(reduceMotion: true)
            #expect(corners.allSatisfy { $0.opacity == 0 && CATransform3DIsIdentity($0.transform) })
        }

        @Test func aHandBackThatDoesntFinishTakesTheCornersAway() {
            view.roundCornersForHandBack(radius: 30)
            let corners = view.handBackCorners
            view.removeHandBackCorners()
            #expect(view.handBackCorners.isEmpty)
            #expect(corners.allSatisfy { $0.superlayer == nil })
        }

        @Test func eachCornerIsTheBlackOutsideAQuarterCircle() {
            let size = PlayerLayerView.cornerExtent(radius: 30)
            let left = PlayerLayerView.cornerPath(radius: 30, corner: .topLeft)
            let right = PlayerLayerView.cornerPath(radius: 30, corner: .topRight)
            #expect(left.boundingBoxOfPath.integral == CGRect(x: 0, y: 0, width: size, height: size).integral)
            // Black right in the corner, and none where the picture curves in.
            #expect(left.contains(CGPoint(x: 1, y: 1)))
            #expect(!left.contains(CGPoint(x: size - 1, y: size - 1)))
            #expect(right.contains(CGPoint(x: size - 1, y: 1)))
            #expect(!right.contains(CGPoint(x: 1, y: size - 1)))
            let bottomLeft = PlayerLayerView.cornerPath(radius: 30, corner: .bottomLeft)
            let bottomRight = PlayerLayerView.cornerPath(radius: 30, corner: .bottomRight)
            #expect(bottomLeft.contains(CGPoint(x: 1, y: size - 1)))
            #expect(!bottomLeft.contains(CGPoint(x: size - 1, y: 1)))
            #expect(bottomRight.contains(CGPoint(x: size - 1, y: size - 1)))
            #expect(!bottomRight.contains(CGPoint(x: 1, y: 1)))
        }
    }
#endif
