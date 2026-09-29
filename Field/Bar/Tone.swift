import SwiftUI
import UIKit
import WebKit

/// Light or dark, from what's under the bar, and slow to change its mind: a
/// reading has to be clearly the other side of the middle before the tone
/// turns, so a boundary sitting under the bar doesn't make it flicker.
struct ToneReading: Equatable {
    /// Luma below this reads dark, above `light` light; between, the tone stays.
    static let dark = 0.4
    static let light = 0.6

    private(set) var tone: ColorScheme?

    /// Returns whether the tone changed. Nil (nothing to read) keeps it.
    mutating func read(_ luma: Double?) -> Bool {
        guard let luma else { return false }
        let next: ColorScheme
        switch tone {
        case nil: next = luma < 0.5 ? .dark : .light
        case .dark?: next = luma > Self.light ? .light : .dark
        case .light?: next = luma < Self.dark ? .dark : .light
        @unknown default: next = luma < 0.5 ? .dark : .light
        }
        guard next != tone else { return false }
        tone = next
        return true
    }

    /// How bright pixels look on average (Rec. 709), from 8-bit RGBA, or
    /// nil for none. Mostly see-through pixels count for nothing.
    static func luma(rgba bytes: [UInt8]) -> Double? {
        var sum = 0.0
        var count = 0
        var i = 0
        while i + 3 < bytes.count {
            if bytes[i + 3] > 127 {
                sum += 0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])
                count += 1
            }
            i += 4
        }
        return count == 0 ? nil : sum / Double(count) / 255
    }
}

/// Looks at the page under the bar now and then: a picture a few pixels
/// wide of just that strip, taken by WebKit, averaged. Never on the scroll's
/// own path. A slow timer asks whether the page has moved (or, less often,
/// whether it might have changed by itself), and takes one picture at a time.
final class ToneSampler {
    /// How often the timer looks. A picture is taken only if something moved.
    static let interval: Duration = .milliseconds(150)
    /// Even when nothing moved, a page can change under the bar.
    static let idle: Duration = .seconds(2)

    /// Called with the new tone when it turns.
    var changed: (ColorScheme?) -> Void = { _ in }
    /// Where to look, in the web view's coordinates; nil when there's no bar
    /// to look under (the field is open).
    var strip: () -> CGRect? = { nil }
    /// The tab's picture, and where the bar is over it in its points: what's
    /// under the bar while the page itself isn't drawn, asleep or waking.
    var picture: () -> (UIImage, CGRect)? = { nil }

    private(set) var reading = ToneReading()
    private weak var web: WKWebView?
    private var timer: Task<Void, Never>?
    private var busy = false
    private var lastOffset: CGPoint?
    private var lastLook: ContinuousClock.Instant?

    /// Watches this web view from now on; nil stops. `fresh` starts again
    /// even with the same one: another tab, which may have none either.
    /// Until the page is drawn, its picture is read, at once.
    func watch(_ web: WKWebView?, fresh: Bool = false) {
        guard fresh || web !== self.web else { return }
        self.web = web
        reading = ToneReading()
        lastOffset = nil
        if web.map({ $0.alpha == 0 }) ?? true { _ = reading.read(pictureLuma()) }
        changed(reading.tone)
        timer?.cancel()
        guard web != nil else { return }
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                self?.tick()
            }
        }
    }

    /// Look now, whatever moved: a new page painted, the bar came back.
    func look() {
        lastOffset = nil
        tick()
    }

    private func tick() {
        guard !busy, let web, web.window != nil, web.alpha > 0,
              UIApplication.shared.applicationState == .active,
              let rect = strip(), !rect.isEmpty else { return }
        let offset = web.scrollView.contentOffset
        let now = ContinuousClock.now
        let stale = lastLook.map { now - $0 > Self.idle } ?? true
        guard offset != lastOffset || stale else { return }
        lastOffset = offset
        lastLook = now
        busy = true
        let config = WKSnapshotConfiguration()
        config.rect = rect
        config.snapshotWidth = 24
        config.afterScreenUpdates = false
        web.takeSnapshot(with: config) { [weak self] image, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.busy = false
                let luma = image?.cgImage.flatMap(Self.luma)
                // Nothing drawn there yet (a page just placed, or still
                // sliding in): look again on the next tick.
                if luma == nil { self.lastOffset = nil }
                guard self.reading.read(luma) else { return }
                self.changed(self.reading.tone)
            }
        }
    }

    private func pictureLuma() -> Double? {
        guard let (image, rect) = picture(), let cg = image.cgImage else { return nil }
        let s = image.scale
        let pixels = CGRect(x: rect.minX * s, y: rect.minY * s, width: rect.width * s, height: rect.height * s).integral
        return cg.cropping(to: pixels).flatMap(Self.luma)
    }

    private static func luma(of cg: CGImage) -> Double? {
        let width = 12, height = 4
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? ToneReading.luma(rgba: bytes) : nil
    }
}
