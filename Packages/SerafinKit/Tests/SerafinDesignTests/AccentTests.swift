import SwiftUI
import Testing

@testable import SerafinDesign

@MainActor
@Suite struct AccentTests {
    @Test(arguments: Accent.allCases)
    func everyAccentIsAsReadableAsTheDefault(accent: Accent) {
        for scheme in [ColorScheme.light, .dark] {
            let colour = rgb(accent.color, in: scheme)
            let background = rgb(.background, in: scheme)
            // White text, as on a selected chip or a prominent button, sits on it.
            #expect(colour.contrastRatio(with: RGB(red: 1, green: 1, blue: 1)) >= 4.5, "\(accent) \(scheme)")
            // It reads as text and symbols on the background.
            #expect(colour.contrastRatio(with: background) >= 4.5, "\(accent) \(scheme)")
        }
    }

    #if canImport(UIKit)
        @Test(arguments: Accent.allCases)
        func increaseContrastMakesEveryAccentStronger(accent: Accent) {
            for style in [UIUserInterfaceStyle.light, .dark] {
                func rgb(_ colour: Color, high: Bool) -> RGB {
                    let traits = UITraitCollection { traits in
                        traits.userInterfaceStyle = style
                        traits.accessibilityContrast = high ? .high : .normal
                    }
                    var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
                    UIColor(colour).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                    return RGB(red: red, green: green, blue: blue)
                }
                let background = rgb(.background, high: true)
                #expect(rgb(accent.color, high: true).contrastRatio(with: background) >= 7, "\(accent) \(style)")
            }
        }
    #endif

    @Test func theDefaultIsSerafinsViolet() {
        #expect(Accent.standard == .violet)
        #expect(rgb(Accent.violet.color, in: .light) == rgb(.accentFallback, in: .light))
    }

    @Test func everyAccentHasItsOwnNameAndColour() {
        #expect(Set(Accent.allCases.map(\.name)).count == Accent.allCases.count)
        let colours = Accent.allCases.map { rgb($0.color, in: .light) }
        for (index, colour) in colours.enumerated() {
            #expect(!colours[..<index].contains(colour))
        }
        #expect(Accent.allCases.count >= 16)
    }

    private func rgb(_ colour: Color, in scheme: ColorScheme) -> RGB {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        let resolved = colour.resolve(in: environment)
        #expect(resolved.opacity == 1, "the colour didn't resolve from the asset catalog")
        return RGB(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
    }
}
