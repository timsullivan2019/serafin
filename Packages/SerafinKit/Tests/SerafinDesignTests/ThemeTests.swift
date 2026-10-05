import SwiftUI
import Testing

@testable import SerafinDesign

@MainActor
@Suite struct ThemeTests {
    private static let colours: [(name: String, colour: Color)] = [
        ("background", .background),
        ("surface", .surface),
        ("textPrimary", .textPrimary),
        ("textSecondary", .textSecondary),
        ("accentFallback", .accentFallback),
    ]

    @Test(arguments: [ColorScheme.light, .dark])
    func everyColourResolvesFromTheAssetCatalog(scheme: ColorScheme) {
        for entry in Self.colours {
            // A missing or misnamed colour set resolves to clear.
            #expect(resolve(entry.colour, in: scheme).opacity == 1, "\(entry.name) did not resolve")
        }
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func textMeetsContrastOnBackgroundAndSurface(scheme: ColorScheme) {
        for text in [Color.textPrimary, .textSecondary] {
            for ground in [Color.background, .surface] {
                let ratio = rgb(text, in: scheme).contrastRatio(with: rgb(ground, in: scheme))
                #expect(ratio >= 4.5)
            }
        }
    }

    /// The fallback accent stands in for an artwork tint behind white text, and also colours text and controls on
    /// the background, so it has to pass both ways.
    @Test(arguments: [ColorScheme.light, .dark])
    func accentFallbackCarriesWhiteTextAndReadsOnTheBackground(scheme: ColorScheme) {
        let accent = rgb(.accentFallback, in: scheme)
        #expect(accent.contrastRatio(with: RGB(red: 1, green: 1, blue: 1)) >= 4.5)
        #expect(accent.relativeLuminance >= ArtworkTint.minimumLuminance)
        if scheme == .dark {
            #expect(accent.contrastRatio(with: rgb(.background, in: scheme)) >= 4.5)
        }
    }

    @Test func backgroundFollowsTheAppearance() {
        #expect(rgb(.background, in: .light).relativeLuminance > 0.9)
        #expect(rgb(.background, in: .dark).relativeLuminance < 0.01)
    }

    #if canImport(UIKit)
        /// Increase Contrast takes secondary text and the accent to the stricter AAA level, and sets surfaces further
        /// apart from the background.
        @Test(arguments: [UIUserInterfaceStyle.light, .dark])
        func increaseContrastRaisesContrast(style: UIUserInterfaceStyle) {
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
            #expect(rgb(.textSecondary, high: true).contrastRatio(with: background) >= 7)
            #expect(rgb(.accentFallback, high: true).contrastRatio(with: background) >= 4.5)
            #expect(
                rgb(.surface, high: true).contrastRatio(with: background)
                    > rgb(.surface, high: false).contrastRatio(with: rgb(.background, high: false))
            )
        }
    #endif

    private func resolve(_ colour: Color, in scheme: ColorScheme) -> Color.Resolved {
        var environment = EnvironmentValues()
        environment.colorScheme = scheme
        return colour.resolve(in: environment)
    }

    private func rgb(_ colour: Color, in scheme: ColorScheme) -> RGB {
        let resolved = resolve(colour, in: scheme)
        return RGB(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue))
    }
}
