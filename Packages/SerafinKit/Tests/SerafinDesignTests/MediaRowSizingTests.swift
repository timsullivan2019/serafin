import CoreGraphics
import Testing

@testable import SerafinDesign

@Suite struct MediaRowSizingTests {
    /// A row's visible width: the window less the row's 16-point margin on each side.
    private func visible(_ window: CGFloat) -> CGFloat { window - 32 }

    private func across(_ style: MediaRowStyle, regular: Bool, large: Bool = false, window: CGFloat) -> CGFloat {
        RowSizing(style: style, isRegular: regular, isLarge: large).across(in: visible(window))
    }

    @Test(arguments: [375.0, 390, 402, 440])
    func phonesKeepTheirCardCounts(window: CGFloat) {
        #expect(abs(across(.posters, regular: false, window: window) - 3.3) < 0.001)
        #expect(abs(across(.landscape, regular: false, window: window) - 1.3) < 0.001)
        #expect(abs(across(.people, regular: false, window: window) - 3.3) < 0.001)
        #expect(abs(across(.posters, regular: false, large: true, window: window) - 1.6) < 0.001)
        #expect(abs(across(.landscape, regular: false, large: true, window: window) - 1.05) < 0.001)
        #expect(abs(across(.people, regular: false, large: true, window: window) - 2.1) < 0.001)
    }

    @Test(arguments: [375.0, 390, 402, 440])
    func everyRowOnAPhoneShowsTheSameSliceOfItsNextCard(window: CGFloat) {
        let slices = [MediaRowStyle.posters, .landscape, .people].map { style in
            let across = across(style, regular: false, window: window)
            return across - across.rounded(.down)
        }
        #expect(Set(slices.map { ($0 * 1000).rounded() }).count == 1)
    }

    @Test(arguments: [820.0, 834])
    func elevenInchIPadsInPortraitKeepTheirCardCounts(window: CGFloat) {
        #expect(abs(across(.posters, regular: true, window: window) - 6.3) < 0.001)
        #expect(abs(across(.landscape, regular: true, window: window) - 3.2) < 0.001)
        #expect(abs(across(.people, regular: true, window: window) - 7.3) < 0.001)
        #expect(abs(across(.posters, regular: true, large: true, window: window) - 3.3) < 0.001)
        #expect(abs(across(.landscape, regular: true, large: true, window: window) - 2.2) < 0.001)
        #expect(abs(across(.people, regular: true, large: true, window: window) - 3.6) < 0.001)
    }

    @Test(arguments: [(600.0, false), (600, true), (1194, true), (1376, true)])
    func otherWindowsGainCardsInsteadOfStretchingThem(window: CGFloat, regular: Bool) {
        for style in [MediaRowStyle.posters, .landscape, .people] {
            let sizing = RowSizing(style: style, isRegular: regular, isLarge: false)
            let ratio = sizing.cardWidth(in: visible(window)) / sizing.comfortableWidth
            #expect(ratio > 0.8 && ratio < 1.35, "\(style) at \(window) points is \(ratio)× its comfortable width")
        }
    }

    @Test func aWindowNarrowerThanOneCardStillShowsOne() {
        let sizing = RowSizing(style: .landscape, isRegular: false, isLarge: true)
        #expect(abs(sizing.across(in: 200) - 1.05) < 0.001)
        #expect(sizing.cardWidth(in: 200) > 0)
    }
}
