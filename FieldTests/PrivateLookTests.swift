import Testing
import UIKit
@testable import Field

/// The way in and out: the strip follows the finger 1:1, lands where the
/// throw was going, and the switch's lift sits wherever the strip is.
@Suite(.serialized)
@MainActor struct PrivateLookTests {
    func strip() -> PrivateStrip {
        let strip = PrivateStrip(everyday: UIView())
        strip.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        strip.hold(UIView())
        strip.layoutIfNeeded()
        return strip
    }

    func landing(_ strip: PrivateStrip, _ start: () -> Void) async -> Bool? {
        await withCheckedContinuation { done in
            strip.landed = { done.resume(returning: $0) }
            start()
        }
    }

    @Test func followsTheFinger() {
        let strip = strip()
        var seen: [CGFloat] = []
        strip.alongside = { seen.append($0) }
        strip.track(-208)
        #expect(abs(strip.progress - 0.5) < 0.001)
        #expect(strip.everyday.transform.tx == -208)
        #expect(strip.inside?.transform.tx == 208)
        #expect(seen.last == strip.progress)
        #expect(strip.inside?.overrideUserInterfaceStyle == .dark)
    }

    @Test func aThrowLandsWhereItWasGoing() async {
        let strip = strip()
        strip.track(-60)
        // Slow and short: back to your tabs.
        #expect(await landing(strip) { strip.release(velocity: 0) } == false)
        strip.track(-60)
        // Short but fast: into Private.
        #expect(await landing(strip) { strip.release(velocity: -1600) } == true)
        #expect(strip.progress == 1)
    }

    @Test func aTapSlidesAndCanTurnMidway() async {
        let strip = strip()
        strip.slide(toPrivate: true)
        #expect(await landing(strip) { strip.slide(toPrivate: false) } == false)
        #expect(strip.progress == 0)
    }

    @Test func switchLiftFollowsProgress() {
        let control = PrivateSwitch(frame: CGRect(x: 0, y: 0, width: 150, height: 44))
        control.count = 3
        control.layoutIfNeeded()
        let lift = control.subviews[1]
        let start = lift.frame
        #expect(control.wantsPrivate)
        control.progress = 1
        control.layoutIfNeeded()
        #expect(lift.frame.maxX > start.maxX)
        #expect(!control.wantsPrivate)
        #expect(lift.frame.width < start.width)
    }
}
