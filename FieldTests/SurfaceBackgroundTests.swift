import Testing
import UIKit
@testable import Field

/// The glass changing tone under a page that turned light or dark: the old
/// glass goes in the same animation as the new one comes, rather than in a
/// frame, which cut a dark pill to grey before the light one came in
/// (bar-polish B-04). Outside an animation (Private, from its first frame)
/// it's replaced at once.
@MainActor struct SurfaceBackgroundTests {
    private func glasses(_ view: UIView) -> Int {
        view.subviews.filter { ($0 as? UIVisualEffectView)?.effect is UIGlassEffect || $0.tag == SurfaceBackground.leaving }.count
    }

    @Test func inAnAnimationTheOldGlassStaysToGo() {
        let background = SurfaceBackground()
        background.tone = .dark
        UIView.animate(withDuration: 0.3) { background.tone = .light }
        #expect(glasses(background) == 2)
    }

    @Test func outsideOneItsReplacedAtOnce() {
        let background = SurfaceBackground()
        background.tone = .dark
        background.tone = .light
        #expect(glasses(background) == 1)
    }
}
