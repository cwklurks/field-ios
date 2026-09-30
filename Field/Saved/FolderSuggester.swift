import FieldKit
import Foundation
import NaturalLanguage

/// The save sheet's suggested folder: FieldKit's FolderGuess, with Apple's
/// on-device sentence vectors for meaning. Nothing leaves the phone and
/// nothing is downloaded. Runs off the main thread, keeps every vector it
/// has worked out, and has only the site to go on for a title in a language
/// the phone has no sentence model for, or none yet.
actor FolderSuggester {
    nonisolated static let shared = FolderSuggester()

    private var models: [NLLanguage: NLEmbedding] = [:]
    /// When each model was last asked for and wasn't there.
    private var missing: [NLLanguage: ContinuousClock.Instant] = [:]
    private var vectors: [String: [Double]] = [:]
    /// How long a missing model is left before it's asked for again.
    private let retry: Duration
    private let load: @Sendable (NLLanguage) -> NLEmbedding?

    /// Both are there for the tests.
    init(retry: Duration = .seconds(2),
         load: @escaping @Sendable (NLLanguage) -> NLEmbedding? = { NLEmbedding.sentenceEmbedding(for: $0) }) {
        self.retry = retry
        self.load = load
    }

    func folder(for url: URL, title: String, in saved: Saved) -> String? {
        let language = Self.language(of: title)
        return FolderGuess.folder(for: url, title: title, in: saved) { text in
            vector(text, language)
        }
    }

    /// Loads the model and works out the vectors for what's saved now, so
    /// the first suggestion is as quick as the rest. For a quiet moment.
    func warm(_ saved: Saved) {
        _ = FolderGuess.folder(for: URL(string: "https://warm.invalid")!, title: "warm", in: saved) { text in
            vector(text, .english)
        }
    }

    private func vector(_ text: String, _ language: NLLanguage) -> [Double]? {
        let key = language.rawValue + "\u{1F}" + text
        if let known = vectors[key] { return known }
        guard !text.isEmpty, let model = model(language), let found = model.vector(for: text) else { return nil }
        vectors[key] = found
        return found
    }

    private func model(_ language: NLLanguage) -> NLEmbedding? {
        if let model = models[language] { return model }
        // Not there isn't never there: the first ask can come back empty
        // while the system is still getting it ready.
        if let since = missing[language], ContinuousClock.now < since + retry { return nil }
        guard let model = load(language) else {
            missing[language] = .now
            return nil
        }
        models[language] = model
        return model
    }

    /// The title's language, or English when it's too short to tell.
    private static func language(of title: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(title)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              confidence > 0.6 else { return .english }
        return language
    }
}
