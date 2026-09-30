import Foundation
import Network
import os
import Testing
import WebKit
@testable import Field

/// The blocker against a real WKWebView: a tiny list compiled into a store
/// of its own, and a page served on loopback with one image the list blocks
/// and one it doesn't.
@Suite(.serialized)
struct BlockingWebTests {
    private let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("BlockingWebTests-\(UUID().uuidString)", isDirectory: true)
    private let suite = "BlockingWebTests-\(UUID().uuidString)"

    private static let rules = """
    [{"trigger":{"url-filter":"/ad\\\\.svg"},"action":{"type":"block"}},
     {"trigger":{"url-filter":"/blocked-page"},"action":{"type":"block"}}]
    """

    private func clean() {
        try? FileManager.default.removeItem(at: root)
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
    }

    /// A manifest and one gzipped list in the shape build.sh writes.
    private func lists(sha: String = "0123456789abcdef") throws -> URL {
        let directory = root.appendingPathComponent("lists", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.gzip(Data(Self.rules.utf8)).write(to: directory.appendingPathComponent("tiny.json.gz"))
        let manifest = #"{"lists":[{"name":"tiny","file":"tiny.json.gz","rules":2,"sha256":"\#(sha)"}]}"#
        let url = directory.appendingPathComponent("blocking-manifest.json")
        try Data(manifest.utf8).write(to: url)
        return url
    }

    private func blocking(_ manifest: URL) -> ContentBlocking {
        ContentBlocking(
            manifest: manifest, store: root.appendingPathComponent("store", isDirectory: true),
            defaults: UserDefaults(suiteName: suite)!, idle: .zero
        )
    }

    @Test func blocksWhatTheListSaysAndNothingElse() async throws {
        defer { clean() }
        let server = try await Server.start()
        defer { server.stop() }
        let blocking = blocking(try lists())
        #expect(!blocking.ready)
        blocking.prepare()
        await blocking.preparing?.value
        #expect(blocking.ready)

        let page = Page()
        let host = server.url.host()
        blocking.apply(to: page.controller, host: host)
        try await page.open(server.url.appendingPathComponent("page"))
        #expect(try await page.loaded("ok"))
        #expect(try await !page.loaded("ad"))

        // Off for the site: the next page gets everything.
        blocking.setShield(false, for: host!)
        #expect(!blocking.isShieldOn(for: host))
        blocking.apply(to: page.controller, host: host)
        try await page.open(server.url.appendingPathComponent("page"))
        #expect(try await page.loaded("ad"))
    }

    /// As a tab does it: the lists go on or come off inside `decidePolicyFor`,
    /// for the site that navigation is heading to, and hold for that page,
    /// including one on another site, which WebKit gives a process of its own.
    @Test func appliedAsEachNavigationIsDecided() async throws {
        defer { clean() }
        let server = try await Server.start()
        defer { server.stop() }
        let blocking = blocking(try lists())
        blocking.prepare()
        await blocking.preparing?.value

        let page = Page()
        page.deciding = { [unowned page] action in
            guard action.targetFrame?.isMainFrame == true else { return }
            blocking.apply(to: page.controller, host: action.request.url?.host())
        }
        let here = server.url.appendingPathComponent("page")
        var elsewhere = try #require(URLComponents(url: here, resolvingAgainstBaseURL: false))
        elsewhere.host = "localhost"
        blocking.setShield(false, for: "localhost")

        try await page.open(here)
        #expect(try await !page.loaded("ad"))
        try await page.open(try #require(elsewhere.url))
        #expect(try await page.loaded("ad"))
        try await page.open(here)
        #expect(try await page.loaded("ok"))
        #expect(try await !page.loaded("ad"))
    }

    /// A page the list stops outright fails with 104, and "Load anyway"
    /// gets it, once.
    @Test func loadAnyway() async throws {
        defer { clean() }
        let server = try await Server.start()
        defer { server.stop() }
        let blocking = blocking(try lists())
        blocking.prepare()
        await blocking.preparing?.value

        let page = Page()
        let target = server.url.appendingPathComponent("blocked-page")
        blocking.apply(to: page.controller, host: target.host())
        let error = await #expect(throws: (any Error).self) { try await page.open(target) }
        #expect(ContentBlocking.blockedURL(from: try #require(error)) == target)

        blocking.loadAnyway(target, in: page.web)
        // The navigation that load starts asks for the lists, as a tab's does.
        blocking.apply(to: page.controller, host: target.host())
        try await page.finished()
        #expect(page.web.url == target)

        // And the one after that is protected again.
        blocking.apply(to: page.controller, host: target.host())
        await #expect(throws: (any Error).self) { try await page.open(target) }
    }

    /// The second launch looks the list up instead of compiling it, and a
    /// build with a new list removes the old compiled one.
    @Test func versionsAndStaleLists() async throws {
        defer { clean() }
        let first = blocking(try lists(sha: "aaaaaaaaaaaaaaaa"))
        first.prepare()
        await first.preparing?.value
        let store = try #require(WKContentRuleListStore(url: root.appendingPathComponent("store", isDirectory: true)))
        let before = try #require(await store.availableIdentifiers())
        #expect(before == ["field.blocking.tiny.aaaaaaaaaaaaaaaa"])

        let again = blocking(try lists(sha: "aaaaaaaaaaaaaaaa"))
        again.prepare()
        await again.preparing?.value
        #expect(again.ready)

        let updated = blocking(try lists(sha: "bbbbbbbbbbbbbbbb"))
        updated.prepare()
        await updated.preparing?.value
        #expect(updated.ready)
        #expect(await store.availableIdentifiers() == ["field.blocking.tiny.bbbbbbbbbbbbbbbb"])
    }

    /// Gzip around Foundation's raw deflate. The CRC is left zero: the
    /// reader checks the length, not the checksum.
    private static func gzip(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        let size = UInt32(data.count)
        return Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 2, 3]) + deflated + Data(count: 4)
            + Data([0, 8, 16, 24].map { UInt8(truncatingIfNeeded: size >> $0) })
    }
}

/// A web view and the navigations it finishes or fails.
@MainActor private final class Page: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    var controller: WKUserContentController { web.configuration.userContentController }
    private var waiting: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        web.navigationDelegate = self
    }

    /// Called with each navigation before it's allowed, as a tab's `decidePolicyFor` is.
    var deciding: (WKNavigationAction) -> Void = { _ in }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        deciding(action)
        decisionHandler(.allow)
    }

    func open(_ url: URL) async throws {
        web.load(URLRequest(url: url))
        try await finished()
    }

    func finished() async throws {
        try await withCheckedThrowingContinuation { waiting = $0 }
    }

    func loaded(_ id: String) async throws -> Bool {
        let width = try await web.evaluateJavaScript("document.getElementById('\(id)').naturalWidth")
        return (width as? Int ?? 0) > 0
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waiting?.resume()
        waiting = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        waiting?.resume(throwing: error)
        waiting = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        waiting?.resume(throwing: error)
        waiting = nil
    }
}

/// Serves the test page and its two images on 127.0.0.1, as FieldPerfTests'
/// Fixture does.
private nonisolated final class Server: Sendable {
    let url: URL
    private let listener: NWListener

    private init(url: URL, listener: NWListener) {
        self.url = url
        self.listener = listener
    }

    func stop() { listener.cancel() }

    private static let queue = DispatchQueue(label: "com.connork.field.tests.blocking")

    private static let page = """
    <!doctype html><title>page</title>
    <img id="ok" src="/ok.svg"><img id="ad" src="/ad.svg">
    """
    private static let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>"#

    static func start() async throws -> Server {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let once = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                let resume: Result<Void, Error>? = switch state {
                case .ready: .success(())
                case .failed(let error), .waiting(let error): .failure(error)
                default: nil
                }
                guard let resume, once.withLock({ done in defer { done = true }; return !done }) else { return }
                continuation.resume(with: resume)
            }
            listener.start(queue: queue)
        }
        return Server(url: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/")!, listener: listener)
    }

    private static func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            let buffer = buffer + (data ?? Data())
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let path = head.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
                respond(on: connection, path: path)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private static func respond(on connection: NWConnection, path: String) {
        let (type, body): (String, String) = path.hasSuffix(".svg") ? ("image/svg+xml", svg) : ("text/html", page)
        let data = Data(body.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + data, completion: .contentProcessed { _ in connection.cancel() })
    }
}
