import Foundation
import Testing
@testable import FieldKit

// Pinned against the Mac's Engine.swift, run as it ships.
struct EngineTests {
    @Test func theList() {
        #expect(Engine.allCases.map(\.rawValue) == [
            "google", "duckduckgo", "bing", "ecosia", "startpage", "kagi", "brave", "qwant", "custom",
        ])
        #expect(Engine.allCases.map(\.title) == [
            "Google", "DuckDuckGo", "Bing", "Ecosia", "Startpage", "Kagi", "Brave Search", "Qwant", "Custom",
        ])
        #expect(Engine.standard == .google)
        #expect(Engine.kagi.id == "kagi")
    }

    @Test(arguments: [
        (Engine.google, "https://www.google.com/search?q="),
        (.duckduckgo, "https://duckduckgo.com/?q="),
        (.bing, "https://www.bing.com/search?q="),
        (.ecosia, "https://www.ecosia.org/search?q="),
        (.startpage, "https://www.startpage.com/sp/search?query="),
        (.kagi, "https://kagi.com/search?q="),
        (.brave, "https://search.brave.com/search?q="),
        (.qwant, "https://www.qwant.com/?q="),
    ])
    func presets(engine: Engine, base: String) {
        let template = engine.template(custom: "")
        // Everything outside the unreserved set is escaped, spaces as %20.
        let expected: [(String, String)] = [
            ("hello world", "hello%20world"),
            ("a&b", "a%26b"),
            ("a#b", "a%23b"),
            ("a+b", "a%2Bb"),
            ("100%", "100%25"),
            ("x=y?z", "x%3Dy%3Fz"),
            ("a/b", "a%2Fb"),
            ("café", "caf%C3%A9"),
            ("日本語", "%E6%97%A5%E6%9C%AC%E8%AA%9E"),
            ("  trim me \n", "trim%20me"),
        ]
        for (words, escaped) in expected {
            #expect(Engine.url(for: words, template: template)?.absoluteString == base + escaped)
        }
        #expect(engine.name(custom: "https://example.com/?q=%s") == engine.title)
    }

    @Test(arguments: ["", "   ", "\n"])
    func nothingToAsk(words: String) {
        #expect(Engine.url(for: words, template: Engine.google.template(custom: "")) == nil)
    }

    @Test(arguments: [
        ("https://example.com/find?q=%s", "https://example.com/find?q=a%20b%26c", "example.com"),
        ("  https://www.example.com/s/%s  ", "https://www.example.com/s/a%20b%26c", "example.com"),
        ("https://example.com/?a=%s&b=%s", "https://example.com/?a=a%20b%26c&b=a%20b%26c", "example.com"),
        ("HTTPS://Example.COM/?q=%s", "HTTPS://Example.COM/?q=a%20b%26c", "example.com"),
        ("https://example.com/?q=%s#frag", "https://example.com/?q=a%20b%26c#frag", "example.com"),
        ("https://example.com/ search?q=%s", "https://example.com/%20search?q=a%20b%26c", "example.com"),
    ])
    func aCustomTemplate(custom: String, expected: String, name: String) {
        #expect(Engine.accepts(custom))
        let template = Engine.custom.template(custom: custom)
        #expect(template == custom.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(Engine.url(for: "a b&c", template: template)?.absoluteString == expected)
        #expect(Engine.custom.name(custom: custom) == name)
    }

    @Test(arguments: [
        "",
        "https://example.com/?q=",       // nowhere for the words to go
        "example.com/?q=%s",             // no scheme
        "ftp://example.com/?q=%s",       // not the web
        "https://%s.example.com/",       // the words would pick the host
    ])
    func aRefusedTemplateFallsBackToGoogle(custom: String) {
        #expect(!Engine.accepts(custom))
        #expect(Engine.custom.template(custom: custom) == "https://www.google.com/search?q=%s")
        #expect(Engine.custom.name(custom: custom) == "Google")
    }

    // MARK: - results pages (Field's own; the Mac never asks)

    @Test(arguments: Engine.allCases.filter { $0 != .custom })
    func aPresetKnowsItsResults(engine: Engine) throws {
        let template = engine.template(custom: "")
        let results = try #require(Engine.url(for: "my secret diagnosis", template: template))
        #expect(Engine.isResults(results, template: template))
        // Not its front page, and not somebody else's page with the same
        // words in the same place.
        let front = try #require(URL(string: "/", relativeTo: results)?.absoluteURL)
        #expect(!Engine.isResults(front, template: template))
        let elsewhere = try #require(URL(string: "https://example.com" + results.path() + "?" + (results.query() ?? "")))
        #expect(!Engine.isResults(elsewhere, template: template))
    }

    @Test(arguments: [
        // The words among other things, in any order, with or without www.
        ("https://www.google.com/search?client=safari&q=x&sca_esv=1", true),
        ("https://google.com/search?q=x", true),
        ("HTTPS://WWW.GOOGLE.COM/search?q=x", true),
        ("https://www.google.com/maps?q=x", false),
        ("https://mail.google.com/search?q=x", false),
        ("https://www.google.com/search", false),
    ])
    func googleResultsAsTheyReallyLook(address: String, expected: Bool) throws {
        let url = try #require(URL(string: address))
        #expect(Engine.isResults(url, template: Engine.google.template(custom: "")) == expected)
    }

    @Test(arguments: [
        ("https://duckduckgo.com/?t=h_&q=x&ia=web", true),
        ("https://duckduckgo.com/?t=h_", false),
        ("https://duckduckgo.com/", false),
        ("https://duckduckgo.com/about", false),
    ])
    func duckDuckGoResultsShareTheFrontPage(address: String, expected: Bool) throws {
        let url = try #require(URL(string: address))
        #expect(Engine.isResults(url, template: Engine.duckduckgo.template(custom: "")) == expected)
    }

    @Test(arguments: [
        ("https://search.example.org/find?q=%s", "https://search.example.org/find?page=2&q=x", true),
        ("https://search.example.org/find?q=%s", "https://search.example.org/find", false),
        ("https://search.example.org/find?q=%s", "https://search.example.org/other?q=x", false),
        ("https://search.example.org/find?q=%s", "https://example.org/find?q=x", false),
        ("https://example.com?q=%s", "https://example.com/?q=x", true),
        ("https://example.com/search/%s", "https://example.com/search/a%20b", true),
        ("https://example.com/search/%s", "https://example.com/search/", false),
        ("https://example.com/search/%s", "https://example.com/about", false),
        ("https://example.com/s/%s/all", "https://example.com/s/x/all", true),
        ("https://example.com/s/%s/all", "https://example.com/s/x/none", false),
    ])
    func aCustomTemplateKnowsItsResults(custom: String, address: String, expected: Bool) throws {
        let url = try #require(URL(string: address))
        #expect(Engine.isResults(url, template: Engine.custom.template(custom: custom)) == expected)
    }
}
