import Foundation
import Testing
@testable import FieldKit

// Every supported engine answers in the OpenSearch suggestions shape: the
// words asked, then a list of strings, then whatever else it likes. These
// are their real answers to "café cr", taken with curl on 2026-10-03.
struct SuggestResponseTests {
    static let fixtures: [(String, String, [String])] = [
        ("google",
         #"["café cr",["café crêpe express","café crema","café crème","café cristal","café crème sky vs original","café croissant","café crème sky","café crème original","café crème cigars","café crêperie"],[],{"google:suggestsubtypes":[[512],[512],[512],[512],[512],[512],[512],[512],[512],[512]]}]"#,
         ["café crêpe express", "café crema", "café crème", "café cristal"]),
        ("duckduckgo",
         #"["café cr",["cafe cruiser","cafe cruz","cafe crepe","cafe crevier denville","cafe cravings","cafe creme austin","cafe crispy","cafe cremerie chicago"]]"#,
         ["cafe cruiser", "cafe cruz", "cafe crepe", "cafe crevier denville"]),
        ("bing",
         #"["café cr",["cafe crepe","cafe cristal","cafe crystal","cafe cristal barrhaven","cafe crepe vancouver","cafe crema west vancouver","cafe crew montreal","cafe croissant calgary","cafe creston bc"]]"#,
         ["cafe crepe", "cafe cristal", "cafe crystal", "cafe cristal barrhaven"]),
        ("brave",
         #"["café cr",["café crème","café crew","café croissant","café crepe vancouver","café crema","café crème longueuil","café croissound photos","café cherrier"]]"#,
         ["café crème", "café crew", "café croissant", "café crepe vancouver"]),
        ("ecosia",
         #"["café cr",["cafe crepe","cafe cristal","cafe crystal","cafe cristal barrhaven","cafe crepe vancouver","cafe crema west vancouver","cafe crew montreal","cafe croissant calgary"]]"#,
         ["cafe crepe", "cafe cristal", "cafe crystal", "cafe cristal barrhaven"]),
        ("kagi",
         #"["café cr",["cafe cruiser","cafe cruz","cafe crepe","cafe crevier denville","cafe cravings","cafe cruz santa cruz","cafe creme austin","cafe crispy","cafe cremerie chicago","cafe cream maysville ky"]]"#,
         ["cafe cruiser", "cafe cruz", "cafe crepe", "cafe crevier denville"]),
        ("qwant",
         #"["café cr",["cafe cruiser","cafe cruz","cafe crepe","cafe crevier denville","cafe cravings","cafe creme austin","cafe crispy"]]"#,
         ["cafe cruiser", "cafe cruz", "cafe crepe", "cafe crevier denville"]),
    ]

    @Test(arguments: fixtures)
    func realAnswers(engine: String, body: String, firstFour: [String]) {
        let words = SuggestResponse.words(from: Data(body.utf8))
        #expect(Array(words.prefix(4)) == firstFour, "\(engine)")
    }

    @Test(arguments: [
        "", "not json", "{}", "[]", #"["q"]"#, #"["q", "not a list"]"#, #"[1, ["a"]]"#,
        #"{"status":"success","data":{"items":[{"value":"swift"}]}}"#, "null", #"["q", null]"#,
    ])
    func anythingElseIsNothing(body: String) {
        #expect(SuggestResponse.words(from: Data(body.utf8)).isEmpty)
    }

    @Test func onlyStringsAreKeptAndTidied() {
        let body = #"["q",["  swift  concurrency ", 7, null, "", "   ", {"a":1}, "swift"]]"#
        #expect(SuggestResponse.words(from: Data(body.utf8)) == ["swift concurrency", "swift"])
    }

    @Test func anOverlongSuggestionIsDropped() {
        let long = String(repeating: "a", count: 300)
        let body = "[\"q\",[\"\(long)\",\"short\"]]"
        #expect(SuggestResponse.words(from: Data(body.utf8)) == ["short"])
    }

    @Test func controlCharactersAreDropped() {
        let body = #"["q",["a\nb","ok"]]"#
        #expect(SuggestResponse.words(from: Data(body.utf8)) == ["ok"])
    }

    @Test func aHugeAnswerIsRefused() {
        let body = "[\"q\",[" + Array(repeating: "\"x\"", count: 40_000).joined(separator: ",") + "]]"
        #expect(SuggestResponse.words(from: Data(body.utf8)).isEmpty)
    }

    @Test func notMoreThanAScreenful() {
        let body = "[\"q\",[" + (0..<50).map { "\"s\($0)\"" }.joined(separator: ",") + "]]"
        #expect(SuggestResponse.words(from: Data(body.utf8)).count == 10)
    }
}
