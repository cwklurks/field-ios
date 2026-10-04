import Foundation

// The searches you made from the field, so it can offer them again. Kept on
// the phone like history and never sent anywhere. Only what was asked from
// the field is here: a search typed into the engine's own page is that
// page's business. Never written in Private, which keeps nothing.

public struct Searches: Equatable, Sendable {
    struct Asked: Codable, Equatable, Sendable {
        /// As last typed, tidied.
        var words: String
        var count: Int
        var last: Date
    }

    /// By the words, small letters, one space apart: "Swift  Concurrency"
    /// and "swift concurrency" are one search.
    var asked: [String: Asked] = [:]

    /// What the file keeps at most; what goes is asked least and longest ago.
    public static let cap = 500

    public init() {}

    public var isEmpty: Bool { asked.isEmpty }
    public var count: Int { asked.count }

    // MARK: - writing

    /// Anything that reads as an address or a secret is not kept, by the
    /// same rule that keeps it from being sent (Suggest).
    public mutating func record(_ typed: String, now: Date = .now) {
        let words = Suggest.tidy(typed)
        guard Suggest.mayLeave(words) else { return }
        let key = words.lowercased()
        var seen = asked[key] ?? Asked(words: words, count: 0, last: now)
        seen.words = words
        seen.count += 1
        seen.last = now
        asked[key] = seen
    }

    public mutating func forget(_ words: String) {
        asked[Suggest.tidy(words).lowercased()] = nil
    }

    public mutating func forget() {
        asked = [:]
    }

    // MARK: - reading

    /// Searches that carry on from what was typed, best first: from their
    /// start before from a later word, then often and lately. A later word
    /// matches from two letters, never from the middle of a word, and what
    /// was typed exactly is not offered back. Each goes to the engine
    /// chosen now, by `template`.
    public func suggestions(for typed: String, template: String, limit: Int = 3, now: Date = .now) -> [Suggestion] {
        let needle = Suggest.tidy(typed).lowercased()
        guard !needle.isEmpty else { return [] }
        var scored: [(asked: Asked, start: Bool, score: Double)] = []
        for (key, search) in asked where key != needle {
            if key.hasPrefix(needle) {
                scored.append((search, true, frecency(search, now: now)))
            } else if needle.count >= 2, key.contains(" " + needle) {
                scored.append((search, false, frecency(search, now: now)))
            }
        }
        return scored
            .sorted {
                if $0.start != $1.start { return $0.start }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.asked.words.count < $1.asked.words.count
            }
            .prefix(limit)
            .compactMap { item in
                Engine.url(for: item.asked.words, template: template).map {
                    Suggestion(key: item.asked.words, title: "", url: $0, kind: .searched)
                }
            }
    }

    /// As history counts it: a month-old search is worth about a third of a
    /// fresh one.
    private func frecency(_ search: Asked, now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(search.last) / 86_400)
        return Double(search.count) * exp(-days / 30)
    }

    // MARK: - the file

    /// As History's: no file is none, a file that isn't one is set aside,
    /// and anything else that stops the read throws, so the app doesn't
    /// write an empty list over a full one.
    public static func load(from file: URL) throws -> Searches {
        var searches = Searches()
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return searches
        }
        guard let list = try? JSONDecoder().decode([Asked].self, from: data) else {
            Store.quarantine(file)
            return searches
        }
        searches.asked = Dictionary(list.map { ($0.words.lowercased(), $0) }) { one, other in
            one.last >= other.last ? one : other
        }
        return searches
    }

    public func save(to file: URL, now: Date = .now) throws {
        let list = asked.values
            .sorted { frecency($0, now: now) > frecency($1, now: now) }
            .prefix(Self.cap)
            .map { $0 }
        let data = try JSONEncoder().encode(list)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
