import CoreGraphics
import Testing

@testable import SerafinDesign

@Suite struct ArtworkTintTests {
    private let white = RGB(red: 1, green: 1, blue: 1)

    @Test func redArtworkGivesARedTint() throws {
        let artwork = try ArtworkImage.solid(RGB(red: 0.80, green: 0.10, blue: 0.08))
        let tint = try #require(ArtworkTint.tint(for: artwork))
        #expect(tint.hue < 0.03 || tint.hue > 0.97)
        #expect(tint.saturation > 0.8)
        #expect(tint.contrastRatio(with: white) >= 5.5)
    }

    @Test func darkBlueArtworkIsLiftedToAVisibleBlue() throws {
        let navy = RGB(red: 0.02, green: 0.05, blue: 0.20)
        let tint = try #require(ArtworkTint.tint(for: try ArtworkImage.solid(navy)))
        #expect(abs(tint.hue - navy.hue) < 0.02)
        #expect(navy.relativeLuminance < ArtworkTint.minimumLuminance)
        #expect(tint.relativeLuminance >= ArtworkTint.minimumLuminance)
        #expect(tint.contrastRatio(with: white) >= 5.5)
    }

    @Test func nearWhiteArtworkGivesANeutralTintThatKeepsWhiteTextLegible() throws {
        let artwork = try ArtworkImage.solid(RGB(red: 0.97, green: 0.97, blue: 0.95))
        let tint = try #require(ArtworkTint.tint(for: artwork))
        #expect(tint.saturation < 0.1)
        #expect(tint.relativeLuminance >= ArtworkTint.minimumLuminance)
        #expect(tint.relativeLuminance <= ArtworkTint.maximumLuminance)
        #expect(tint.contrastRatio(with: white) >= 5.5)
    }

    @Test func theNeutralTintIsAGreyThatKeepsWhiteTextLegible() {
        let grey = ArtworkTint.neutralRGB
        #expect(grey.red == grey.green && grey.green == grey.blue)
        #expect(grey.relativeLuminance >= ArtworkTint.minimumLuminance)
        #expect(grey.relativeLuminance <= ArtworkTint.maximumLuminance + 0.0001)
        #expect(grey.contrastRatio(with: white) >= 5.5)
    }

    @Test func greyPixelsDoNotDiluteTheTint() throws {
        let blue = RGB(red: 0.10, green: 0.30, blue: 0.80)
        let artwork = try ArtworkImage.split(left: RGB(red: 0.5, green: 0.5, blue: 0.5), right: blue)
        let tint = try #require(ArtworkTint.tint(for: artwork))
        #expect(abs(tint.hue - blue.hue) < 0.02)
        #expect(tint.saturation > 0.75)
    }

    @Test func blackArtworkGivesADarkGreyRatherThanBlack() throws {
        let tint = try #require(ArtworkTint.tint(for: try ArtworkImage.solid(RGB(red: 0, green: 0, blue: 0))))
        #expect(tint.saturation == 0)
        #expect(tint.relativeLuminance >= ArtworkTint.minimumLuminance)
    }

    @Test func transparentArtworkHasNoTint() throws {
        #expect(ArtworkTint.tint(for: try ArtworkImage.transparent()) == nil)
    }
}

/// Generated test artwork, drawn in sRGB.
private enum ArtworkImage {
    struct DrawingFailed: Error {}

    static func solid(_ colour: RGB) throws -> CGImage {
        try draw { context, width, height in
            fill(context, CGRect(x: 0, y: 0, width: width, height: height), with: colour)
        }
    }

    static func split(left: RGB, right: RGB) throws -> CGImage {
        try draw { context, width, height in
            fill(context, CGRect(x: 0, y: 0, width: width / 2, height: height), with: left)
            fill(context, CGRect(x: width / 2, y: 0, width: width / 2, height: height), with: right)
        }
    }

    static func transparent() throws -> CGImage {
        try draw { _, _, _ in }
    }

    private static func fill(_ context: CGContext, _ rect: CGRect, with colour: RGB) {
        context.setFillColor(red: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
        context.fill(rect)
    }

    private static func draw(_ body: (CGContext, Int, Int) -> Void) throws -> CGImage {
        let width = 120
        let height = 180
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw DrawingFailed() }
        body(context, width, height)
        guard let image = context.makeImage() else { throw DrawingFailed() }
        return image
    }
}
