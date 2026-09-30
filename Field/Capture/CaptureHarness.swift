#if DEBUG
import UIKit
import WebKit

/// `-FieldCaptureHarness YES -FieldOpen <url>`: once the page has painted,
/// scrolls it to `-FieldCaptureScroll` points (1500 unless given), then
/// captures it as a PDF and as an image, timing each and watching the main
/// thread and the app's memory, and asks the screenshot editor's question,
/// private and not. Last it runs the menu's own flow (`-FieldCaptureFlow
/// pdf|image`, image unless given), toast and share sheet included, while
/// the page scrolls, for the video. Everything lands in
/// Documents/CaptureHarness, and each line is printed as
/// `[FieldCaptureHarness] …`. Started by CaptureHarnessLoader.m.
@objc(FieldCaptureHarness) final class CaptureHarness: NSObject {
    @objc static func start() {
        Task { await run() }
    }

    private static let out = URL.documentsDirectory.appendingPathComponent("CaptureHarness", isDirectory: true)
    private static var report: [String] = []

    private static func run() async {
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard let (surface, browser) = await found() else { return say("no browser found") }
        for _ in 0..<600 where !browser.tab.isPainted || browser.tab.isLoading {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let web = browser.tab.web, browser.tab.isPainted else { return say("the page never painted") }
        // Late images and fonts.
        try? await Task.sleep(for: .seconds(2))
        let defaults = UserDefaults.standard
        let scroll = defaults.object(forKey: "FieldCaptureScroll") == nil ? 1500 : defaults.double(forKey: "FieldCaptureScroll")
        web.scrollView.setContentOffset(CGPoint(x: 0, y: scroll - web.scrollView.adjustedContentInset.top), animated: false)
        try? await Task.sleep(for: .milliseconds(500))
        say("page \(web.url?.absoluteString ?? "?"), content \(Int(web.scrollView.contentSize.width))×\(Int(web.scrollView.contentSize.height)) pt, scrolled to \(Int(web.scrollView.contentOffset.y))")

        let capture = Capture(page: { browser.tab }, announce: { browser.toaster.show($0) })
        for kind in [PageCapture.Kind.pdf, .image] {
            var made: URL?
            await measure("\(kind)") {
                made = try await capture.make(kind)
                return made?.lastPathComponent ?? "busy"
            }
            guard let file = made else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            try? FileManager.default.copyItem(at: file, to: out.appendingPathComponent(file.lastPathComponent))
            say("  \(size / 1024) KB\(kind == .image ? ", \(pixels(file))" : "")")
        }
        // The PDF alone, apart from writing it: what WebKit takes.
        await measure("createPDF alone") {
            let pdf = try await PageCapture.pdf(of: web)
            let pages = PageCapture.pageSizes(pdf)
            return "\(pdf.count / 1024) KB, \(pages.count) page(s), \(Int(TallImage.stacked(pages).height)) pt tall"
        }

        if defaults.bool(forKey: "FieldCaptureCompare") { await compare(web) }

        let (full, index, rect) = await capture.fullPage()
        if let full { try? full.write(to: out.appendingPathComponent("full-page.pdf")) }
        say("Full Page: \(full.map { "\($0.count / 1024) KB" } ?? "nil"), page \(index), rect \(rect); visible \(web.scrollView.bounds), content \(web.scrollView.contentSize), pages \(full.map(PageCapture.pageSizes) ?? [])")
        capture.isPrivate = { true }
        let (hidden, _, _) = await capture.fullPage()
        say("Full Page, private: \(hidden == nil ? "nil" : "DATA (wrong)")")
        capture.isPrivate = { false }

        // What the menu does, on camera: a flick of the page as it starts,
        // which must keep moving.
        let flow: PageCapture.Kind = defaults.string(forKey: "FieldCaptureFlow") == "pdf" ? .pdf : .image
        try? await Task.sleep(for: .seconds(1))
        say("flow \(flow) starts")
        capture.capture(flow, from: surface, source: surface.view)
        let offset = web.scrollView.contentOffset
        web.scrollView.setContentOffset(CGPoint(x: 0, y: offset.y + 900), animated: true)
        try? report.joined(separator: "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        say("done, files in \(out.path)")
    }

    /// Times `work`, and watches the main thread (the longest it went
    /// without running a 1 ms timer) and the app's footprint while it runs.
    private static func measure(_ name: String, _ work: () async throws -> String) async {
        let watch = MainWatch()
        let memory = Footprint()
        let before = Footprint.now()
        let start = ContinuousClock.now
        let result: String
        do { result = try await work() } catch { result = "failed: \(error)" }
        let took = ContinuousClock.now - start
        let longest = watch.stop()
        let peak = memory.stop()
        say("\(name): \(ms(took)), main thread held at most \(ms(longest)), footprint \(before >> 20) → peak \(peak >> 20) MB; \(result)")
    }

    /// `-FieldCaptureCompare YES`: the routes not taken, for looking at side
    /// by side. One snapshot whose rect is the whole content, then tiles of
    /// the screen, scrolled one screen at a time (which the person would see).
    private static func compare(_ web: WKWebView) async {
        let scroll = web.scrollView
        let content = scroll.contentSize
        let home = scroll.contentOffset
        await measure("snapshot of the whole content") {
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: -home.y, width: content.width, height: content.height)
            config.snapshotWidth = NSNumber(value: Double(content.width) / 1.5)
            let image = try await web.takeSnapshot(configuration: config)
            try image.pngData()?.write(to: out.appendingPathComponent("compare-snapshot.png"))
            return "\(Int(image.size.width * image.scale))×\(Int(image.size.height * image.scale)) px"
        }
        await measure("tiles, scrolling") {
            let screen = scroll.bounds.height
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            var tiles: [(CGFloat, UIImage)] = []
            var y: CGFloat = 0
            while y < content.height {
                let at = max(0, min(y, content.height - screen))
                scroll.setContentOffset(CGPoint(x: 0, y: at), animated: false)
                try await Task.sleep(for: .milliseconds(120))
                tiles.append((at, try await web.takeSnapshot(configuration: WKSnapshotConfiguration())))
                y += screen
            }
            scroll.setContentOffset(home, animated: false)
            let sheet = UIGraphicsImageRenderer(size: CGSize(width: content.width, height: content.height), format: format).pngData { _ in
                for (y, tile) in tiles { tile.draw(at: CGPoint(x: 0, y: y)) }
            }
            try sheet.write(to: out.appendingPathComponent("compare-tiles.png"))
            return "\(tiles.count) tiles"
        }
    }

    private static func pixels(_ file: URL) -> String {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return "?" }
        return "\(props[kCGImagePropertyPixelWidth] ?? "?")×\(props[kCGImagePropertyPixelHeight] ?? "?") px"
    }

    /// The bar's controller, and the browser it holds, from the window.
    private static func found() async -> (FieldSurface, Browser)? {
        for _ in 0..<100 {
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            for window in windows {
                if let surface = find(in: window),
                   let browser = Mirror(reflecting: surface).children.first(where: { $0.label == "browser" })?.value as? Browser {
                    return (surface, browser)
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private static func find(in view: UIView) -> FieldSurface? {
        if let surface = view.next as? FieldSurface { return surface }
        for sub in view.subviews { if let surface = find(in: sub) { return surface } }
        return nil
    }

    private static func say(_ line: String) {
        print("[FieldCaptureHarness] \(line)")
        report.append(line)
    }

    private static func ms(_ d: Duration) -> String {
        let (s, atto) = d.components
        return String(format: "%.1f ms", Double(s) * 1000 + Double(atto) / 1e15)
    }
}

/// The longest gap between fires of a 1 ms timer on the main run loop.
private final class MainWatch {
    private var timer: Timer?
    private var tick = ContinuousClock.now
    private var longest = Duration.zero

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ContinuousClock.now
                self.longest = max(self.longest, now - self.tick)
                self.tick = now
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() -> Duration {
        timer?.invalidate()
        return max(longest, ContinuousClock.now - tick)
    }
}

/// The app's physical footprint, as jetsam counts it, sampled every 2 ms on
/// a thread of its own; `stop` gives the highest.
private nonisolated final class Footprint: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    private var peak: UInt64 = 0

    init() {
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                let now = Footprint.now()
                lock.withLock { peak = max(peak, now) }
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
    }

    func stop() -> UInt64 {
        lock.withLock {
            running = false
            return max(peak, Footprint.now())
        }
    }

    static func now() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
#endif
