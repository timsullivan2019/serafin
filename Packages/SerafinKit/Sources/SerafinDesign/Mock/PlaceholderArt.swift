import CoreGraphics

/// Generated stand-ins for posters and backdrops, so previews and tests look like real artwork without shipping
/// any image files.
///
/// Each image is a gradient between a lit tone and a deep tone of related hues, a soft glow, and a fine grain.
/// The same seed always gives the same image.
public enum PlaceholderArt {
    /// The pixel size of a generated poster, 2:3.
    public static let posterSize = CGSize(width: 240, height: 360)

    /// The pixel size of a generated backdrop or episode thumbnail, 16:9.
    public static let backdropSize = CGSize(width: 640, height: 360)

    /// Returns a 2:3 poster.
    ///
    /// - Parameter seed: Any number. Equal seeds give identical images.
    /// - Returns: The poster, or nil if Core Graphics cannot create a bitmap.
    public static func poster(seed: Int) -> CGImage? {
        render(size: posterSize, seed: seed, isBackdrop: false)
    }

    /// Returns a 16:9 backdrop.
    ///
    /// - Parameter seed: Any number. Equal seeds give identical images.
    /// - Returns: The backdrop, or nil if Core Graphics cannot create a bitmap.
    public static func backdrop(seed: Int) -> CGImage? {
        render(size: backdropSize, seed: seed, isBackdrop: true)
    }

    private static func render(size: CGSize, seed: Int, isBackdrop: Bool) -> CGImage? {
        var random = SeededRandom(seed: seed)
        let hue = random.unit()
        let saturation = 0.45 + 0.3 * random.unit()
        let lit = RGB(hue: hue, saturation: saturation * 0.8, brightness: 0.75 + 0.2 * random.unit())
        let deep = RGB(
            hue: hue + 0.16 * (random.unit() - 0.5),
            saturation: min(saturation + 0.15, 1),
            brightness: 0.12 + 0.12 * random.unit()
        )
        let glow = RGB(hue: hue + 0.04, saturation: 0.25, brightness: 1)

        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            let base = CGGradient(
                colorSpace: space,
                colorComponents: [lit.red, lit.green, lit.blue, 1, deep.red, deep.green, deep.blue, 1],
                locations: [0, 1],
                count: 2
            ),
            let light = CGGradient(
                colorSpace: space,
                colorComponents: [glow.red, glow.green, glow.blue, 0.45, glow.red, glow.green, glow.blue, 0],
                locations: [0, 1],
                count: 2
            )
        else { return nil }

        // Core Graphics puts the origin at the bottom left, so the lit tone starts at the top.
        let start: CGPoint
        let end: CGPoint
        if isBackdrop {
            start = CGPoint(x: size.width * 0.2 * random.unit(), y: size.height)
            end = CGPoint(x: size.width, y: 0)
        } else {
            start = CGPoint(x: size.width * random.unit(), y: size.height)
            end = CGPoint(x: size.width * random.unit(), y: 0)
        }
        context.drawLinearGradient(
            base,
            start: start,
            end: end,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        let glowCentre = CGPoint(
            x: size.width * (0.2 + 0.6 * random.unit()),
            y: size.height * (0.55 + 0.35 * random.unit())
        )
        let glowRadius = max(size.width, size.height) * (0.45 + 0.25 * random.unit())
        context.drawRadialGradient(
            light,
            startCenter: glowCentre,
            startRadius: 0,
            endCenter: glowCentre,
            endRadius: glowRadius,
            options: []
        )

        if let grain = grainTile(random: &random) {
            context.setBlendMode(.softLight)
            context.setAlpha(0.35)
            context.draw(grain, in: CGRect(x: 0, y: 0, width: grain.width, height: grain.height), byTiling: true)
        }
        return context.makeImage()
    }

    /// A square of grey noise, drawn tiled over the gradient as film grain.
    private static func grainTile(random: inout SeededRandom) -> CGImage? {
        let side = 128
        guard
            let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ),
            let data = context.data
        else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: side * side)
        for index in 0..<(side * side) {
            pixels[index] = UInt8(96 + Int(random.next() % 64))
        }
        return context.makeImage()
    }
}

/// A small, fast generator whose sequence depends only on its seed (SplitMix64).
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(bitPattern: Int64(seed))
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// A number from 0 up to, but not including, 1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }
}
