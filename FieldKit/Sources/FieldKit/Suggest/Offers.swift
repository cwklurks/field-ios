import Foundation

// The rows, put together. Nearest the field: places you have been and
// searches you made, which are known at the keystroke. Beyond them: the
// engine's suggestions, which arrive late, so they stand where their
// arrival moves nothing that was already there.
public enum Offers {
    /// Rows from the phone.
    public static let nearLimit = 5
    /// Rows from the engine.
    public static let farLimit = 4
    /// Rows in all, so the panel still fits over the keyboard.
    public static let allLimit = 8

    /// Places and past searches in one list, best first. A place you have
    /// been that starts with what was typed comes first, so it is what the
    /// field finishes inline; then a past search that starts so, which beats
    /// a place the app merely knows the name of; then the other places, in
    /// history's order; then searches matched on a later word.
    public static func merge(places: [Suggestion], searches: [Suggestion], typed: String) -> [Suggestion] {
        let needle = bare(typed)
        let words = Suggest.tidy(typed).lowercased()
        let ahead = places.filter { $0.kind != .known && !needle.isEmpty && $0.key.hasPrefix(needle) }
        let asked = searches.filter { !words.isEmpty && $0.key.lowercased().hasPrefix(words) }
        let taken = Set((ahead + asked).map(\.id))
        let rest = places.filter { !taken.contains($0.id) } + searches.filter { !taken.contains($0.id) }
        var seen: Set<String> = []
        return (ahead + asked + rest).filter { seen.insert($0.id).inserted }.prefix(nearLimit).map { $0 }
    }

    /// The rest of the first row that carries on from what was typed, for
    /// the field to draw after the caret, or nil. Never one of the engine's:
    /// those arrive after the keystroke they would finish. A search keeps
    /// its capitals ("swi" finishes as "swiftUI").
    public static func completion(for typed: String, among options: [Suggestion]) -> (ending: String, suggestion: Suggestion)? {
        let lower = typed.lowercased()
        guard !lower.isEmpty else { return nil }
        for option in options where option.kind != .search {
            let folded = option.key.lowercased()
            guard folded.hasPrefix(lower), folded.count > lower.count else { continue }
            // Where lowering changes the length, the lowered ending is the one
            // that lines up.
            let source = folded.count == option.key.count ? option.key : folded
            return (String(source.dropFirst(lower.count)), option)
        }
        return nil
    }

    /// The engine's words as rows: searches with this engine, none that
    /// repeats what was typed or a search already offered nearer the field,
    /// none that is an address or a secret, and only as many as there is
    /// room for.
    public static func remote(_ words: [String], typed: String, near: [Suggestion], template: String) -> [Suggestion] {
        var seen = Set(near.map(\.id))
        seen.insert("?" + Suggest.tidy(typed).lowercased())
        var rows: [Suggestion] = []
        for text in words where rows.count < room(near) {
            guard Suggest.mayLeave(text), let url = Engine.url(for: text, template: template) else { continue }
            let row = Suggestion(key: text, title: "", url: url, kind: .search)
            if seen.insert(row.id).inserted { rows.append(row) }
        }
        return rows
    }

    private static func room(_ near: [Suggestion]) -> Int {
        max(0, min(farLimit, allLimit - near.count))
    }

    /// As history reads what was typed: small letters, no scheme, no www.
    private static func bare(_ typed: String) -> String {
        var text = typed.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) {
            text = String(text.dropFirst(scheme.count))
        }
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        return text
    }
}
