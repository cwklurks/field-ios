import Testing
import UIKit
@testable import Field

/// The glass changing tone under a page that turned light or dark: the old
/// glass goes in the same animation as the new one comes, rather than in a
/// frame, which cut a dark pill to grey before the light one came in.
/// Outside an animation (Private, from its first frame) it's replaced at
/// once.
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
    @Test func anImmediateToneChangeRemovesAllLeavingGlass() {
        let background = SurfaceBackground()
        background.tone = .dark
        UIView.animate(withDuration: 0.3) { background.tone = .light }
        UIView.performWithoutAnimation { background.tone = .dark }
        #expect(glasses(background) == 1)
    }

    @Test func leavingGlassFollowsTheMorphsCorners() throws {
        let background = SurfaceBackground()
        background.radius = 17
        background.tone = .dark
        UIView.animate(withDuration: 0.3) { background.tone = .light }
        let old = try #require(background.subviews.first { $0.tag == SurfaceBackground.leaving })
        background.radius = 12
        #expect(old.cornerConfiguration == .corners(radius: .fixed(12)))
    }

    @Test func privateCanFinishAnAlreadyDarkToneFadeImmediately() {
        let background = SurfaceBackground()
        background.tone = .light
        UIView.animate(withDuration: 0.3) { background.tone = .dark }
        UIView.performWithoutAnimation { background.tone = .dark }
        #expect(glasses(background) == 1)
    }

}
