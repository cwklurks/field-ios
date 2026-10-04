import Foundation
import Testing
@testable import FieldKit

// What may leave the phone while you type. Everything here is a "no" unless
// the switch is on, the space is not Private, and the words are words: not
// an address, not a secret, not one letter.
struct SuggestGateTests {
    func request(
        _ typed: String, engine: Engine = .google, privately: Bool = false, enabled: Bool = true,
        near: [Suggestion] = []
    ) -> URL? {
        Suggest.request(for: typed, engine: engine, privately: privately, enabled: enabled, near: near)
    }

    @Test func wordsAreSentToTheEngine() {
        #expect(request("swift conc")?.absoluteString
            == "https://suggestqueries.google.com/complete/search?client=firefox&oe=utf-8&q=swift%20conc")
    }

    @Test func theDefaultIsOneConstant() {
        #expect(Suggest.enabledByDefault == true)
    }

    @Test func neverInPrivate() {
        #expect(request("swift conc", privately: true) == nil)
    }

    @Test func neverWithTheSwitchOff() {
        #expect(request("swift conc", enabled: false) == nil)
    }

    @Test(arguments: ["", " ", "s", " s ", "é"])
    func nothingForAnEmptyOrOneLetterField(typed: String) {
        #expect(request(typed) == nil)
    }

    @Test func twoLettersAreEnough() {
        #expect(request("sw") != nil)
    }

    @Test(arguments: [
        "github.com", "github.com/apple/swift", "https://example.com/a?b=c", "localhost:3000",
        "192.168.1.1", "printer.local", "example.", "example.c", "http:", "http:/",
        "https://", "[::1]", "intranet/path", "ftp://server", "find example.com", "name@host", "about:blank", "www.exa", "news.ycombinator.com",
    ])
    func anAddressIsNeverSent(typed: String) {
        #expect(request(typed) == nil)
    }

    @Test(arguments: [
        // Keys and tokens.
        "sk-ant-api03-abcdefghijklmnop", "ghp_16C7e42F292c6912E7710c838347Ae178B4a",
        "AKIAIOSFODNN7EXAMPLE", "xoxb-1234-5678-abcdefghij",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.abc",
        "-----BEGIN OPENSSH PRIVATE KEY-----",
        // Anything long and unbroken: a hash, a key, a pasted blob.
        "3f786850e387550fdab836ed7e6dc881de23001b",
        "aGVsbG8gd29ybGQgdGhpcyBpcyBiYXNlNjQ",
        // Something that reads as a password.
        "Summer2024", "Tr0ub4dor&3", "hunter2!Pass", "password: letmein", "my pwd is hunter2", "api_key=abc123",
        // Numbers that are someone's: a card, a phone, a social security number.
        "4111 1111 1111 1111", "4111-1111-1111-1111", "(555) 123-4567", "123-45-6789",
        // An email address, which is half a sign-in.
        "someone@example.com",
    ])
    func aSecretIsNeverSent(typed: String) {
        #expect(request(typed) == nil)
    }

    @Test(arguments: [
        "swift concurrency", "iphone 17 pro", "how tall is the eiffel tower", "SwiftUI",
        "weather in paris", "1984 orwell", "café crème", "日本語", "c++ templates", "macOS 26",
        "sk-ii essence", "ASIA travel", "COVID-19 symptoms", "best password manager", "secret garden",
    ])
    func ordinaryWordsAreSent(typed: String) {
        #expect(request(typed) != nil)
    }

    @Test func aVeryLongQueryIsNotSent() {
        #expect(request(String(repeating: "word ", count: 30)) == nil)
    }

    @Test func surroundingSpaceIsNotSent() {
        #expect(request("  swift conc  ")?.absoluteString.hasSuffix("q=swift%20conc") == true)
    }

    /// Typing on the way to somewhere the field already knows is typing an
    /// address that isn't finished yet: "intranet-co" must not leave before
    /// it has become intranet-corp.example.
    @Test func nothingWhileHeadingToAKnownPlace() {
        let place = Suggestion(
            key: "intranet-corp.example", title: "", url: URL(string: "https://intranet-corp.example")!, kind: .visited
        )
        #expect(request("intranet-co", near: [place]) == nil)
        #expect(request("Intranet-Co", near: [place]) == nil)
        // Once the words go somewhere else, they are words.
        #expect(request("intranet costs", near: [place]) != nil)
        // A past search starting so is no address.
        let searched = Suggestion(
            key: "swift concurrency", title: "", url: URL(string: "https://www.google.com/search?q=swift")!, kind: .searched
        )
        #expect(request("swift c", near: [searched]) != nil)
    }

    @Test func anEngineWithNothingToOfferGetsNothing() {
        #expect(request("swift conc", engine: .startpage) == nil)
        #expect(request("swift conc", engine: .custom) == nil)
    }
}
