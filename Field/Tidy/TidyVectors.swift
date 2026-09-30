import FieldKit
import Foundation
import NaturalLanguage

/// The rules' sense of what a tab is about, when there's no language model:
/// the nouns of its title, with the site's name cut from the end, as the
/// average of their word vectors. Whole-title sentence vectors put
/// unrelated tabs together far too often: on two sets of realistic tabs,
/// 19% and 45% of the pairs they grouped were right, against 88% and 77%
/// for this, at the same cut (docs/integration/tidy.md, "The fallback").
/// A title with no noun the model knows has no vector, and stays loose.
nonisolated final class TidyVectors {
    private let words: NLEmbedding?
    private let sentences: NLEmbedding?
    private let tagger = NLTagger(tagSchemes: [.lexicalClass])

    init(language: NLLanguage) {
        words = NLEmbedding.wordEmbedding(for: language)
        // Only when there's no word model for the language.
        sentences = words == nil ? NLEmbedding.sentenceEmbedding(for: language) : nil
    }

    /// There's a model for the language at all.
    var usable: Bool { words != nil || sentences != nil }

    /// Takes "title — host", as FieldKit's rules hand it over, or a title.
    func vector(_ text: String) -> [Double]? {
        let topic = Self.topic(of: text)
        guard let words else { return sentences?.vector(for: topic) }
        var sum: [Double]?
        var count = 0
        for noun in nouns(topic) {
            guard let v = words.vector(for: noun) else { continue }
            if sum == nil { sum = [Double](repeating: 0, count: v.count) }
            for i in v.indices { sum![i] += v[i] }
            count += 1
        }
        guard let sum, count > 0 else { return nil }
        return sum.map { $0 / Double(count) }
    }

    private func nouns(_ text: String) -> [String] {
        tagger.string = text
        var found: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            let word = text[range].lowercased()
            if tag == .noun || tag == .otherWord, word.count >= 3, word.allSatisfy(\.isLetter),
               !Self.generic.contains(word) {
                found.append(word)
            }
            return true
        }
        return found
    }

    /// Words in titles that say nothing about the topic.
    private static let generic: Set<String> = [
        "review", "reviews", "tips", "guide", "best", "home", "page", "official", "site",
        "news", "video", "videos", "update", "report", "gen", "edition", "one", "inbox",
    ]

    /// The title without the " — host" FieldKit's rules add, or the site's
    /// own name after its last " | ", " - " and the like, unless too little
    /// would be left to say anything.
    static func topic(of text: String) -> String {
        var title = text
        if let host = title.range(of: " — ", options: .backwards) { title = String(title[..<host.lowerBound]) }
        for separator in [" | ", " - ", " – ", " · ", " : r/", ": r/"] {
            guard let cut = title.range(of: separator, options: .backwards),
                  title.distance(from: title.startIndex, to: cut.lowerBound) > 12 else { continue }
            title = String(title[..<cut.lowerBound])
        }
        return title
    }
}
