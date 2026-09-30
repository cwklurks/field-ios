import Foundation

/// What a captured page is called wherever it goes: `<host> – <title>.pdf`,
/// with the host as the bar shows it, and nothing a file name can't hold.
nonisolated enum CaptureName {
    /// Long enough to tell pages apart in Files, well short of the 255
    /// bytes a file name may take.
    static let titleLength = 80

    static func file(url: URL?, title: String, extension ext: String) -> String {
        var host = url?.host() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if host.isEmpty { host = "Page" }
        let title = cut(clean(title))
        guard !title.isEmpty, title.lowercased() != host.lowercased() else { return "\(host).\(ext)" }
        return "\(host) – \(title).\(ext)"
    }

    /// One line, no slashes (a folder in Files) and no colons (a slash in
    /// the Finder). A colon before a space just goes, as in "Swift: a
    /// language"; one between digits becomes a dash, as in "12-30".
    private static func clean(_ title: String) -> String {
        var out = ""
        let characters = Array(title)
        for (i, c) in characters.enumerated() {
            switch c {
            case "/", "\\":
                out.append("-")
            case ":":
                let next = characters.indices.contains(i + 1) ? characters[i + 1] : " "
                if !next.isWhitespace { out.append("-") }
            case let c where c.isWhitespace:
                out.append(" ")
            case let c where c.unicodeScalars.allSatisfy({ $0.properties.generalCategory == .control }):
                break
            default:
                out.append(c)
            }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    /// At a word break when there's one in the second half, with an ellipsis.
    private static func cut(_ title: String) -> String {
        guard title.count > titleLength else { return title }
        var kept = String(title.prefix(titleLength))
        if let space = kept.lastIndex(of: " "), kept.distance(from: kept.startIndex, to: space) > titleLength / 2 {
            kept = String(kept[..<space])
        }
        return kept.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
    }
}
