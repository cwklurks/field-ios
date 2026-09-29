import SwiftUI
import WebKit

/// The page: the tab's web view, put in place once and never rebuilt by
/// SwiftUI. Its scrolling drives the bar's shrink straight from UIKit.
struct PageView: UIViewRepresentable {
    let tab: Tab
    let bar: BarState

    func makeCoordinator() -> Scroller {
        Scroller(bar: bar)
    }

    func makeUIView(context: Context) -> PageHost {
        PageHost()
    }

    func updateUIView(_ host: PageHost, context: Context) {
        guard let web = tab.web, web.superview !== host else { return }
        web.scrollView.delegate = context.coordinator
        host.hold(web)
    }
}

/// Holds the web view edge to edge, and tells it what the status bar and the
/// bar cover so the page starts below one and its fixed and sticky parts stay
/// clear of the other.
final class PageHost: UIView {
    private var web: WKWebView?

    func hold(_ web: WKWebView) {
        self.web?.removeFromSuperview()
        self.web = web
        // What scrolls under the status bar blurs away rather than running
        // into the time and battery.
        web.scrollView.topEdgeEffect.style = .soft
        addSubview(web)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let web else { return }
        web.frame = bounds
        let covered = UIEdgeInsets(top: safeAreaInsets.top, left: 0, bottom: safeAreaInsets.bottom + Bar.clearance, right: 0)
        if web.obscuredContentInsets != covered {
            web.obscuredContentInsets = covered
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }
}

/// Turns the page's scrolling into the bar's shrink, here in UIKit, so that
/// nothing but the bar hears about it.
final class Scroller: NSObject, UIScrollViewDelegate {
    private let bar: BarState
    private var dragging = false
    private var last: CGFloat = 0

    init(bar: BarState) {
        self.bar = bar
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        dragging = true
        last = position(scrollView)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let now = position(scrollView)
        defer { last = now }
        if dragging {
            bar.track(from: last, to: now, limit: limit(scrollView))
        } else if now <= 0 {
            // Coasting, or sent there by the page: the top shows the whole bar.
            bar.expand()
        }
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView,
        withVelocity velocity: CGPoint,
        targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        dragging = false
        // UIKit's velocity is in points a millisecond.
        let landing = targetContentOffset.pointee.y + scrollView.adjustedContentInset.top
        bar.release(velocity: velocity.y * 1000, landing: landing)
    }

    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        bar.expand()
        return true
    }

    /// How far down the page, 0 at its top.
    private func position(_ scrollView: UIScrollView) -> CGFloat {
        scrollView.contentOffset.y + scrollView.adjustedContentInset.top
    }

    /// The furthest down the page goes.
    private func limit(_ scrollView: UIScrollView) -> CGFloat {
        let insets = scrollView.adjustedContentInset
        return scrollView.contentSize.height + insets.top + insets.bottom - scrollView.bounds.height
    }
}
