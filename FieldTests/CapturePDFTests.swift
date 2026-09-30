import Foundation
import ImageIO
import Network
import os
import Testing
import WebKit
@testable import Field

/// A capture of a real WKWebView: a long page served on loopback, with a
/// fixed header, made into a PDF and into a tall image.
@Suite(.serialized)
@MainActor struct CapturePDFTests {
    /// Sections of known height under a fixed header, so the document is
    /// exactly `sections * 100 + 60` CSS pixels long.
    private static func page(sections: Int) -> String {
        """
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Long page</title>
        <style>
          html, body { margin: 0 }
          header { position: fixed; top: 0; left: 0; right: 0; height: 60px; background: #222; color: #fff }
          main { padding-top: 60px }
          section { height: 100px; box-sizing: border-box; border-bottom: 1px solid #ccc; font: 16px sans-serif }
        </style>
        <header>Header</header>
        <main>\((0..<sections).map { "<section>Section \($0)</section>" }.joined())</main>
        """
    }

    @Test func aLongPageIsOnePDFAsLongAsTheDocument() async throws {
        let server = try await CaptureServer.start(html: Self.page(sections: 120))
        defer { server.stop() }
        let page = CapturePage()
        try await page.open(server.url)
        let height = try await page.documentHeight()
        #expect(height == 120 * 100 + 60)

        let pdf = try await PageCapture.pdf(of: page.web)
        let pages = PageCapture.pageSizes(pdf)
        #expect(pages.count == 1)
        let whole = TallImage.stacked(pages)
        #expect(whole.width == 390)
        #expect(abs(whole.height - CGFloat(height)) <= 1)
    }

    /// Wherever it's scrolled to, the capture starts at the top.
    @Test func scrollingDoesNotMoveTheCapture() async throws {
        let server = try await CaptureServer.start(html: Self.page(sections: 60))
        defer { server.stop() }
        let page = CapturePage()
        try await page.open(server.url)
        let top = PageCapture.pageSizes(try await PageCapture.pdf(of: page.web))
        page.web.scrollView.contentOffset.y = 3000
        let scrolled = PageCapture.pageSizes(try await PageCapture.pdf(of: page.web))
        #expect(scrolled == top)
    }

    @Test func theImageIsThePageAtTwiceItsSize() async throws {
        let server = try await CaptureServer.start(html: Self.page(sections: 40))
        defer { server.stop() }
        let page = CapturePage()
        try await page.open(server.url)
        let pdf = try await PageCapture.pdf(of: page.web)
        let file = try await Task.detached { try PageCapture.write(pdf, as: .image, named: "long.png") }.value
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let image = try #require(CGImageSourceCreateWithURL(file as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == 780)
        #expect(image.height == 2 * (40 * 100 + 60))
    }

    /// 60,000 points: WebKit breaks the PDF into pages at 14,400 points
    /// (PDF's own limit) and loses none of it, and the image shrinks to fit
    /// the cap rather than being cut.
    @Test func aVeryLongPageShrinksIntoTheImage() async throws {
        let server = try await CaptureServer.start(html: Self.page(sections: 600))
        defer { server.stop() }
        let page = CapturePage()
        try await page.open(server.url)
        let pdf = try await PageCapture.pdf(of: page.web)
        let pages = PageCapture.pageSizes(pdf)
        #expect(pages.count == 5)
        #expect(pages.dropLast().allSatisfy { $0.height == 14_400 })
        #expect(abs(TallImage.stacked(pages).height - 60_060) <= 1)
        let file = try await Task.detached { try PageCapture.write(pdf, as: .image, named: "longer.png") }.value
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let image = try #require(CGImageSourceCreateWithURL(file as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.height == TallImage.maxSide)
        #expect(image.width == 106)
    }
}

/// A web view on screen, in a window of its own, and its loads.
@MainActor final class CapturePage: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    private let window: UIWindow
    private var waiting: CheckedContinuation<Void, Error>?

    override init() {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = web.frame
        super.init()
        web.navigationDelegate = self
        window.addSubview(web)
        window.isHidden = false
    }

    isolated deinit {
        window.isHidden = true
    }

    func open(_ url: URL) async throws {
        web.load(URLRequest(url: url))
        try await withCheckedThrowingContinuation { waiting = $0 }
    }

    func documentHeight() async throws -> Int {
        try await web.evaluateJavaScript("document.documentElement.scrollHeight") as? Int ?? 0
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waiting?.resume()
        waiting = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        waiting?.resume(throwing: error)
        waiting = nil
    }
}

/// One page on 127.0.0.1, as FieldPerfTests' Fixture serves its article.
nonisolated final class CaptureServer: Sendable {
    let url: URL
    private let listener: NWListener

    private init(url: URL, listener: NWListener) {
        self.url = url
        self.listener = listener
    }

    func stop() { listener.cancel() }

    private static let queue = DispatchQueue(label: "com.connork.field.tests.capture")

    static func start(html: String) async throws -> CaptureServer {
        let body = Data(html.utf8)
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            receive(on: connection, buffer: Data(), body: body)
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
        return CaptureServer(url: URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/")!, listener: listener)
    }

    private static func receive(on connection: NWConnection, buffer: Data, body: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            let buffer = buffer + (data ?? Data())
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer, body: body)
            }
        }
    }
}
