import CoreGraphics

/// Where the screenshot editor's "Full Page" opens: the part of the page
/// that was on screen, found in the PDF as UIScreenshotService wants it.
nonisolated enum ScreenshotPlace {
    /// `visible` is in the scroll view's content coordinates, whose width is
    /// `contentWidth` (zoom included); `pages` are the PDF's, top to bottom.
    /// The page that holds most of what was visible, and the visible part
    /// of it in PDF coordinates, whose origin is the page's bottom left.
    /// Nothing to place gives page 0 and a zero rect, which the service
    /// takes as "unknown".
    static func locate(visible: CGRect, contentWidth: CGFloat, pages: [CGSize]) -> (index: Int, rect: CGRect) {
        guard let first = pages.first, contentWidth > 0, first.width > 0 else { return (0, .zero) }
        let ratio = first.width / contentWidth
        let seen = CGRect(x: visible.minX * ratio, y: visible.minY * ratio,
                          width: visible.width * ratio, height: visible.height * ratio)
        var best: (index: Int, rect: CGRect)?
        var top: CGFloat = 0
        for (index, page) in pages.enumerated() {
            let onPage = CGRect(x: 0, y: top, width: page.width, height: page.height).intersection(seen)
            if !onPage.isNull, onPage.height > (best?.rect.height ?? 0) {
                let flipped = CGRect(x: onPage.minX, y: top + page.height - onPage.maxY,
                                     width: onPage.width, height: onPage.height)
                best = (index, flipped)
            }
            top += page.height
        }
        return best ?? (0, .zero)
    }
}
