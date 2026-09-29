import Foundation
import Testing
import FieldKit

// As the Mac's Browser.destination: an address if it can be one, otherwise
// the words, asked of the engine.
struct DestinationTests {
    @Test(arguments: [
        ("example.com", "https://example.com"),
        ("  example.com/a?b=1  ", "https://example.com/a?b=1"),
        ("localhost:3000", "http://localhost:3000"),
        ("192.168.1.1/admin", "http://192.168.1.1/admin"),
        ("https://x.y/path", "https://x.y/path"),
        ("about:blank", "about:blank"),
    ])
    func anAddressIsGoneTo(text: String, expected: String) {
        #expect(Destination.url(for: text, engine: .duckduckgo, custom: "")?.absoluteString == expected)
    }

    @Test(arguments: [
        ("what is x.y", "https://www.google.com/search?q=what%20is%20x.y"),
        ("todo", "https://www.google.com/search?q=todo"),
        ("a&b #1", "https://www.google.com/search?q=a%26b%20%231"),
        // Not a place the field can show, so they are words.
        ("mailto:x@y.com", "https://www.google.com/search?q=mailto%3Ax%40y.com"),
        ("ftp://x.com", "https://www.google.com/search?q=ftp%3A%2F%2Fx.com"),
    ])
    func wordsAreAskedOfTheEngine(text: String, expected: String) {
        #expect(Destination.url(for: text, engine: .google, custom: "")?.absoluteString == expected)
    }

    @Test func eachEngineIsAskedItsOwnWay() {
        #expect(Destination.url(for: "swift testing", engine: .duckduckgo, custom: "")?.absoluteString
            == "https://duckduckgo.com/?q=swift%20testing")
        #expect(Destination.url(for: "swift testing", engine: .startpage, custom: "")?.absoluteString
            == "https://www.startpage.com/sp/search?query=swift%20testing")
    }

    @Test func aCustomTemplate() {
        let custom = "https://search.example.org/find?q=%s"
        #expect(Destination.url(for: "swift testing", engine: .custom, custom: custom)?.absoluteString
            == "https://search.example.org/find?q=swift%20testing")
        // Only when it is the chosen engine.
        #expect(Destination.url(for: "swift testing", engine: .kagi, custom: custom)?.absoluteString
            == "https://kagi.com/search?q=swift%20testing")
        // A template that can't be used asks Google instead, as Settings says.
        #expect(Destination.url(for: "swift testing", engine: .custom, custom: "nonsense")?.absoluteString
            == "https://www.google.com/search?q=swift%20testing")
    }

    @Test(arguments: ["", "   ", "\n"])
    func nothingGoesNowhere(text: String) {
        #expect(Destination.url(for: text, engine: .google, custom: "") == nil)
    }
}
