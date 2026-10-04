import Foundation

/// A colour in the sRGB colour space, with gamma-encoded components from 0 to 1.
struct RGB: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double

    /// HSB brightness: the largest component.
    var brightness: Double { max(red, green, blue) }

    /// HSB saturation, from 0 for grey to 1 for a pure hue.
    var saturation: Double {
        brightness == 0 ? 0 : (brightness - min(red, green, blue)) / brightness
    }

    /// HSB hue as a fraction of the colour wheel, starting from red at 0.
    var hue: Double {
        let delta = brightness - min(red, green, blue)
        guard delta > 0 else { return 0 }
        let sector: Double
        if brightness == red {
            sector = (green - blue) / delta
        } else if brightness == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        let turn = (sector / 6).truncatingRemainder(dividingBy: 1)
        return turn < 0 ? turn + 1 : turn
    }

    /// Relative luminance as WCAG defines it, from 0 for black to 1 for white.
    var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    /// The WCAG contrast ratio between this colour and `other`, from 1 to 21.
    func contrastRatio(with other: RGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The same hue and saturation with brightness multiplied by `factor`.
    func scaled(by factor: Double) -> RGB {
        RGB(red: min(red * factor, 1), green: min(green * factor, 1), blue: min(blue * factor, 1))
    }

    /// The same hue and saturation, made brighter or darker until the luminance falls inside `range`.
    ///
    /// Black has no hue, so it comes back as a neutral grey at the bottom of the range.
    func clampingLuminance(to range: ClosedRange<Double>) -> RGB {
        let luminance = relativeLuminance
        guard !range.contains(luminance) else { return self }
        let base = brightness == 0 ? RGB(red: 1, green: 1, blue: 1) : self
        let target = min(max(luminance, range.lowerBound), range.upperBound)

        // Luminance rises with the brightness factor, so a binary search finds the factor that meets the target.
        // `lower` always stays below the target and `upper` at or above it.
        var lower = 0.0
        var upper = 1 / base.brightness
        for _ in 0..<32 {
            let middle = (lower + upper) / 2
            if base.scaled(by: middle).relativeLuminance < target {
                lower = middle
            } else {
                upper = middle
            }
        }
        return base.scaled(by: luminance > range.upperBound ? lower : upper)
    }

    /// The average of `colours`, taken in linear light so that dark and bright pixels weigh fairly.
    static func average(of colours: [RGB]) -> RGB {
        guard !colours.isEmpty else { return RGB(red: 0, green: 0, blue: 0) }
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        for colour in colours {
            red += linear(colour.red)
            green += linear(colour.green)
            blue += linear(colour.blue)
        }
        let count = Double(colours.count)
        return RGB(red: encoded(red / count), green: encoded(green / count), blue: encoded(blue / count))
    }

    /// Converts a gamma-encoded sRGB component to linear light.
    static func linear(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    /// Converts a linear-light component back to gamma-encoded sRGB.
    static func encoded(_ component: Double) -> Double {
        component <= 0.0031308 ? component * 12.92 : 1.055 * pow(component, 1 / 2.4) - 0.055
    }
}

extension RGB {
    /// Creates a colour from HSB components, each from 0 to 1. Hue wraps around the colour wheel.
    init(hue: Double, saturation: Double, brightness: Double) {
        let turn = hue - hue.rounded(.down)
        let sector = turn * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))
        let value = brightness
        let low = value * (1 - saturation)
        let falling = value * (1 - saturation * fraction)
        let rising = value * (1 - saturation * (1 - fraction))
        switch index {
        case 0: self.init(red: value, green: rising, blue: low)
        case 1: self.init(red: falling, green: value, blue: low)
        case 2: self.init(red: low, green: value, blue: rising)
        case 3: self.init(red: low, green: falling, blue: value)
        case 4: self.init(red: rising, green: low, blue: value)
        default: self.init(red: value, green: low, blue: falling)
        }
    }
}
