import SwiftUI
import Testing
import UIKit
@testable import Field

/// The Mac's white levels, light then dark, copied from Search's Design.swift
/// rather than read back from Palette, so a slip in the port fails here.
private let greys: [(name: String, ui: UIColor, color: Color, light: CGFloat, dark: CGFloat)] = [
    ("ground", Palette.UI.ground, Palette.ground, 1.0, 0.11),
    ("ink", Palette.UI.ink, Palette.ink, 0.09, 0.93),
    ("muted", Palette.UI.muted, Palette.muted, 0.55, 0.58),
    ("faint", Palette.UI.faint, Palette.faint, 0.83, 0.32),
    ("hairline", Palette.UI.hairline, Palette.hairline, 0.91, 0.20),
    ("wash", Palette.UI.wash, Palette.wash, 0.937, 0.175),
    ("press", Palette.UI.press, Palette.press, 0.965, 0.15),
    ("raised", Palette.UI.raised, Palette.raised, 1.0, 0.16),
]

private let lightTraits = UITraitCollection(userInterfaceStyle: .light)
private let darkTraits = UITraitCollection(userInterfaceStyle: .dark)

/// sRGB red, green, blue and alpha, as the colour resolves in those traits.
private func rgba(_ colour: UIColor, _ traits: UITraitCollection) -> [CGFloat] {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    colour.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a)
    return [r, g, b, a]
}

private func close(_ a: [CGFloat], _ b: [CGFloat]) -> Bool {
    zip(a, b).allSatisfy { abs($0 - $1) < 0.0005 }
}

private func environment(_ scheme: ColorScheme) -> EnvironmentValues {
    var environment = EnvironmentValues()
    environment.colorScheme = scheme
    return environment
}

struct PaletteTests {
    @Test func everyTokenChangesWithTheLook() {
        let all = greys.map { ($0.name, $0.ui) } + [("safe", Palette.UI.safe), ("unsafe", Palette.UI.unsafe)]
        for (name, colour) in all {
            #expect(!close(rgba(colour, lightTraits), rgba(colour, darkTraits)), "\(name)")
        }
    }

    @Test func greysAreTheMacsLevelsInSRGB() {
        for grey in greys {
            let l = grey.light, d = grey.dark
            #expect(close(rgba(grey.ui, lightTraits), [l, l, l, 1]), "\(grey.name) light")
            #expect(close(rgba(grey.ui, darkTraits), [d, d, d, 1]), "\(grey.name) dark")
        }
    }

    @Test func tintsAreTheMacs() {
        #expect(close(rgba(Palette.UI.safe, lightTraits), [0.08, 0.50, 0.24, 1]))
        #expect(close(rgba(Palette.UI.safe, darkTraits), [0.29, 0.87, 0.50, 1]))
        #expect(close(rgba(Palette.UI.unsafe, lightTraits), [0.71, 0.33, 0.04, 1]))
        #expect(close(rgba(Palette.UI.unsafe, darkTraits), [0.98, 0.75, 0.14, 1]))
    }

    /// With no look set yet, a colour is the light one.
    @Test func unspecifiedIsLight() {
        let unspecified = UITraitCollection(userInterfaceStyle: .unspecified)
        #expect(close(rgba(Palette.UI.ground, unspecified), [1, 1, 1, 1]))
    }

    /// The SwiftUI colours are wired to the right UIColor, and follow the
    /// colour scheme SwiftUI resolves them in.
    @Test func swiftUIColoursFollowTheScheme() {
        for grey in greys {
            let light = grey.color.resolve(in: environment(.light))
            let dark = grey.color.resolve(in: environment(.dark))
            #expect(abs(CGFloat(light.red) - grey.light) < 0.0005, "\(grey.name) light")
            #expect(abs(CGFloat(dark.red) - grey.dark) < 0.0005, "\(grey.name) dark")
            #expect(light.red == light.green && light.green == light.blue, "\(grey.name) is grey")
        }
    }

    /// A sleeping tab's picture is drawn off the main thread, so the colours
    /// have to resolve there too. A provider tied to the main actor traps.
    @Test func coloursResolveOffTheMainThread() async {
        let colours = greys.map(\.ui) + [Palette.UI.safe, Palette.UI.unsafe]
        let reds = await Task.detached {
            let dark = UITraitCollection(userInterfaceStyle: .dark)
            return colours.map { colour in
                var red: CGFloat = 0
                colour.resolvedColor(with: dark).getRed(&red, green: nil, blue: nil, alpha: nil)
                return red
            }
        }.value
        #expect(close(reds, greys.map(\.dark) + [0.29, 0.98]))
    }
}
