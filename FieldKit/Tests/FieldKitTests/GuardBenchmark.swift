import Foundation
import Testing
@testable import FieldKit

/// The guard runs in `decidePolicyFor` before every main-frame navigation
/// leaves, so it has to cost nothing next to the network: under 50 µs a
/// decision. Timed in a release build:
///
///     cd FieldKit && swift test -c release --filter GuardBenchmark
@Suite(.serialized, .enabled(if: optimised, "times only a release build"))
struct GuardBenchmark {
    static let budget = Duration.microseconds(50)

    /// A thousand navigations shaped like a day of browsing: mostly plain
    /// links, then search results, shims, tracking parameters, AMP, other
    /// apps and local addresses.
    static let navigations: [Navigation] = (0..<1_000).map { i in
        let shapes: [(String, String?, Navigation.Kind, Bool)] = [
            ("https://en.wikipedia.org/wiki/Page_\(i)", "https://en.wikipedia.org/wiki/Main_Page", .link, true),
            ("https://www.nytimes.com/2026/09/\(i % 28)/world/story-\(i).html", "https://www.nytimes.com/", .link, true),
            ("https://github.com/swiftlang/swift/pull/\(i)", "https://github.com/swiftlang/swift", .script, false),
            ("https://news.ycombinator.com/item?id=\(40_000_000 + i)", nil, .typed, false),
            ("https://www.google.com/url?sa=t&source=web&rct=j&url=https://site\(i).example.com/a&ved=2ahUKEwjX\(i)",
             "https://www.google.com/search?q=\(i)", .link, true),
            ("https://l.facebook.com/l.php?u=https%3A%2F%2Fwww.theguardian.com%2Fworld%2F\(i)%3Ffbclid%3DIwAR\(i)&h=AT0",
             "https://www.facebook.com/", .link, true),
            ("https://shop\(i % 50).example.co.uk/p/\(i)?color=red&utm_source=news&utm_medium=email&gclid=Cj0\(i)",
             "https://mail.example.net/", .link, true),
            ("https://www.youtube.com/watch?v=v\(i)&si=abc\(i)", "https://www.reddit.com/r/videos", .link, true),
            ("https://www.google.com/amp/s/www.bbc.co.uk/news/amp/world-\(i)", "https://www.google.com/search?q=bbc", .link, true),
            ("https://go.skimresources.com/?id=1X2&url=https%3A%2F%2Fwww.bestbuy.com%2Fsite%2F\(i).p", "https://www.wired.com/", .link, true),
            ("https://apps.apple.com/app/id\(i)", "https://free-prizes.example/", .script, false),
            ("mailto:user\(i)@example.com", "https://example.org/contact", .link, true),
            ("http://192.168.1.\(i % 250)/admin?fbclid=\(i)", nil, .typed, false),
            ("https://docs.swift.org/swift-book/\(i)?lang=en#section", "https://www.swift.org/", .link, true),
        ]
        let (url, source, kind, tapped) = shapes[i % shapes.count]
        return Navigation(url: URL(string: url)!, source: source.flatMap(URL.init(string:)), kind: kind, userTapped: tapped)
    }

    @Test func aDecisionFitsTheBudget() {
        let field = Guard(rules: .bundled)
        _ = Self.navigations.map { field.decide($0, shieldOn: true) }   // warm up
        let clock = ContinuousClock()
        var rewritten = 0
        var times: [Duration] = []
        for nav in Self.navigations {
            times.append(clock.measure {
                if case .rewrite = field.decide(nav, shieldOn: true) { rewritten += 1 }
            })
        }
        times.sort()
        let median = times[times.count / 2]
        print("Guard.decide over 1,000 navigations: median \(median), p99 \(times[times.count * 99 / 100]), max \(times.last!), \(rewritten) rewritten")
        #expect(median < Self.budget)
    }
}

#if DEBUG
private let optimised = false
#else
private let optimised = true
#endif
