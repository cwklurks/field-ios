import Foundation

// An engine's answer, read with suspicion: it comes from outside. The shape
// is OpenSearch's, `["words asked", ["suggestion", …], …]`, and anything
// that isn't exactly that is no suggestions at all.
public enum SuggestResponse {
    /// Bigger than any honest answer to a few letters.
    static let largest = 64 * 1024
    /// A screenful, before the field takes its share.
    static let most = 10
    /// Longer than a row can show.
    static let longest = 200

    public static func words(from data: Data) -> [String] {
        guard data.count <= largest,
              let answer = try? JSONSerialization.jsonObject(with: data) as? [Any],
              answer.count >= 2, answer[0] is String,
              let list = answer[1] as? [Any]
        else { return [] }
        var seen: Set<String> = []
        var words: [String] = []
        for case let text as String in list {
            guard !text.contains(where: { $0.isNewline || $0.unicodeScalars.contains { $0.properties.generalCategory == .control } })
            else { continue }
            let tidy = Suggest.tidy(text)
            guard !tidy.isEmpty, tidy.count <= longest, seen.insert(tidy.lowercased()).inserted else { continue }
            words.append(tidy)
            if words.count == most { break }
        }
        return words
    }
}
