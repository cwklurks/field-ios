// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI
import UIKit

// The Mac's palette, grey for grey. The page is the ground, and everything
// the browser draws has to get out of its way.
//
// Every colour is a pair, one for light and one for dark, and resolves itself
// against whatever the view it's in is showing. The app takes its look from
// Settings (see Look), and nothing else in the code knows which it is.
enum Palette {
    static let ground = Color(uiColor: UI.ground)
    static let ink = Color(uiColor: UI.ink)             // neutral-900 · neutral-100
    static let muted = Color(uiColor: UI.muted)         // neutral-500
    static let faint = Color(uiColor: UI.faint)         // neutral-300 · neutral-700
    static let hairline = Color(uiColor: UI.hairline)   // neutral-200 · neutral-800
    static let wash = Color(uiColor: UI.wash)           // the live tab
    static let press = Color(uiColor: UI.press)         // the one under a finger; the Mac's hover
    static let raised = Color(uiColor: UI.raised)       // the bar
    /// The only two that aren't grey: a connection nobody can read on the
    /// way, and one anybody can.
    static let safe = Color(uiColor: UI.safe)           // green-700 · green-400
    static let unsafe = Color(uiColor: UI.unsafe)       // amber-700 · amber-400

    /// A colour as it is in one look, whichever look it's drawn in: the glass
    /// bar takes the page's look, not the app's.
    static func fixed(_ colour: UIColor, in scheme: ColorScheme) -> Color {
        Color(uiColor: colour.resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)))
    }

    /// The same colours for the UIKit corners of the app (the field, the web
    /// view's background), which want a UIColor and keep it.
    ///
    /// Nonisolated because a UIColor goes wherever it's drawn, main thread or
    /// not (a sleeping tab's picture), and a provider tied to the main actor
    /// traps when it's resolved anywhere else.
    nonisolated enum UI {
        static let ground = pair(1.0, 0.11)
        static let ink = pair(0.09, 0.93)
        static let muted = pair(0.55, 0.58)
        static let faint = pair(0.83, 0.32)
        static let hairline = pair(0.91, 0.20)
        static let wash = pair(0.937, 0.175)
        static let press = pair(0.965, 0.15)
        /// The one thing that stands off the page. White on white in light,
        /// where a shadow does the lifting; in dark a step up from the ground,
        /// because a shadow there has nothing darker to fall on.
        static let raised = pair(1.0, 0.16)
        static let safe = tint(light: (0.08, 0.50, 0.24), dark: (0.29, 0.87, 0.50))
        static let unsafe = tint(light: (0.71, 0.33, 0.04), dark: (0.98, 0.75, 0.14))

        // The Mac's greys are NSColor(white:), which is Generic Gray Gamma 2.2,
        // and ColorSync takes that to sRGB one to one: 0.11 draws as 28/255
        // either way. So the same level on all three sRGB channels is the same
        // grey, spelled out rather than left to UIKit's own grey space.
        private static func pair(_ light: CGFloat, _ dark: CGFloat) -> UIColor {
            tint(light: (light, light, light), dark: (dark, dark, dark))
        }

        private static func tint(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> UIColor {
            UIColor { traits in
                let c = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            }
        }
    }
}
