import CoreGraphics

/// Where each card sits in the tab grid: two columns, centred, each a picture
/// of its page with the title below. Pure, so the grid, the transition that
/// lands the page on its card, and the tests all agree on the same frames.
struct GridLayout: Equatable {
    static let columns = 2
    static let margin: CGFloat = 16
    /// Between the two columns.
    static let gap: CGFloat = 14
    /// Below a card's title, before the next row.
    static let rowGap: CGFloat = 16
    /// The favicon letter and title under the picture.
    static let titleHeight: CGFloat = 30
    /// A picture's height over its width: the top of the page, a little
    /// taller than square, as in Safari.
    static let aspect: CGFloat = 1.36

    /// The grid's width.
    let width: CGFloat
    let count: Int
    /// Content above the first row: the status bar and some air.
    let top: CGFloat
    /// Content below the last row: the grid's bottom row and the home indicator.
    let bottom: CGFloat

    var cardWidth: CGFloat {
        floor((width - 2 * Self.margin - Self.gap) / CGFloat(Self.columns))
    }

    var pictureHeight: CGFloat { round(cardWidth * Self.aspect) }

    private var rowHeight: CGFloat { pictureHeight + Self.titleHeight + Self.rowGap }
    private var rows: Int { (count + Self.columns - 1) / Self.columns }
    private var left: CGFloat {
        floor((width - CGFloat(Self.columns) * cardWidth - Self.gap) / 2)
    }

    /// Card `i`'s picture, in the grid's content coordinates.
    func picture(_ i: Int) -> CGRect {
        let row = i / Self.columns, column = i % Self.columns
        return CGRect(
            x: left + CGFloat(column) * (cardWidth + Self.gap),
            y: top + CGFloat(row) * rowHeight,
            width: cardWidth,
            height: pictureHeight
        )
    }

    /// The picture and its title.
    func card(_ i: Int) -> CGRect {
        var frame = picture(i)
        frame.size.height += Self.titleHeight
        return frame
    }

    var contentHeight: CGFloat {
        rows == 0 ? top + bottom : card(count - 1).maxY + bottom
    }

    /// The scroll offset that puts card `i` in the middle of a viewport this
    /// tall, kept within the content.
    func offset(showing i: Int, viewport: CGFloat) -> CGFloat {
        let most = max(0, contentHeight - viewport)
        return min(most, max(0, picture(i).midY - viewport / 2))
    }

    /// Where a grid scrolled to `y` is scrolled once its count has changed:
    /// the same place, or as far down as the shorter content now goes.
    func offset(keeping y: CGFloat, viewport: CGFloat) -> CGFloat {
        min(y, max(0, contentHeight - viewport))
    }

    /// A card moving from index `from` to `to` changes row, crossing the
    /// cards that only slide along one.
    static func wraps(from: Int, to: Int) -> Bool {
        from / columns != to / columns
    }

    /// The cards any part of which is within this stretch of content.
    func visible(from y: CGFloat, height: CGFloat) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        let first = max(0, Int(floor((y - top) / rowHeight)))
        let last = max(first, Int(floor((y + height - top) / rowHeight)))
        let lower = min(count, first * Self.columns)
        let upper = min(count, (last + 1) * Self.columns)
        return lower..<upper
    }
}
