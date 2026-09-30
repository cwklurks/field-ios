import Foundation
import Testing
import UIKit
@testable import Field

/// Capture on a real tab: the screenshot editor's "Full Page", which a
/// private page never reaches, and the in-app capture, which it does.
@Suite(.serialized)
@MainActor struct CaptureScreenshotTests {
    private static let html = """
    <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Long page</title>
    <style>html, body { margin: 0 } section { height: 100px; font: 16px sans-serif }</style>
    \((0..<60).map { "<section>Section \($0)</section>" }.joined())
    """

    private static func history() -> HistoryStore {
        HistoryStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("CaptureScreenshotTests-\(UUID().uuidString)"))
    }

    /// A tab whose page has painted, on screen in a window of its own.
    private func paintedTab(_ url: URL) async throws -> (Tab, UIWindow) {
        let tab = Tab(history: Self.history())
        tab.load(url)
        tab.build()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let web = try #require(tab.web)
        web.frame = window.bounds
        window.addSubview(web)
        window.isHidden = false
        for _ in 0..<100 where !tab.isPainted || tab.isLoading {
            try await Task.sleep(for: .milliseconds(100))
        }
        try #require(tab.isPainted)
        return (tab, window)
    }

    @Test func theEditorOpensWhereThePageWasScrolledTo() async throws {
        let server = try await CaptureServer.start(html: Self.html)
        defer { server.stop() }
        let (tab, window) = try await paintedTab(server.url)
        defer { window.isHidden = true }
        let capture = Capture(page: { tab }, announce: { _ in })
        tab.web?.scrollView.contentOffset.y = 2000

        let (pdf, index, rect) = await capture.fullPage()
        #expect(pdf != nil)
        #expect(index == 0)
        // 6,000 points of page, 844 on screen from 2,000 down; PDF space
        // counts from the bottom.
        #expect(rect == CGRect(x: 0, y: 6000 - 2000 - 844, width: 390, height: 844))
    }

    @Test func aPrivatePageNeverReachesTheEditor() async throws {
        let server = try await CaptureServer.start(html: Self.html)
        defer { server.stop() }
        let (tab, window) = try await paintedTab(server.url)
        defer { window.isHidden = true }
        let capture = Capture(page: { tab }, announce: { _ in })
        capture.isPrivate = { true }

        let (pdf, index, rect) = await capture.fullPage()
        #expect(pdf == nil)
        #expect(index == 0 && rect == .zero)
    }

    /// Asked for, a private page is captured like any other.
    @Test func aPrivatePageCanStillBeCapturedOnPurpose() async throws {
        let server = try await CaptureServer.start(html: Self.html)
        defer { server.stop() }
        let (tab, window) = try await paintedTab(server.url)
        defer { window.isHidden = true }
        let capture = Capture(page: { tab }, announce: { _ in })
        capture.isPrivate = { true }

        let file = try #require(try await capture.make(.pdf))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        #expect(file.lastPathComponent == "127.0.0.1 – Long page.pdf")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    /// The scene's screenshot service asks the capture, which it holds weakly.
    @Test func attachesToTheScene() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let service = try #require(scene.screenshotService)
        let before = service.delegate
        defer { service.delegate = before }
        let capture = Capture(page: { nil }, announce: { _ in })
        capture.attach(to: scene)
        #expect(service.delegate === capture)
    }

    @Test func aBlankTabHasNothingToCapture() async throws {
        let tab = Tab(history: Self.history())
        let capture = Capture(page: { tab }, announce: { _ in })
        #expect(capture.menu(presenter: UIViewController(), source: nil) == nil)
        let (pdf, _, _) = await capture.fullPage()
        #expect(pdf == nil)
        await #expect(throws: CaptureError.self) { try await capture.make(.pdf) }
    }
}
