import Foundation
import Testing
@testable import FieldKit

/// Tidy runs when the user taps the button and must feel instant, so 200 tabs
/// group in under 50 ms, excluding embedding (which the app does on the
/// phone). Timed in a release build, where the number means something:
///
///     cd FieldKit && swift test -c release --filter TidyBenchmark
///
/// A debug build is several times slower and says nothing about the phone,
/// so there it is skipped.
@Suite(.serialized, .enabled(if: optimised, "times only a release build"))
struct TidyBenchmark {
    static let budget = Duration.milliseconds(50)

    /// Two hundred tabs shaped like a busy day: ten sites with four tabs
    /// each, then eight topics of twenty tabs spread across unique hosts. So
    /// the site pass makes ten groups and the clustering has to do the rest.
    static let tabs: [TabInfo] = makeTabs()

    /// One fixed sentence vector per embed text, so the embedding step is a
    /// lookup and the timing is all grouping.
    static let vectors: [String: [Double]] = makeVectors(for: TidyBenchmark.tabs)

    static let site: @Sendable (String) -> String = { host in
        let labels = host.split(separator: ".")
        return labels.count >= 2 ? labels.suffix(2).joined(separator: ".") : host
    }

    static let embed: @Sendable (String) -> [Double]? = { TidyBenchmark.vectors[$0] }

    @Test func twoHundredTabsFitTheBudget() {
        let tabs = Self.tabs
        _ = Tidy.suggest(tabs, embed: Self.embed, site: Self.site)   // warm up
        let clock = ContinuousClock()
        var groups = 0
        var times: [Duration] = []
        for _ in 0..<20 {
            times.append(clock.measure { groups = Tidy.suggest(tabs, embed: Self.embed, site: Self.site).count })
        }
        times.sort()
        let median = times[times.count / 2]
        print("Tidy.suggest over 200 tabs: median \(median), p99 \(times[times.count * 99 / 100]), "
            + "max \(times.last!), \(groups) groups")
        #expect(median < Self.budget)
    }

    // MARK: - fixtures

    private static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private static func makeTabs() -> [TabInfo] {
        (0..<200).map { i in
            if i < 40 {
                let site = "shared\(i / 4).com"
                return TabInfo(id: id(i), title: "Shared page \(i)", url: URL(string: "https://\(site)/p/\(i % 4)")!)
            }
            let topic = (i - 40) / 20
            return TabInfo(id: id(i), title: "Topic \(topic) item \(i)", url: URL(string: "https://site\(i).com/p")!)
        }
    }

    /// Each topic sits on its own block of the 512 axes, with a little noise.
    /// The forty site tabs never reach clustering, so any vector will do.
    private static func makeVectors(for tabs: [TabInfo]) -> [String: [Double]] {
        var generator = Seeded(state: 0x5EED_5EED)
        var table: [String: [Double]] = [:]
        for (i, tab) in tabs.enumerated() {
            let text = "\(tab.title) — \(tab.url.host()!)"
            var vector = [Double](repeating: 0, count: 512)
            let base = (i < 40) ? (i * 53) : ((i - 40) / 20 * 64)
            for k in 0..<8 {
                vector[(base + k * 7) % 512] = 1 + generator.symmetric() * 0.05
            }
            table[text] = vector
        }
        return table
    }
}

/// A deterministic stream, so the vectors are the same every run.
private struct Seeded {
    var state: UInt64

    mutating func symmetric() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 11) / Double(UInt64(1) << 53) * 2 - 1
    }
}

#if DEBUG
private let optimised = false
#else
private let optimised = true
#endif
