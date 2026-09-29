// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// The type ramp: the Mac's sizes plus 2 to 3 points, since a phone is read
/// closer but smaller. Each step lands on or beside the iOS text style whose
/// Dynamic Type curve it follows, so it grows with the reader's setting in
/// the same proportion as the rest of the phone, up to `cap`.
///
/// System font only. Regular almost everywhere, medium for labels and the
/// title, semibold for headings.
struct Ramp {
    let size: CGFloat
    let weight: Font.Weight
    let style: Font.TextStyle

    static let title = Ramp(size: 36, weight: .medium, style: .largeTitle)     // Mac 34
    static let heading = Ramp(size: 20, weight: .semibold, style: .title3)     // Mac 17
    static let field = Ramp(size: 18, weight: .regular, style: .body)          // Mac 15.5, the address
    static let message = Ramp(size: 17, weight: .regular, style: .body)        // Mac 14, a page that failed
    static let row = Ramp(size: 16, weight: .regular, style: .callout)         // Mac 13
    static let tab = Ramp(size: 15, weight: .regular, style: .subheadline)     // Mac 12.5
    static let toast = Ramp(size: 14.5, weight: .regular, style: .subheadline) // Mac 12
    static let caption = Ramp(size: 14, weight: .regular, style: .footnote)    // Mac 11.5, details
    static let label = Ramp(size: 14, weight: .medium, style: .footnote)       // Mac 11.5 medium, section labels
    static let glyph = Ramp(size: 11, weight: .regular, style: .caption2)      // Mac 9, marks beside a title

    /// Where the chrome stops growing: the largest size short of the
    /// accessibility ones, so the bar keeps to one line. Pages have their
    /// own text size.
    static let cap = DynamicTypeSize.xxxLarge
}

extension View {
    func ramp(_ step: Ramp) -> some View {
        modifier(Typeset(step: step))
    }
}

private struct Typeset: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(step: Ramp) {
        _size = ScaledMetric(wrappedValue: step.size, relativeTo: step.style)
        weight = step.weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}
