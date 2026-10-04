import Foundation
import Testing
@testable import FieldKit

// Each engine's public suggest endpoint, checked with curl on 2026-10-03.
// Startpage answers with an empty list for everything, and a custom template
// has no endpoint to guess at, so neither is asked.
struct SuggestEndpointTests {
    @Test(arguments: [
        (Engine.google, "https://suggestqueries.google.com/complete/search?client=firefox&oe=utf-8&q=caf%C3%A9%20cr"),
        (.duckduckgo, "https://duckduckgo.com/ac/?q=caf%C3%A9%20cr&type=list"),
        (.bing, "https://api.bing.com/osjson.aspx?query=caf%C3%A9%20cr"),
        (.ecosia, "https://ac.ecosia.org/autocomplete?q=caf%C3%A9%20cr&type=list"),
        (.kagi, "https://kagisuggest.com/api/autosuggest?q=caf%C3%A9%20cr"),
        (.brave, "https://search.brave.com/api/suggest?q=caf%C3%A9%20cr"),
        (.qwant, "https://api.qwant.com/v3/suggest/?q=caf%C3%A9%20cr&client=opensearch"),
    ])
    func endpoints(engine: Engine, expected: String) {
        #expect(engine.suggests)
        #expect(engine.suggestURL(for: "café cr")?.absoluteString == expected)
    }

    @Test func theWordsAreEscapedLikeASearch() {
        #expect(Engine.google.suggestURL(for: "a&b=c#d")?.absoluteString.hasSuffix("q=a%26b%3Dc%23d") == true)
    }

    @Test func noEndpointNoURL() {
        #expect(!Engine.startpage.suggests)
        #expect(!Engine.custom.suggests)
        #expect(Engine.startpage.suggestURL(for: "swift") == nil)
        #expect(Engine.custom.suggestURL(for: "swift") == nil)
    }
}
