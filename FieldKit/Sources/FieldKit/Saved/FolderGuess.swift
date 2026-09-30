import Foundation

/// The folder a page being saved probably belongs in, offered in the save
/// sheet. The site first: a folder already holding pages from it. Then
/// meaning: the folder whose pages (and name) read most like the title, by
/// sentence vectors the app supplies (NLEmbedding, on the phone). Only a
/// clear winner counts; otherwise no folder, rather than the least bad one.
public enum FolderGuess {
    /// Measured on NLEmbedding's English sentence vectors of titles, over 30
    /// pages and up to five folders (SavedSuggestTests): a page and its
    /// folder scored 0.57 to 0.73 when the model saw the link at all, and a
    /// page belonging nowhere still reached 0.56 with its nearest folder, but
    /// led the next one by 0.22 at most. The model is weak, so this is picky:
    /// it takes a clear case and leaves the rest to the site.
    static let close = 0.55
    static let clear = 0.25
    /// How many of a folder's pages speak for it, newest first: a sentence
    /// vector costs a few milliseconds on a phone.
    static let newest = 12

    public static func folder(for url: URL, title: String, in saved: Saved,
                              vector: (String) -> [Double]?) -> String? {
        guard !saved.folders.isEmpty else { return nil }
        let host = url.host()?.lowercased().replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) ?? ""
        let filed = saved.pages.filter { $0.folder != nil && Saved.key($0.url) != Saved.key(url) }

        let sameSite = filed.filter { $0.host == host }
        if !sameSite.isEmpty {
            let counts = Dictionary(grouping: sameSite, by: { $0.folder! }).mapValues(\.count)
            return counts.max { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }?.key
        }

        guard let wanted = vector(title) else { return nil }
        var scores: [(folder: String, score: Double)] = []
        for folder in saved.folders {
            let vectors = ([folder] + filed.lazy.filter { $0.folder == folder }.prefix(newest).map(\.title)).compactMap(vector)
            guard let middle = mean(vectors) else { continue }
            scores.append((folder, similarity(wanted, middle)))
        }
        let ranked = scores.sorted { $0.score > $1.score }
        guard let best = ranked.first, best.score >= close,
              ranked.count < 2 || best.score - ranked[1].score >= clear else { return nil }
        return best.folder
    }

    /// Cosine similarity; nothing is like a zero vector.
    static func similarity(_ one: [Double], _ other: [Double]) -> Double {
        var dot = 0.0, a = 0.0, b = 0.0
        for i in 0..<min(one.count, other.count) {
            dot += one[i] * other[i]
            a += one[i] * one[i]
            b += other[i] * other[i]
        }
        guard a > 0, b > 0 else { return 0 }
        return dot / (a.squareRoot() * b.squareRoot())
    }

    private static func mean(_ vectors: [[Double]]) -> [Double]? {
        guard let first = vectors.first else { return nil }
        var sum = [Double](repeating: 0, count: first.count)
        for vector in vectors where vector.count == sum.count {
            for i in sum.indices { sum[i] += vector[i] }
        }
        return sum.map { $0 / Double(vectors.count) }
    }
}
