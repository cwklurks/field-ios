import Foundation
import Testing
@testable import Field

/// A blank tab's first web view is built only once the field has been quiet
/// for a while, so the stall never lands between two keystrokes.
struct WarmUpTests {
    private let t0 = ContinuousClock.now
    private let quiet = WarmUp.quiet

    @Test func nothingIsDueBeforeTheFieldIsFocused() {
        let w = WarmUp()
        #expect(w.due == nil)
        #expect(!w.isDue(at: t0 + .seconds(60)))
    }

    @Test func dueOnceTheFieldHasBeenQuiet() {
        var w = WarmUp()
        w.focused(at: t0)
        #expect(!w.isDue(at: t0 + quiet - .milliseconds(1)))
        #expect(w.isDue(at: t0 + quiet))
    }

    /// Each keystroke starts the quiet over.
    @Test func typingPutsItOff() {
        var w = WarmUp()
        w.focused(at: t0)
        w.typed(at: t0 + .seconds(1))
        w.typed(at: t0 + .seconds(2))
        #expect(!w.isDue(at: t0 + .seconds(3)))
        #expect(w.isDue(at: t0 + .seconds(2) + quiet))
    }

    /// Typing somewhere else before the field was ever focused doesn't count.
    @Test func typingBeforeFocusSchedulesNothing() {
        var w = WarmUp()
        w.typed(at: t0)
        #expect(w.due == nil)
    }
}
