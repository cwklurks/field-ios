import Foundation
import Testing
@testable import FieldKit

// History's ranking is tuned for speed. This keeps it honest: the Mac's
// ranking, written out as it was, must give the same list for anything
// typed, over the same two thousand places plus a few whose keys aren't
// plain ASCII.
struct RankingReferenceTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var history: History {
        var history = HistoryBenchmark.history
        // Keys a hand-edited file could hold; nothing Field writes looks
        // like this, which is the point.
        for key in ["café.fr/é", "e\u{301}xample.com", "cr\r\nlf.com/a", "κόσμος.gr", "semi;colon.com/a;b", "x/\u{338}y.com"] {
            history.visits[key] = Visit(url: "https://example.com/", key: key, title: key, count: 3, last: now)
        }
        return history
    }

    var typed: [String] {
        var typed = ["", " ", "g", "gi", "git", "github.com/", "wiki", "co", "e", "news.y", "zzz", ".", "/", "-",
                     "HTTPS://WWW.GitHub", "www.", "é", "e", "café", "caf", "κό", "\u{212A}", "\u{037E}", "semi\u{037E}",
                     "cr\r", "cr\r\n", "x/", "x/\u{338}", "e\u{301}", "ex"]
        // The start of every hundredth key, and a stretch from inside it.
        for (i, key) in history.visits.keys.sorted().enumerated() where i % 100 == 0 {
            let characters = Array(key)
            for length in 1...min(3, characters.count) { typed.append(String(characters.prefix(length))) }
            if characters.count > 6 { typed.append(String(characters[2..<6])) }
        }
        return typed
    }

    @Test func theSameListAsTheMacsRanking() {
        let history = history
        for text in typed {
            for limit in [5, 60] {
                let fast = history.suggestions(for: text, limit: limit, now: now)
                let reference = Self.reference(history, text, limit: limit, now: now)
                #expect(fast == reference, "\(text.debugDescription), limit \(limit)")
            }
        }
    }

    // MARK: - the Mac's ranking, as it was

    static func reference(_ history: History, _ typed: String, limit: Int, now: Date) -> [Suggestion] {
        var text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        let needle = text
        guard !needle.isEmpty else { return [] }

        func rank(_ key: String) -> Double? {
            if key.hasPrefix(needle) { return 6 }
            let host = key[..<(key.firstIndex(of: "/") ?? key.endIndex)]
            if let dot = host.firstIndex(of: "."), host[host.index(after: dot)...].hasPrefix(needle) { return 3 }
            if needle.count >= 2, host.contains(needle) { return 2 }
            return nil
        }

        var scored: [(Suggestion, Double)] = []
        for visit in history.visits.values {
            guard let rank = rank(visit.key) else { continue }
            guard let url = URL(string: visit.url) else { continue }
            let days = max(0, now.timeIntervalSince(visit.last) / 86_400)
            scored.append((
                Suggestion(key: visit.key, title: visit.title, url: url, kind: .visited),
                rank + 4 + Double(visit.count) * exp(-days / 30) + (visit.key.contains("/") ? 0 : 1.5)
            ))
        }
        for known in History.known where history.visits[known.0] == nil {
            guard let rank = rank(known.0) else { continue }
            guard let url = URL(string: "https://" + known.0) else { continue }
            scored.append((Suggestion(key: known.0, title: known.1, url: url, kind: .known), rank))
        }
        return scored
            .sorted { $0.1 == $1.1 ? $0.0.key.count < $1.0.key.count : $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
