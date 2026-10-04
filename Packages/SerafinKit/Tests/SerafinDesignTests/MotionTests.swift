import SwiftUI
import Testing

@testable import SerafinDesign

@Suite struct MotionTests {
    @Test func usesTheRequestedAnimationWhenReduceMotionIsOff() {
        #expect(Motion.animation(reduceMotion: false) == .serafinSnappy)
        #expect(Motion.animation(.smooth, reduceMotion: false) == .smooth)
    }

    @Test func swapsInTheReducedAnimationWhenReduceMotionIsOn() {
        #expect(Motion.animation(reduceMotion: true) == Motion.reduced)
        #expect(Motion.animation(.bouncy, reduceMotion: true) == Motion.reduced)
    }
}
