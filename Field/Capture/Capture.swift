import UIKit
import WebKit

/// The whole page, top to bottom, not just what's on screen: "Capture Page"
/// on the address's long press (a PDF, or one tall image, to share), and the
/// "Full Page" tab of the system screenshot editor, as in Safari.
///
/// Only what's already loaded goes in, and nothing is fetched. A private
/// page can be captured on purpose, and a shared copy leaves Private like
/// any share; the screenshot editor never gets one (`isPrivate`).
final class Capture: NSObject {
    /// Whether the page on screen is a private one. Set by Private.
    var isPrivate: () -> Bool = { false }

    /// The tab on screen, private or not.
    var page: () -> Tab?
    private let announce: (String) -> Void
    /// One capture at a time.
    private var busy = false

    /// How long a capture runs before it says so.
    static let patience = Duration.milliseconds(300)
    /// A share sheet has been shown since launch. The first is slow to
    /// come: iOS finds what can share a file then.
    private static var shown = false
    /// One has been made out of sight to get that done early.
    private static var warmed = false

    init(page: @escaping () -> Tab?, announce: @escaping (String) -> Void) {
        self.page = page
        self.announce = announce
    }

    /// Answers the system screenshot for this scene, with the whole page.
    func attach(to scene: UIWindowScene) {
        scene.screenshotService?.delegate = self
    }

    /// "Capture Page", with PDF and Image under it, for a page there is to
    /// capture; nil for a blank tab or a failed load.
    func menu(presenter: UIViewController, source: UIView?) -> UIMenuElement? {
        guard page().flatMap(web(of:)) != nil else { return nil }
        let item = { [weak self, weak presenter, weak source] (title: String, symbol: String, kind: PageCapture.Kind) in
            UIAction(title: title, image: UIImage(systemName: symbol)) { _ in
                guard let self, let presenter else { return }
                self.capture(kind, from: presenter, source: source)
            }
        }
        return UIMenu(
            title: "Capture Page",
            subtitle: isPrivate() ? "A shared copy leaves Private." : nil,
            image: UIImage(systemName: "camera.viewfinder"),
            children: [item("PDF", "doc.richtext", .pdf), item("Image", "photo", .image)]
        )
    }

    /// Captures the page, then puts up the share sheet: Save to Files or
    /// Photos, Messages and the rest.
    func capture(_ kind: PageCapture.Kind, from presenter: UIViewController, source: UIView?) {
        // The first sheet since launch takes a while to come: said at once,
        // rather than a page that seems to have ignored the tap.
        if !Self.shown { announce("Capturing the page…") }
        Task {
            do {
                guard let file = try await make(kind) else { return }
                share(file, from: presenter, source: source)
            } catch {
                announce("Couldn't capture this page.")
            }
        }
    }

    /// The page as a file, named for its site and title. Nil while another
    /// capture is running. Past `patience` it says it's working, and keeps
    /// saying so (the toast would go after 1.7 s) until it's done.
    func make(_ kind: PageCapture.Kind) async throws -> URL? {
        guard let tab = page(), let web = web(of: tab) else { throw CaptureError.nothingToCapture }
        guard !busy else { return nil }
        busy = true
        defer { busy = false }
        let name = CaptureName.file(url: tab.url, title: tab.title, extension: kind.fileExtension)
        let saying = Task { [announce] in
            try await Task.sleep(for: Self.patience)
            while true {
                announce("Capturing the page…")
                try await Task.sleep(for: .seconds(1.5))
            }
        }
        defer { saying.cancel() }
        async let cleared: Void = Task.detached(priority: .userInitiated) { PageCapture.clear() }.value
        let pdf = try await PageCapture.pdf(of: web)
        await cleared
        return try await Task.detached(priority: .userInitiated) {
            try PageCapture.write(pdf, as: kind, named: name)
        }.value
    }

    /// The share sheet for a capture, which takes the file with it when it
    /// closes: a private page's capture is on disk only while it's shared.
    func share(_ file: URL, from presenter: UIViewController, source: UIView?) {
        Self.shown = true
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = source
        sheet.completionWithItemsHandler = { _, _, _, _ in
            Task.detached(priority: .utility) {
                try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            }
        }
        var top = presenter
        while let above = top.presentedViewController { top = above }
        top.present(sheet, animated: true)
    }

    /// A share sheet made and laid out out of sight, a few seconds after
    /// launch when `busy` says nothing else is going on, so the first one
    /// asked for doesn't wait for iOS to look for what can share.
    static func prepareSoon(unless busy: @escaping @MainActor () -> Bool, tries: Int = 0) {
        guard tries < 20 else { return }
        Timer.scheduledTimer(withTimeInterval: tries == 0 ? 3 : 0.5, repeats: false) { _ in
            MainActor.assumeIsolated {
                guard !warmed, !shown else { return }
                if busy() { return prepareSoon(unless: busy, tries: tries + 1) }
                let sample = FileManager.default.temporaryDirectory.appendingPathComponent("Field.pdf")
                let sheet = UIActivityViewController(activityItems: [sample], applicationActivities: nil)
                sheet.loadViewIfNeeded()
                warmed = true
            }
        }
    }

    /// A page that has painted and didn't fail: there's something to capture.
    private func web(of tab: Tab) -> WKWebView? {
        guard let web = tab.web, tab.isPainted, tab.failure == nil else { return nil }
        return web
    }
}

extension Capture: UIScreenshotServiceDelegate {
    /// The system screenshot's "Full Page": the whole page as a PDF, opened
    /// where the person was looking. Nothing for a private page, which goes
    /// nowhere without being asked.
    func screenshotService(_ screenshotService: UIScreenshotService) async -> (Data?, Int, CGRect) {
        await fullPage()
    }

    func fullPage() async -> (Data?, Int, CGRect) {
        guard !isPrivate(), let web = page().flatMap(web(of:)) else { return (nil, 0, .zero) }
        let scroll = web.scrollView
        let visible = scroll.bounds
        let width = scroll.contentSize.width
        guard let pdf = try? await PageCapture.pdf(of: web), !isPrivate() else { return (nil, 0, .zero) }
        let pages = await Task.detached(priority: .userInitiated) { PageCapture.pageSizes(pdf) }.value
        let place = ScreenshotPlace.locate(visible: visible, contentWidth: width, pages: pages)
        return (pdf, place.index, place.rect)
    }
}
