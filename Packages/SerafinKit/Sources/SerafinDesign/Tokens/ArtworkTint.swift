import CoreGraphics
import SwiftUI

/// Derives a screen's glass tint from its artwork.
///
/// The tint is the average colour of the artwork's colourful pixels: those with mid-range saturation and enough
/// brightness for their hue to mean something. Greys, near-black shadows and the most saturated neon accents,
/// which are usually type or logos, are left out. The result's luminance is then clamped so that white text on
/// the tint has at least 5.5:1 contrast and the tint never sinks to black. Glass lightens a tint where bright
/// artwork shows through it, and the margin keeps white text above 4.5:1 there.
///
/// Artwork with almost no colourful pixels, such as a black-and-white still, gets a near-neutral tint from the
/// average of all its pixels, clamped the same way.
public enum ArtworkTint {
    /// The highest relative luminance a tint may have, so white text on it has a 5.5:1 contrast ratio.
    public static let maximumLuminance = 1.05 / 5.5 - 0.05

    /// The lowest relative luminance a tint may have, so it still reads as a colour rather than black.
    public static let minimumLuminance = 0.03

    /// Returns the glass tint for a piece of artwork.
    ///
    /// The work is a pure function of the image's pixels and costs one small offscreen draw, so it is safe to
    /// call from any thread.
    ///
    /// - Parameter image: The artwork, typically a poster or backdrop.
    /// - Returns: The tint, or `Color.accentFallback` when the image has no opaque pixels to sample.
    public static func color(for image: CGImage) -> Color {
        guard let tint = tint(for: image) else { return .accentFallback }
        return Color(.sRGB, red: tint.red, green: tint.green, blue: tint.blue)
    }

    /// The tint for a screen whose artwork hasn't loaded yet: the graphite grey that colourless artwork gets.
    ///
    /// A screen starts neutral and takes on its artwork's colour once that loads, rather than starting in another
    /// colour, such as the chosen accent, and visibly changing to the artwork's. Like every tint, it is dark enough for
    /// white text.
    public static var neutral: Color {
        let grey = neutralRGB
        return Color(.sRGB, red: grey.red, green: grey.green, blue: grey.blue)
    }

    /// Mid grey with its luminance clamped like every tint's.
    static var neutralRGB: RGB {
        RGB(red: 0.5, green: 0.5, blue: 0.5).clampingLuminance(to: minimumLuminance...maximumLuminance)
    }

    /// The side of the square, in pixels, that artwork is scaled down to before sampling.
    static let sampleSide = 40

    /// The saturation band of pixels that count as colourful.
    static let colourfulSaturation = 0.2...0.95

    /// Pixels darker than this have no reliable hue.
    static let minimumColourfulBrightness = 0.15

    /// Below this share of colourful pixels, artwork is treated as neutral.
    static let minimumColourfulShare = 0.02

    /// The clamped tint for `image`, or nil when the image has no opaque pixels.
    static func tint(for image: CGImage) -> RGB? {
        guard let pixels = opaquePixels(of: image), !pixels.isEmpty else { return nil }
        let colourful = pixels.filter(isColourful)
        let isNeutral = Double(colourful.count) < Double(pixels.count) * minimumColourfulShare
        let average = RGB.average(of: isNeutral ? pixels : colourful)
        return average.clampingLuminance(to: minimumLuminance...maximumLuminance)
    }

    static func isColourful(_ pixel: RGB) -> Bool {
        colourfulSaturation.contains(pixel.saturation) && pixel.brightness >= minimumColourfulBrightness
    }

    /// Scales `image` down to a ``sampleSide`` square and returns its mostly opaque pixels in sRGB.
    private static func opaquePixels(of image: CGImage) -> [RGB]? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let side = sampleSide
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drewImage = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: side,
                    height: side,
                    bitsPerComponent: 8,
                    bytesPerRow: side * 4,
                    space: space,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drewImage else { return nil }

        var pixels: [RGB] = []
        pixels.reserveCapacity(side * side)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[offset + 3]) / 255
            guard alpha >= 0.5 else { continue }
            // The bitmap is premultiplied, so divide the alpha back out.
            pixels.append(
                RGB(
                    red: min(Double(bytes[offset]) / 255 / alpha, 1),
                    green: min(Double(bytes[offset + 1]) / 255 / alpha, 1),
                    blue: min(Double(bytes[offset + 2]) / 255 / alpha, 1)
                )
            )
        }
        return pixels
    }
}
