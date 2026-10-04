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

    @Test(arguments: [ColorScheme.light, .dark])
    func accentFallbackIsWithinTheArtworkTintRange(scheme: ColorScheme) {
        let luminance = rgb(.accentFallback, in: scheme).relativeLuminance
        #expect((ArtworkTint.minimumLuminance...ArtworkTint.maximumLuminance).contains(luminance))
    }

    @Test func backgroundFollowsTheAppearance() {
        #expect(rgb(.background, in: .light).relativeLuminance > 0.9)
        #expect(rgb(.background, in: .dark).relativeLuminance < 0.01)
    }

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
