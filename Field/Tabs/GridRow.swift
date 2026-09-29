import CoreGraphics

/// Where the grid's bottom row puts its buttons: Settings and a new tab at
/// the leading end, the count in the middle, Done at the trailing end, each
/// a finger wide and vertically centred in the row above the home indicator.
struct GridRow {
    static let margin: CGFloat = 8
    static let button: CGFloat = 44
    static let doneWidth: CGFloat = 80

    /// The row's width.
    let width: CGFloat

    private var top: CGFloat { (TabGrid.rowHeight - Self.button) / 2 }

    var settings: CGRect {
        CGRect(x: Self.margin, y: top, width: Self.button, height: Self.button)
    }

    var new: CGRect {
        CGRect(x: settings.maxX, y: top, width: Self.button, height: Self.button)
    }

    var done: CGRect {
        CGRect(x: width - Self.margin - Self.doneWidth, y: top, width: Self.doneWidth, height: Self.button)
    }

    /// As wide as fits between the buttons with the middle kept centred.
    var count: CGRect {
        let inset = max(new.maxX, width - done.minX)
        return CGRect(x: inset, y: top, width: max(0, width - 2 * inset), height: Self.button)
    }
}
