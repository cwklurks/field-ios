import Foundation

// Each engine's public suggest endpoint. All of them answer in the
// OpenSearch suggestions shape (SuggestResponse) and need no key. Checked
// with curl on 2026-10-03: Startpage answers every question with an empty
// list, so it isn't asked, and a custom template has no endpoint to guess.
extension Engine {
    /// Whether the engine has suggestions to offer while you type.
    public var suggests: Bool { suggestTemplate != nil }

    /// Where to ask for suggestions for these words, escaped as a search is.
    public func suggestURL(for words: String) -> URL? {
        suggestTemplate.flatMap { Engine.url(for: words, template: $0) }
    }

    private var suggestTemplate: String? {
        switch self {
        case .google: return "https://suggestqueries.google.com/complete/search?client=firefox&oe=utf-8&q=%s"
        case .duckduckgo: return "https://duckduckgo.com/ac/?q=%s&type=list"
        case .bing: return "https://api.bing.com/osjson.aspx?query=%s"
        case .ecosia: return "https://ac.ecosia.org/autocomplete?q=%s&type=list"
        // Kagi's and Qwant's are the ones their own OpenSearch files name.
        case .kagi: return "https://kagisuggest.com/api/autosuggest?q=%s"
        case .brave: return "https://search.brave.com/api/suggest?q=%s"
        case .qwant: return "https://api.qwant.com/v3/suggest/?q=%s&client=opensearch"
        case .startpage, .custom: return nil
        }
    }
}
