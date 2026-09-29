import Foundation
import Testing
@testable import FieldKit

/// The "Smooth" budget (docs/PLAN.md): suggestions arrive in the keystroke's
/// own frame, so ranking 2,000 places takes under 2 ms. Timed in a release
/// build, where the number means something:
///
///     cd FieldKit && swift test -c release --filter HistoryBenchmark
///
/// A debug build is several times slower and says nothing about the phone,
/// so there it is skipped.
@Suite(.serialized, .enabled(if: optimised, "times only a release build"))
struct HistoryBenchmark {
    static let budget = Duration.milliseconds(2)

    /// Two thousand made-up places, shaped like a year of browsing.
    static let history = History.sample(2_000, now: Date(timeIntervalSinceReferenceDate: 800_000_000))

    /// What people type: one letter, a few, a whole host and into its path,
    /// "co" (inside nearly every .com), and something nothing matches.
    @Test(arguments: ["g", "gi", "git", "github.com/", "wiki", "co", "e", "news.y", "developer.apple.com/sw", "zzz"])
    func rankingTwoThousandPlacesFitsInAFrame(typed: String) {
        let history = Self.history
        #expect(history.visits.count == 2_000)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let clock = ContinuousClock()
        var found = 0
        var times: [Duration] = []
        for _ in 0..<50 {
            times.append(clock.measure { found += history.suggestions(for: typed, now: now).count })
        }
        let median = times.sorted()[times.count / 2]
        print("suggestions(for: \"\(typed)\") over 2,000 places: median \(median) of 50, \(found / 50) found")
        #expect(median < Self.budget, "\(median) for \"\(typed)\"")
    }
}

#if DEBUG
private let optimised = false
#else
private let optimised = true
#endif
