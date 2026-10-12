import CoreGraphics
import Testing

@testable import SerafinDesign

@Suite struct GenreTileTests {
    @Test func tilesAre160By90OnIPhone() {
        #expect(GenreTileLayout.size(isRegular: false, isLarge: false) == CGSize(width: 160, height: 90))
    }

    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func everyTileIsSixteenByNine(isRegular: Bool, isLarge: Bool) {
        let size = GenreTileLayout.size(isRegular: isRegular, isLarge: isLarge)
        #expect(abs(size.width / size.height - 16 / 9) < 0.001)
    }

    @Test func iPadAndLargeTextGetLargerTiles() {
        let phone = GenreTileLayout.size(isRegular: false, isLarge: false).width
        #expect(GenreTileLayout.size(isRegular: true, isLarge: false).width > phone)
        #expect(GenreTileLayout.size(isRegular: false, isLarge: true).width > phone)
        // At accessibility sizes a tile still fits on the narrowest iPhone, inside the row's margins.
        #expect(GenreTileLayout.size(isRegular: false, isLarge: true).width <= 375 - 32)
    }
}
