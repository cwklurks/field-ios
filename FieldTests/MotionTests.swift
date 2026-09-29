import SwiftUI
import Testing
@testable import Field

/// The three curves, as Search's Design.swift has them.
struct MotionTests {
    @Test func curvesAreTheMacs() {
        #expect(Motion.glide == .spring(response: 0.34, dampingFraction: 0.82))
        #expect(Motion.settle == .spring(response: 0.30, dampingFraction: 0.86))
        #expect(Motion.quick == .easeOut(duration: 0.14))
    }

    /// Animation's equality has to look at the numbers for the test above to
    /// mean anything.
    @Test func equalityComparesTheNumbers() {
        #expect(Motion.glide != .spring(response: 0.34, dampingFraction: 0.80))
        #expect(Motion.quick != .easeOut(duration: 0.15))
        #expect(Motion.glide != Motion.settle)
    }
}
