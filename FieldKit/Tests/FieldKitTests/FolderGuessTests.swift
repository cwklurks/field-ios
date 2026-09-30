import Foundation
import Testing
@testable import FieldKit

/// Which folder a page being saved probably belongs in: the one already
/// holding its site, else the one whose pages read most like it, else none.
struct FolderGuessTests {
    func url(_ text: String) -> URL { URL(string: text)! }
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Three directions stand in for meanings.
    let meanings: [String: [Double]] = [
        "food": [1, 0, 0], "travel": [0, 1, 0], "code": [0, 0, 1],
        "Recipes": [1, 0.1, 0], "Trips": [0, 1, 0.1], "Work": [0.1, 0, 1],
    ]

    func vector(_ text: String) -> [Double]? {
        meanings.first { text.lowercased().contains($0.key.lowercased()) }?.value
    }

    func library() -> Saved {
        var saved = Saved()
        saved.save(url("https://cooking.example/pasta"), title: "food pasta", folder: "Recipes", now: now)
        saved.save(url("https://cooking.example/soup"), title: "food soup", folder: "Recipes", now: now)
        saved.save(url("https://flights.example/lisbon"), title: "travel lisbon", folder: "Trips", now: now)
        saved.save(url("https://docs.example/swift"), title: "code swift", folder: "Work", now: now)
        saved.save(url("https://news.example/today"), title: "code news", now: now)
        return saved
    }

    @Test func theFolderAlreadyHoldingTheSiteWins() {
        let guess = FolderGuess.folder(for: url("https://www.flights.example/porto"), title: "food porto", in: library(), vector: vector)
        #expect(guess == "Trips")
    }

    @Test func otherwiseTheFolderThatReadsMostLikeIt() {
        let guess = FolderGuess.folder(for: url("https://elsewhere.example/cake"), title: "food cake", in: library(), vector: vector)
        #expect(guess == "Recipes")
    }

    /// A page that is like nothing in particular gets no folder, not the
    /// least bad one.
    @Test func nothingCloseEnoughIsNoFolder() {
        let guess = FolderGuess.folder(for: url("https://elsewhere.example/x"), title: "something", in: library()) { _ in [0.6, 0.6, 0.5] }
        #expect(guess == nil)
    }

    /// Without the language's model there's only the site to go on.
    @Test func noVectorsIsTheSiteOrNothing() {
        #expect(FolderGuess.folder(for: url("https://elsewhere.example/cake"), title: "food cake", in: library()) { _ in nil } == nil)
        #expect(FolderGuess.folder(for: url("https://docs.example/rust"), title: "code rust", in: library()) { _ in nil } == "Work")
    }

    @Test func noFoldersIsNoGuess() {
        var saved = Saved()
        saved.save(url("https://cooking.example/pasta"), title: "food pasta", now: now)
        #expect(FolderGuess.folder(for: url("https://cooking.example/cake"), title: "food cake", in: saved, vector: vector) == nil)
    }

    /// A sentence vector costs a few milliseconds on a phone, so a folder is
    /// read from its newest dozen pages and its name, however full it is.
    @Test func aFolderIsReadFromItsNewestPages() {
        var saved = Saved()
        for i in 0..<50 {
            saved.save(url("https://cooking.example/\(i)"), title: "food \(i)", folder: "Recipes", now: now + Double(i))
        }
        var asked: [String] = []
        let guess = FolderGuess.folder(for: url("https://elsewhere.example/cake"), title: "food cake", in: saved) { text in
            asked.append(text)
            return vector(text)
        }
        #expect(guess == "Recipes")
        #expect(asked.count == 1 + 1 + FolderGuess.newest)
        #expect(asked.contains("food 49"))
        #expect(!asked.contains("food 0"))
    }

    @Test func cosine() {
        #expect(FolderGuess.similarity([1, 0], [1, 0]) == 1)
        #expect(FolderGuess.similarity([1, 0], [0, 1]) == 0)
        #expect(FolderGuess.similarity([0, 0], [1, 0]) == 0)
    }
}
