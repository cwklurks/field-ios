import Foundation
import Network
import os
import Testing
import WebKit
@testable import Field

// What the Private tests share: pages served on loopback, and a web view
// that waits for them. No tests of its own.

/// A web view and the navigations it finishes or fails.
@MainActor final class PrivatePage: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private var waiting: CheckedContinuation<Void, Error>?

    init(_ configuration: WKWebViewConfiguration) {
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        super.init()
        web.navigationDelegate = self
    }

    func open(_ url: URL) async throws {
        web.load(URLRequest(url: url))
        try await withCheckedThrowingContinuation { waiting = $0 }
    }

    /// What `script` gives in the page's own world.
    func page(_ script: String) async throws -> Any? {
        try await web.evaluateJavaScript(script, contentWorld: .page)
    }

    /// Asks until `script` gives something other than null, for up to `limit`.
    func poll(_ script: String, limit: Duration = .seconds(5)) async throws -> Any? {
        let end = ContinuousClock.now + limit
        while ContinuousClock.now < end {
            if let value = try await page(script), !(value is NSNull) { return value }
            try await Task.sleep(for: .milliseconds(50))
        }
        return nil
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

/// Pages on 127.0.0.1, answering each request from `respond`: its path and
/// its header lines, to a content type and body, and extra header lines.
nonisolated final class PrivateServer: Sendable {
    struct Reply: Sendable {
        var body: String
        var type = "text/html"
        var headers: [String] = []
    }

    let url: URL
    private let listener: NWListener

    private init(url: URL, listener: NWListener) {
        self.url = url
        self.listener = listener
    }

    func stop() { listener.cancel() }

    /// The same server under another name, for a frame from another site.
    var otherSite: URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        parts.host = "localhost"
        return parts.url!
    }

    private static let queue = DispatchQueue(label: "com.connork.field.tests.private")

    static func start(_ respond: @escaping @Sendable (_ path: String, _ head: String) -> Reply) async throws -> PrivateServer {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            receive(on: connection, buffer: Data(), respond: respond)
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
        return PrivateServer(url: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/")!, listener: listener)
    }

    private static func receive(on connection: NWConnection, buffer: Data, respond: @escaping @Sendable (String, String) -> Reply) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            let buffer = buffer + (data ?? Data())
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let path = head.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? "/"
                let reply = respond(path, head)
                let body = Data(reply.body.utf8)
                let lines = ["HTTP/1.1 200 OK", "Content-Type: \(reply.type)", "Content-Length: \(body.count)",
                             "Cache-Control: no-store", "Connection: close"] + reply.headers
                let out = Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8) + body
                connection.send(content: out, completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer, respond: respond)
            }
        }
    }
}
