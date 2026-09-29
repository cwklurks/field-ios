import SwiftUI
import Testing
import UIKit
@testable import Field

/// Whether a page reads as light or dark, from its background, so the glass
/// bar over it can be the same.
struct PageToneTests {
    @Test func whiteAndNearWhiteAreLight() {
        #expect(Tab.scheme(for: .white) == .light)
        #expect(Tab.scheme(for: UIColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)) == .light)
    }

    @Test func blackAndNearBlackAreDark() {
        #expect(Tab.scheme(for: .black) == .dark)
        #expect(Tab.scheme(for: UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)) == .dark)
    }

    /// By how bright it looks, not by its numbers: pure blue is dark and
    /// pure yellow light, though each is two-thirds zeros or ones.
    @Test func brightnessIsPerceived() {
        #expect(Tab.scheme(for: UIColor(red: 0, green: 0, blue: 1, alpha: 1)) == .dark)
        #expect(Tab.scheme(for: UIColor(red: 1, green: 1, blue: 0, alpha: 1)) == .light)
    }

    /// A page with no background of its own says nothing about itself.
    @Test func clearSaysNothing() {
        #expect(Tab.scheme(for: .clear) == nil)
        #expect(Tab.scheme(for: nil) == nil)
    }
}

/// A token pinned to one look, for the glass bar, which takes the page's look
/// rather than the app's.
struct FixedColourTests {
    @Test func aTokenPinnedToALookIsThatLooksColour() {
        let dark = UIColor(Palette.fixed(Palette.UI.ink, in: .dark))
        let light = UIColor(Palette.fixed(Palette.UI.ink, in: .light))
        // Resolved in the opposite look, each keeps its own.
        #expect(abs(red(dark, in: .light) - 0.93) < 0.001)
        #expect(abs(red(light, in: .dark) - 0.09) < 0.001)
    }

    private func red(_ colour: UIColor, in style: UIUserInterfaceStyle) -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: style)).getRed(&r, green: &g, blue: &b, alpha: &a)
        return r
    }
}
