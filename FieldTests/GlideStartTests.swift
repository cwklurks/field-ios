import Foundation
import Testing
@testable import Field

/// A glide from rest, some time in: how far along it is, and how fast it's
/// going as UIKit's springs take a speed (a share of the distance left, each
/// second). The grid starts its shrink one frame in, so the first frame after
/// the tap already moves (Core Animation draws a new animation's first frame
/// where it starts).
struct GlideStartTests {
    @Test func atRestItHasNotMoved() {
        let start = Stage.glide(after: 0)
        #expect(start.progress == 0)
        #expect(start.velocity == 0)
    }

    @Test func oneFrameInItHasVisiblyMoved() {
        let frame = Stage.glide(after: 1.0 / 60)
        #expect(frame.progress > 0.02 && frame.progress < 0.08)
        #expect(frame.velocity > 0)
    }

    @Test func itSettlesWhereItWasGoing() {
        #expect(abs(Stage.glide(after: 1).progress - 1) < 0.01)
    }

    /// Picked up from there, it carries on as if it had never stopped.
    @Test func theSpeedIsTheCurvesOwn() {
        let t = 1.0 / 60, h = 1e-5
        let slope = (Stage.glide(after: t + h).progress - Stage.glide(after: t - h).progress) / (2 * h)
        let here = Stage.glide(after: t)
        #expect(abs(here.velocity - slope / (1 - here.progress)) < 0.01)
    }
}
