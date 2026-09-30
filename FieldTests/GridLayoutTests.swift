import CoreGraphics
import Testing
@testable import Field

/// Where each card sits in the tab grid: two columns, centred, each card a
/// picture of the page with its title below.
struct GridLayoutTests {
    // An iPhone 17's width, under its status bar, above the grid's own row.
    let layout = GridLayout(width: 402, count: 7, top: 74, bottom: 120)

    @Test func twoColumnsCentredWithEqualMargins() {
        let left = layout.picture(0)
        let right = layout.picture(1)
        #expect(left.minY == right.minY)
        #expect(left.width == right.width)
        #expect(right.minX - left.maxX == GridLayout.gap)
        #expect(abs(left.minX - (402 - right.maxX)) <= 1)
        #expect(left.minX >= GridLayout.margin)
    }

    @Test func picturesKeepTheirShape() {
        let p = layout.picture(0)
        #expect(abs(p.height / p.width - GridLayout.aspect) < 0.01)
    }

    @Test func rowsFollowOnBelowTheTitles() {
        let first = layout.card(0)
        let third = layout.picture(2)
        #expect(layout.picture(0).minY == 74)
        #expect(first.maxY + GridLayout.rowGap == third.minY)
        #expect(first.height == layout.picture(0).height + GridLayout.titleHeight)
    }

    @Test func theContentEndsAfterTheLastRowAndTheBottom() {
        // Seven cards, four rows.
        #expect(layout.contentHeight == layout.card(6).maxY + 120)
    }

    /// Opening the grid scrolls so the current tab's card is in the middle,
    /// never past either end.
    @Test func showsACardInTheMiddleWithinTheEnds() {
        let many = GridLayout(width: 402, count: 50, top: 74, bottom: 120)
        let viewport: CGFloat = 874
        #expect(many.offset(showing: 0, viewport: viewport) == 0)
        let middle = many.offset(showing: 24, viewport: viewport)
        let card = many.picture(24)
        #expect(abs((card.midY - middle) - viewport / 2) < 1)
        #expect(many.offset(showing: 49, viewport: viewport) == many.contentHeight - viewport)
        // Everything fits: never scrolled.
        #expect(layout.offset(showing: 6, viewport: 2000) == 0)
    }

    @Test func visibleCardsAreTheRowsOnScreen() {
        let many = GridLayout(width: 402, count: 50, top: 74, bottom: 120)
        let range = many.visible(from: 0, height: 874)
        #expect(range.lowerBound == 0)
        #expect(range.contains(3))
        #expect(!range.contains(49))
        let later = many.visible(from: many.picture(20).minY, height: 300)
        #expect(later.contains(20))
        #expect(later.contains(21))
        #expect(!later.contains(17))
        #expect(later.upperBound <= 50)
    }

    @Test func noCardsStillHasAHeight() {
        let empty = GridLayout(width: 402, count: 0, top: 74, bottom: 120)
        #expect(empty.visible(from: 0, height: 874).isEmpty)
        #expect(empty.contentHeight == 194)
    }

    /// A card closed or reopened: the grid stays scrolled where it was, or,
    /// now shorter than that, as far down as it goes.
    @Test func keepsItsScrollWithinTheNewContent() {
        let viewport: CGFloat = 874
        let nine = GridLayout(width: 402, count: 9, top: 74, bottom: 120)
        let eight = GridLayout(width: 402, count: 8, top: 74, bottom: 120)
        let bottom = nine.contentHeight - viewport
        #expect(eight.offset(keeping: bottom, viewport: viewport) == eight.contentHeight - viewport)
        #expect(eight.offset(keeping: 40, viewport: viewport) == 40)
        #expect(layout.offset(keeping: 300, viewport: 2000) == 0)
    }

    /// Only a card going from the start of a row to the end of the one above
    /// changes row.
    @Test func aCardWrapsWhenItChangesRow() {
        #expect(GridLayout.wraps(from: 6, to: 5))
        #expect(GridLayout.wraps(from: 5, to: 6))
        #expect(!GridLayout.wraps(from: 5, to: 4))
        #expect(!GridLayout.wraps(from: 7, to: 6))
        #expect(!GridLayout.wraps(from: 3, to: 3))
    }

    /// After a close the cards after it move back one place, and after a
    /// reopen on one. Those staying on their row slide along it; those
    /// changing row hop, fading out of one place and into the other, so no
    /// card passes through another. A card new to the list grows in.
    @Test func cardsSlideAlongTheirRowOrHopToAnother() {
        #expect(GridLayout.move(from: 2, to: 2) == .stay)
        // Closed at 1.
        #expect(GridLayout.move(from: 3, to: 2) == .slide)
        #expect(GridLayout.move(from: 4, to: 3) == .hop)
        #expect(GridLayout.move(from: 5, to: 4) == .slide)
        // Reopened at 1.
        #expect(GridLayout.move(from: 1, to: 2) == .hop)
        #expect(GridLayout.move(from: 2, to: 3) == .slide)
        #expect(GridLayout.move(from: nil, to: 1) == .arrive)
    }

    /// A slide never leaves its row, so it only ever moves sideways.
    @Test func aSlideStaysOnItsRow() {
        for from in 0..<12 {
            for to in [from - 1, from + 1] where to >= 0 && GridLayout.move(from: from, to: to) == .slide {
                #expect(layout.picture(from).minY == layout.picture(to).minY)
            }
        }
    }
}
