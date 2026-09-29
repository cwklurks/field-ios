// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation

public enum Engine: String, CaseIterable, Identifiable, Sendable {
    case google, duckduckgo, bing, ecosia, startpage, kagi, brave, qwant, custom

    public static let standard = Engine.google

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .google: return "Google"
        case .duckduckgo: return "DuckDuckGo"
        case .bing: return "Bing"
        case .ecosia: return "Ecosia"
        case .startpage: return "Startpage"
        case .kagi: return "Kagi"
        case .brave: return "Brave Search"
        case .qwant: return "Qwant"
        case .custom: return "Custom"
        }
    }

    public func template(custom: String) -> String {
        switch self {
        case .google: return "https://www.google.com/search?q=%s"
        case .duckduckgo: return "https://duckduckgo.com/?q=%s"
        case .bing: return "https://www.bing.com/search?q=%s"
        case .ecosia: return "https://www.ecosia.org/search?q=%s"
        case .startpage: return "https://www.startpage.com/sp/search?query=%s"
        case .kagi: return "https://kagi.com/search?q=%s"
        case .brave: return "https://search.brave.com/search?q=%s"
        case .qwant: return "https://www.qwant.com/?q=%s"
        case .custom:
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            return Engine.accepts(trimmed) ? trimmed : Engine.standard.template(custom: "")
        }
    }

    public func name(custom: String) -> String {
        guard self == .custom else { return title }
        guard let host = Engine.host(of: custom) else { return Engine.standard.title }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func accepts(_ template: String) -> Bool {
        host(of: template) != nil
    }

    public static func url(for text: String, template: String) -> URL? {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty,
              let escaped = words.addingPercentEncoding(withAllowedCharacters: unreserved),
              let base = URL(string: template.replacingOccurrences(of: "%s", with: mark))?.absoluteString
        else { return nil }
        return URL(string: base.replacingOccurrences(of: mark, with: escaped), encodingInvalidCharacters: false)
    }

    /// Whether a page is the engine's answer to something asked: the same
    /// site, the same page, and a place for the words where the template puts
    /// them. The app counts one as a visit to the engine rather than
    /// remembering what was asked.
    public static func isResults(_ url: URL, template: String) -> Bool {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let form = URLComponents(string: trimmed.replacingOccurrences(of: "%s", with: mark)),
              let page = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let asked = form.host?.lowercased(), let answered = page.host?.lowercased(),
              asked.trimmingPrefix("www.") == answered.trimmingPrefix("www.")
        else { return false }
        let path = page.path.isEmpty ? "/" : page.path

        // The words in the query: the same page, with that field in it, among
        // whatever else the engine adds and in any order.
        if let field = form.queryItems?.first(where: { $0.value?.contains(mark) == true })?.name {
            return path == (form.path.isEmpty ? "/" : form.path)
                && page.queryItems?.contains { $0.name == field } == true
        }
        // The words in the path: something between what stands either side.
        let sides = form.path.components(separatedBy: mark)
        guard sides.count == 2 else { return false }
        return path.count > sides[0].count + sides[1].count
            && path.hasPrefix(sides[0])
            && path.hasSuffix(sides[1])
    }

    private static let mark = "SEARCHWORDSGOHERE"

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func host(of template: String) -> String? {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("%s"),
              let parts = URLComponents(string: trimmed.replacingOccurrences(of: "%s", with: "a")),
              let other = URLComponents(string: trimmed.replacingOccurrences(of: "%s", with: "b")),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty, host == other.host
        else { return nil }
        return host.lowercased()
    }
}
