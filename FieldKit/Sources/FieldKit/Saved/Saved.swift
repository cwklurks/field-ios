import Foundation

// Pages you keep. One concept rather than Safari's four: a page is saved, it
// may sit in a folder (one level, no folders in folders), and it may be
// starred, which puts it on the new tab. "Read later" isn't a place of its
// own, only the saved pages not opened since. A plain value: when to write
// it to its file is the app's business.

public struct SavedPage: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var url: URL
    public var title: String
    public let added: Date
    public var folder: String?
    public var starred: Bool
    /// The last time it was opened after it was saved; nil until then.
    public var lastOpened: Date?

    /// The site, without the www.
    public var host: String {
        let host = url.host()?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Saved and not opened since: what "Read later" shows.
    public var isUnread: Bool { lastOpened == nil }
}

public struct Saved: Equatable, Sendable {
    /// Newest first.
    public private(set) var pages: [SavedPage] = []
    /// In the order they were made. A folder stays when it empties.
    public private(set) var folders: [String] = []

    public init() {}

    // MARK: - reading

    public func page(for url: URL) -> SavedPage? {
        let key = Saved.key(url)
        return pages.first { Saved.key($0.url) == key }
    }

    public func contains(_ url: URL) -> Bool { page(for: url) != nil }

    /// The new tab's grid. Oldest saved first, so a new star lands at the
    /// end rather than moving the others along.
    public var starred: [SavedPage] { pages.filter(\.starred).reversed() }

    /// Saved and never opened since, newest first.
    public var readLater: [SavedPage] { pages.filter(\.isUnread) }

    public func pages(in folder: String) -> [SavedPage] {
        guard let folder = named(folder) else { return [] }
        return pages.filter { $0.folder == folder }
    }

    public func count(in folder: String) -> Int { pages(in: folder).count }

    /// Every word typed has to be in the title or the site, in any order,
    /// case and accents aside. Nothing typed is everything.
    public func search(_ text: String, among list: [SavedPage]? = nil) -> [SavedPage] {
        let words = Saved.fold(text).split(whereSeparator: \.isWhitespace)
        let list = list ?? pages
        guard !words.isEmpty else { return list }
        return list.filter { page in
            let title = Saved.fold(page.title)
            let host = page.host
            return words.allSatisfy { title.contains($0) || host.contains($0) }
        }
    }

    // MARK: - writing

    /// The page, saved now, or the one already saved at that address, which
    /// is left as it was. Nil for anything that isn't a web page.
    @discardableResult
    public mutating func save(_ url: URL, title: String, folder: String? = nil, starred: Bool = false,
                              id: UUID = UUID(), now: Date = .now) -> SavedPage? {
        guard url.scheme == "http" || url.scheme == "https", url.host() != nil,
              let url = Saved.withoutPassword(url) else { return nil }
        if let kept = page(for: url) { return kept }
        let page = SavedPage(
            id: id, url: url, title: Saved.title(title, for: url), added: now,
            folder: folder.flatMap { addFolder($0) }, starred: starred, lastOpened: nil
        )
        pages.insert(page, at: 0)
        return page
    }

    public mutating func unsave(_ url: URL) {
        let key = Saved.key(url)
        pages.removeAll { Saved.key($0.url) == key }
    }

    public mutating func remove(_ id: UUID) {
        pages.removeAll { $0.id == id }
    }

    public mutating func star(_ id: UUID, _ on: Bool = true) {
        edit(id) { $0.starred = on }
    }

    public mutating func retitle(_ id: UUID, _ title: String) {
        edit(id) { $0.title = Saved.title(title, for: $0.url) }
    }

    /// Into a folder, made if it isn't there yet, or out of any for nil.
    public mutating func move(_ id: UUID, to folder: String?) {
        guard pages.contains(where: { $0.id == id }) else { return }
        let folder = folder.flatMap { addFolder($0) }
        edit(id) { $0.folder = folder }
    }

    /// The folder by that name, made if there isn't one. A name differing
    /// only in case is the same folder. Nil for a name that's all space.
    @discardableResult
    public mutating func addFolder(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        if let there = named(name) { return there }
        folders.append(name)
        return name
    }

    /// Onto the name of another folder, the two become one.
    public mutating func renameFolder(_ name: String, to new: String) {
        let new = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let old = named(name), !new.isEmpty else { return }
        let target = folders.first { $0 != old && Saved.same($0, new) } ?? new
        folders = folders.compactMap { $0 == old ? (target == new ? new : nil) : $0 }
        pages = pages.map { page in
            var page = page
            if page.folder == old { page.folder = target }
            return page
        }
    }

    /// The folder goes; what was in it stays saved, in no folder.
    public mutating func deleteFolder(_ name: String) {
        guard let folder = named(name) else { return }
        folders.removeAll { $0 == folder }
        pages = pages.map { page in
            var page = page
            if page.folder == folder { page.folder = nil }
            return page
        }
    }

    /// A saved page has been opened, so it's read.
    public mutating func opened(_ url: URL, now: Date = .now) {
        let key = Saved.key(url)
        guard let index = pages.firstIndex(where: { Saved.key($0.url) == key }) else { return }
        pages[index].lastOpened = now
    }

    private mutating func edit(_ id: UUID, _ change: (inout SavedPage) -> Void) {
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return }
        change(&pages[index])
    }

    private func named(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return folders.first { Saved.same($0, name) }
    }

    // MARK: - rules

    private static func same(_ one: String, _ other: String) -> Bool {
        one.compare(other, options: [.caseInsensitive]) == .orderedSame
    }

    /// Lower case, no accents: what search compares.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func title(_ title: String, for url: URL) -> String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? Address.pretty(url) : title
    }

    /// Two addresses are one page when they differ only in the scheme, the
    /// www., the case of the site, a closing slash or the fragment.
    static func key(_ url: URL) -> String {
        var host = url.host()?.lowercased() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        var path = url.path()
        while path.hasSuffix("/") { path.removeLast() }
        let port = url.port.map { ":\($0)" } ?? ""
        let query = url.query().map { "?" + $0 } ?? ""
        return host + port + path + query
    }

    private static func withoutPassword(_ url: URL) -> URL? {
        guard url.user() != nil || url.password() != nil else { return url }
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.user = nil
        parts.password = nil
        return parts.url
    }

    // MARK: - the file

    private struct File: Codable {
        var folders: [String]
        var pages: [SavedPage]
    }

    /// No file is nothing saved, and so is a file that isn't one, which is
    /// set aside first. Anything else that stops the file being read throws,
    /// and until a load has succeeded the app must not save over it.
    public static func load(from file: URL) throws -> Saved {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return Saved()
        }
        guard let read = try? JSONDecoder().decode(File.self, from: data) else {
            Store.quarantine(file)
            return Saved()
        }
        // Whatever the file says, one page per address, and every page's
        // folder among the folders.
        var saved = Saved()
        for name in read.folders { saved.addFolder(name) }
        var seen = Set<String>()
        for page in read.pages where seen.insert(key(page.url)).inserted {
            var page = page
            page.folder = page.folder.flatMap { saved.addFolder($0) }
            saved.pages.append(page)
        }
        return saved
    }

    public func save(to file: URL) throws {
        let data = try JSONEncoder().encode(File(folders: folders, pages: pages))
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: file, options: .atomic)
    }
}
