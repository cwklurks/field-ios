// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// Corner radii, each named for what wears it. Always continuous corners.
enum Radius {
    static let panel: CGFloat = 16   // sheets and panels
    static let field: CGFloat = 14   // the address field's surface
    static let card: CGFloat = 11    // cards
    static let filter: CGFloat = 10  // a field that narrows a list
    static let row: CGFloat = 9      // rows and tabs
    static let chip: CGFloat = 7     // the chosen one in a segmented row

    /// A site's icon keeps the same squircle at any size.
    static func icon(_ size: CGFloat) -> CGFloat { size * 0.22 }
}

extension Shape where Self == RoundedRectangle {
    /// The only rounded rectangle Field draws: continuous, never circular.
    static func corner(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
