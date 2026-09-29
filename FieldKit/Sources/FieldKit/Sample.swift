import Foundation

extension History {
    /// A made-up history of exactly `count` places, shaped like a year of
    /// someone's browsing: a few sites visited constantly and deeply, a long
    /// tail seen once or twice, and the weather. The same every time, so
    /// ranking can be timed against something realistic: FieldKit's benchmark,
    /// and the app's `-FieldSeedHistory` for the perf tests.
    public static func sample(_ count: Int, now: Date) -> History {
        var history = History()
        var dice = Dice(seed: 2026)

        // Somewhere to type toward, visited every day this week.
        let weather = [
            ("https://weather.com/", "The Weather Channel"),
            ("https://www.weather.gov/", "National Weather Service"),
            ("https://weather.example/forecast/today", "Today's forecast"),
        ]
        for (address, title) in weather {
            let url = URL(string: address)!
            // A page deeper than the front one brings its front page with it.
            guard count - history.visits.count >= (url.path() == "/" ? 1 : 2) else { break }
            for day in 0..<5 {
                history.record(url, title: title, now: now.addingTimeInterval(-Double(day) * 86_400))
            }
        }

        let big = [
            "github.com", "en.wikipedia.org", "news.ycombinator.com", "developer.apple.com",
            "stackoverflow.com", "www.youtube.com", "www.reddit.com", "docs.google.com",
            "mail.google.com", "x.com", "www.nytimes.com", "forums.swift.org",
            "www.amazon.com", "maps.google.com", "linear.app", "www.figma.com",
        ]
        let words = ["swift", "concurrency", "actor", "layout", "design", "notes", "release", "profile",
                     "issue", "pull", "wiki", "search", "account", "settings", "article", "video"]
        let endings = [".com", ".org", ".io", ".dev", ".co.uk", ".fr", ".net", ".app"]
        let tail = (0..<260).map { i in
            (dice.roll(3) == 0 ? "www." : "") + words[dice.roll(words.count)] + "\(i)" + endings[dice.roll(endings.count)]
        }

        while history.visits.count < count {
            // With room for one more, a new page on a site already there,
            // which adds only itself.
            let last = count - history.visits.count == 1
            let host = last ? "weather.com" : dice.roll(3) == 0 ? big[dice.roll(big.count)] : tail[dice.roll(tail.count)]
            let depth = last ? 1 + dice.roll(3) : dice.roll(4)
            let path = (0..<depth).map { _ in words[dice.roll(words.count)] + "\(dice.roll(40))" }.joined(separator: "/")
            let when = now.addingTimeInterval(-Double(dice.roll(365 * 86_400)))
            history.record(URL(string: "https://\(host)/\(path)")!, title: "A page about \(path)", now: when)
        }
        return history
    }
}

/// The same numbers every run.
struct Dice {
    var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func roll(_ sides: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(sides))
    }
}
