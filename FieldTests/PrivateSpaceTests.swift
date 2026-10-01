import Foundation
@testable import FieldKit
import Testing
import WebKit
@testable import Field

/// The private space against real web views: its own store that nothing
/// else shares, nothing on disk, and a wipe that leaves nothing behind.
@Suite(.serialized)
@MainActor struct PrivateSpaceTests {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent("PrivateSpaceTests-\(UUID().uuidString)", isDirectory: true)

    func clean() { try? FileManager.default.removeItem(at: temporary) }

    /// A page that sets a cookie in its response and a few more ways in
    /// script, all named for `token`.
    static func server() async throws -> PrivateServer {
        try await PrivateServer.start { path, _ in
            let token = path.split(separator: "?").dropFirst().first.map(String.init) ?? "none"
            guard path.hasPrefix("/set") else { return .init(body: "<!doctype html><title>echo</title>") }
            return .init(body: """
            <!doctype html><title>\(token)</title><p>\(token)</p>
            <script>
            document.cookie = "js_\(token)=1; path=/";
            localStorage.setItem("k_\(token)", "\(token)");
            sessionStorage.setItem("s_\(token)", "\(token)");
            indexedDB.open("db_\(token)").onupgradeneeded = e => e.target.result.createObjectStore("\(token)");
            caches.open("c_\(token)").then(c => c.put("/cached_\(token)", new Response("\(token)"))).catch(() => {});
            </script>
            """, headers: ["Set-Cookie: http_\(token)=1; Path=/; Max-Age=86400"])
        }
    }

    @Test func itsOwnStoreThatNothingElseShares() async throws {
        defer { clean() }
        let server = try await Self.server()
        defer { server.stop() }
        let space = PrivateSpace(temporary: temporary)
        let token = "t\(UUID().uuidString.prefix(8))"

        let config = WKWebViewConfiguration()
        space.configure(config)
        #expect(!config.websiteDataStore.isPersistent)
        #expect(config.websiteDataStore === space.dataStore)
        // Every private web view shares it, so sign-ins carry across tabs.
        let other = WKWebViewConfiguration()
        space.configure(other)
        #expect(other.websiteDataStore === config.websiteDataStore)

        let page = PrivatePage(config)
        try await page.open(server.url.appending(path: "set").appending(queryItems: [.init(name: token, value: nil)]))
        let cookies = await space.dataStore.httpCookieStore.allCookies()
        #expect(cookies.contains { $0.name == "http_\(token)" })
        let everyday = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        #expect(!everyday.contains { $0.name.hasSuffix(token) })

        // And the other way: an everyday cookie never shows in Private.
        let regular = HTTPCookie(properties: [.name: "everyday_\(token)", .value: "1", .domain: "127.0.0.1", .path: "/"])!
        await WKWebsiteDataStore.default().httpCookieStore.setCookie(regular)
        defer { Task { await WKWebsiteDataStore.default().httpCookieStore.deleteCookie(regular) } }
        let fresh = PrivatePage({ let c = WKWebViewConfiguration(); space.configure(c); return c }())
        try await fresh.open(server.url.appending(path: "echo"))
        let seen = try await fresh.page("document.cookie") as? String ?? ""
        #expect(seen.contains("js_\(token)"))
        #expect(!seen.contains("everyday_\(token)"))
    }

    /// Through the real Tab: a private tab's web view gets the session's
    /// store, Private's delegate and its hardening.
    @Test func aPrivateTabUsesTheSpacesStore() async throws {
        defer { clean() }
        let server = try await Self.server()
        defer { server.stop() }
        let space = PrivateSpace(temporary: temporary)
        let tab = space.open().current
        tab.load(server.url.appending(path: "set").appending(queryItems: [.init(name: "tab", value: nil)]))
        tab.build()
        let web = try #require(tab.web)
        #expect(web.configuration.websiteDataStore === space.dataStore)
        #expect(web.uiDelegate is PrivateUIDelegate)
        #expect(!web.configuration.allowsPictureInPictureMediaPlayback)
    }

    /// Wiped, the store it had holds no record of anything.
    @Test func wipeLeavesNoRecords() async throws {
        defer { clean() }
        let server = try await Self.server()
        defer { server.stop() }
        let space = PrivateSpace(temporary: temporary)
        _ = space.open()
        let store = space.dataStore
        do {
            let config = WKWebViewConfiguration()
            space.configure(config)
            let page = PrivatePage(config)
            try await page.open(server.url.appending(path: "set").appending(queryItems: [.init(name: "w", value: nil)]))
            _ = try await page.poll("localStorage.getItem('k_w')")
        }
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        #expect(await !store.dataRecords(ofTypes: types).isEmpty)
        await space.wipe()
        #expect(await store.dataRecords(ofTypes: types).isEmpty)
        #expect(await store.httpCookieStore.allCookies().isEmpty)
        #expect(space.tabs == nil)
        #expect(space.history == nil)
    }

    @Test func wipesInOrder() async throws {
        defer { clean() }
        let space = PrivateSpace(temporary: temporary)
        let tabs = space.open()
        _ = space.dataStore
        var steps: [PrivateWipe.Step] = []
        var webViewsAtDataStep = -1
        space.stepped = { step in
            steps.append(step)
            if step == .websiteData { webViewsAtDataStep = tabs.all.compactMap(\.web).count }
        }
        await space.wipe()
        #expect(steps == PrivateWipe.order)
        #expect(webViewsAtDataStep == 0)
    }

    /// Its tabs keep nothing: no session file, pictures in memory only, a
    /// history that never reaches disk, and nothing for Saved.
    @Test func itsTabsKeepNothing() async throws {
        defer { clean() }
        let space = PrivateSpace(temporary: temporary)
        let tabs = space.open()
        #expect(tabs.store.file == nil)
        #expect(tabs.snapshots.directory == nil)
        #expect(space.open() === tabs)

        let history = try #require(space.history)
        history.visited(URL(string: "https://private.example/")!, title: "Secret")
        await history.load()
        await history.flush()
        let path = await history.file.url.path
        #expect(!FileManager.default.fileExists(atPath: path))
        #expect(path.hasPrefix("/dev/null"))
        #expect(await history.file.writes == 0)
    }

    /// The Done-when check for M5: everything a page can store, and our own
    /// pictures and history of it, then the whole app container searched
    /// for its name. Nothing may turn up, before the wipe or after it.
    @Test func nothingReachesTheDisk() async throws {
        defer { clean() }
        let server = try await Self.server()
        defer { server.stop() }
        let space = PrivateSpace(temporary: temporary)
        let tabs = space.open()
        let token = "fieldleak\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        let config = WKWebViewConfiguration()
        space.configure(config)
        let page = PrivatePage(config)
        try await page.open(server.url.appending(path: "set").appending(queryItems: [.init(name: token, value: nil)]))
        _ = try await page.poll("localStorage.getItem('k_\(token)')")
        // The things Field itself keeps of a tab: its picture and history.
        let picture = try await page.web.takeSnapshot(configuration: nil)
        tabs.snapshots.put(picture, for: tabs.all[0].id)
        space.history?.visited(page.web.url!, title: token)
        tabs.changed()
        await tabs.flush()
        // Let WebKit's processes write anything they were going to.
        try await Task.sleep(for: .seconds(2))
        #expect(Self.containerFiles(containing: token).isEmpty)
        await space.wipe()
        try await Task.sleep(for: .seconds(1))
        #expect(Self.containerFiles(containing: token).isEmpty)
    }

    /// The search above finds what a persistent store writes, so its
    /// empty answer means something.
    @Test func theSearchFindsAnEverydayStore() async throws {
        defer { clean() }
        let server = try await Self.server()
        defer { server.stop() }
        let id = UUID()
        let token = "fieldkept\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
        do {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
            let page = PrivatePage(config)
            try await page.open(server.url.appending(path: "set").appending(queryItems: [.init(name: token, value: nil)]))
            _ = try await page.poll("localStorage.getItem('k_\(token)')")
            var found: [String] = []
            for _ in 0..<20 where found.isEmpty {
                try await Task.sleep(for: .milliseconds(500))
                found = Self.containerFiles(containing: token)
            }
            #expect(!found.isEmpty)
            print("Private: an everyday store wrote the page's name to \(found.map { $0.components(separatedBy: "/Library/").last ?? $0 })")
        }
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    /// Uploads and downloads made during the session go; older files stay.
    @Test func purgesOnlyTheSessionsFiles() async throws {
        defer { clean() }
        let fm = FileManager.default
        try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
        let old = temporary.appendingPathComponent("older.txt")
        try Data("old".utf8).write(to: old)
        try fm.setAttributes([.creationDate: Date.now.addingTimeInterval(-3600)], ofItemAtPath: old.path)

        let space = PrivateSpace(temporary: temporary)
        _ = space.open()
        let upload = temporary.appendingPathComponent("WKFileUploadPanel.x1", isDirectory: true)
        try fm.createDirectory(at: upload, withIntermediateDirectories: true)
        try Data("picked".utf8).write(to: upload.appendingPathComponent("photo.jpg"))
        let download = try #require(space.files?.downloads)
        try Data("got".utf8).write(to: download.appendingPathComponent("file.pdf"))
        #if !targetEnvironment(simulator)
        // The simulator has no data protection, and reports none.
        let protection = try fm.attributesOfItem(atPath: download.path)[.protectionKey] as? FileProtectionType
        #expect(protection == .complete)
        #endif

        await space.wipe()
        #expect(fm.fileExists(atPath: old.path))
        #expect(!fm.fileExists(atPath: upload.path))
        #expect(!fm.fileExists(atPath: download.path))
    }

    /// The fetches Field makes for Private (a picture saved from a page)
    /// carry its cookies and keep no cache or cookies of their own.
    @Test func itsURLSessionIsEphemeral() async throws {
        defer { clean() }
        let space = PrivateSpace(temporary: temporary)
        let session = space.session
        #expect(session.configuration.urlCache == nil || session.configuration.urlCache?.diskCapacity == 0)
        #expect(session.configuration.httpCookieStorage !== HTTPCookieStorage.shared)
        #expect(session === space.session)
        await space.wipe()
        #expect(session !== space.session)
    }

    /// Every file under the app's home whose bytes hold `token`.
    nonisolated static func containerFiles(containing token: String) -> [String] {
        let needle = Data(token.utf8)
        let home = URL(fileURLWithPath: NSHomeDirectory())
        guard let walk = FileManager.default.enumerator(at: home, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return [] }
        var found: [String] = []
        for case let url as URL in walk {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true, (values?.fileSize ?? 0) < 64 << 20,
                  let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }
            if data.range(of: needle) != nil { found.append(url.path) }
        }
        return found
    }
}
