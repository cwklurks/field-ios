import CoreGraphics

/// Where each card sits in the tab grid: two columns, centred, each a picture
/// of its page with the title below, in sections: each of Tidy's groups under
/// its name, then the loose tabs with none. Pure, so the grid, the transition
/// that lands the page on its card, and the tests all agree on the same frames.
/// A card's index runs on across the sections.
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
    /// A group's name, above its cards.
    static let header: CGFloat = 34

    /// A run of cards: a group, under its name, or the loose tabs.
    struct Section: Equatable {
        let count: Int
        let named: Bool
    }

    /// The grid's width.
    let width: CGFloat
    let sections: [Section]
    /// Content above the first row: the status bar and some air.
    let top: CGFloat
    /// Content below the last row: the grid's bottom row and the home indicator.
    let bottom: CGFloat

    /// No groups: one run of cards, as the grid was before them.
    init(width: CGFloat, count: Int, top: CGFloat, bottom: CGFloat) {
        self.init(width: width, sections: [Section(count: count, named: false)], top: top, bottom: bottom)
    }

    init(width: CGFloat, sections: [Section], top: CGFloat, bottom: CGFloat) {
        self.width = width
        self.sections = sections
        self.top = top
        self.bottom = bottom
    }

    var count: Int { sections.reduce(0) { $0 + $1.count } }

    var cardWidth: CGFloat {
        floor((width - 2 * Self.margin - Self.gap) / CGFloat(Self.columns))
    }

    var pictureHeight: CGFloat { round(cardWidth * Self.aspect) }

    private var rowHeight: CGFloat { pictureHeight + Self.titleHeight + Self.rowGap }
    private var left: CGFloat {
        floor((width - CGFloat(Self.columns) * cardWidth - Self.gap) / 2)
    }

    private static func rows(_ count: Int) -> Int { (count + columns - 1) / columns }

    /// Each section's first card, and where it starts, its header included.
    private var starts: [(first: Int, y: CGFloat)] {
        var first = 0, y = top
        return sections.map { section in
            defer {
                first += section.count
                y += (section.named ? Self.header : 0) + CGFloat(Self.rows(section.count)) * rowHeight
            }
            return (first, y)
        }
    }

    /// Section `s`'s name, over its cards; nil for the loose tabs.
    func header(_ s: Int) -> CGRect? {
        guard sections.indices.contains(s), sections[s].named else { return nil }
        return CGRect(x: left, y: starts[s].y, width: width - 2 * left, height: Self.header)
    }

    /// Card `i`'s picture, in the grid's content coordinates.
    func picture(_ i: Int) -> CGRect {
        let starts = starts
        let s = starts.indices.first { i < starts[$0].first + sections[$0].count } ?? starts.count - 1
        let j = i - starts[s].first
        let row = j / Self.columns, column = j % Self.columns
        let y = starts[s].y + (sections[s].named ? Self.header : 0)
        return CGRect(
            x: left + CGFloat(column) * (cardWidth + Self.gap),
            y: y + CGFloat(row) * rowHeight,
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
        count == 0 ? top + bottom : card(count - 1).maxY + bottom
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

    /// A card moving from index `from` to `to` changes row.
    static func wraps(from: Int, to: Int) -> Bool {
        from / columns != to / columns
    }

    /// How a card goes to its place after a close or a reopen.
    enum Move: Equatable {
        case stay
        /// Along its row.
        case slide
        /// To another row, across the cards sliding along theirs: over
        /// them, so none passes under another.
        case hop
        /// New to the list: it grows in.
        case arrive
    }

    /// From index `from` (nil: it wasn't in the list) to `to`.
    static func move(from: Int?, to: Int) -> Move {
        guard let from else { return .arrive }
        if from == to { return .stay }
        return wraps(from: from, to: to) ? .hop : .slide
    }

    /// The cards any part of which is within this stretch of content.
    func visible(from y: CGFloat, height: CGFloat) -> Range<Int> {
        var lower: Int?, upper = 0
        for (s, start) in starts.enumerated() where sections[s].count > 0 {
            let cards = start.y + (sections[s].named ? Self.header : 0)
            let first = max(0, Int(floor((y - cards) / rowHeight)))
            let last = Int(floor((y + height - cards) / rowHeight))
            guard last >= 0, first < Self.rows(sections[s].count) else { continue }
            let from = start.first + min(sections[s].count, first * Self.columns)
            let to = start.first + min(sections[s].count, (last + 1) * Self.columns)
            guard from < to else { continue }
            lower = lower.map { min($0, from) } ?? from
            upper = max(upper, to)
        }
        return lower.map { $0..<upper } ?? 0..<0
    }
}
