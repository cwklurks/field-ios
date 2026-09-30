import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The whole page as one tall picture, drawn from its PDF. A page too long
/// for one image iOS can hold comes out smaller, never cut off.
nonisolated enum TallImage {
    /// The longest side Photos, Messages and the GPU all take whole.
    static let maxSide = 16_384
    /// 64 MB as a bitmap: the most the drawing holds at once.
    static let maxPixels = 16_384 * 1_024

    /// Pixels for a page `size` points big: `scale` pixels to the point,
    /// or fewer when that would pass either cap. Nil when there's nothing
    /// to draw.
    static func pixels(for size: CGSize, scale: CGFloat) -> (width: Int, height: Int, scale: CGFloat)? {
        guard size.width > 0, size.height > 0, scale > 0 else { return nil }
        let side = CGFloat(maxSide)
        let fit = min(
            scale,
            side / size.width,
            side / size.height,
            (CGFloat(maxPixels) / (size.width * size.height)).squareRoot()
        )
        // Rounded down, so rounding never lands a pixel over a cap; the
        // nudge keeps 16383.9999 from losing a whole pixel.
        let width = max(1, min(maxSide, Int((size.width * fit + 0.001).rounded(.down))))
        let height = max(1, min(maxSide, Int((size.height * fit + 0.001).rounded(.down))))
        return (width, height, fit)
    }

    /// The pages one under the other, as wide as the widest.
    static func stacked(_ pages: [CGSize]) -> CGSize {
        pages.reduce(.zero) { CGSize(width: max($0.width, $1.width), height: $0.height + $1.height) }
    }

    /// The PDF's pages drawn one under the other into a single PNG at `to`.
    /// Slow on a long page, so never on the main thread.
    static func write(pdf: Data, scale: CGFloat, to url: URL) throws {
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages > 0 else { throw CaptureError.unreadable }
        let pages = (1...document.numberOfPages).compactMap(document.page(at:))
        let sizes = pages.map { $0.getBoxRect(.mediaBox).size }
        guard let pixels = pixels(for: stacked(sizes), scale: scale),
              let context = CGContext(
                data: nil, width: pixels.width, height: pixels.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { throw CaptureError.tooBig }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height))
        context.interpolationQuality = .high
        context.scaleBy(x: pixels.scale, y: pixels.scale)
        // PDF space starts at the bottom, so the first page is drawn highest.
        var top = stacked(sizes).height
        for (page, size) in zip(pages, sizes) {
            top -= size.height
            context.saveGState()
            context.translateBy(x: 0, y: top)
            context.drawPDFPage(page)
            context.restoreGState()
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CaptureError.tooBig }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.unwritable }
    }
}

nonisolated enum CaptureError: Error {
    case unreadable, tooBig, unwritable, nothingToCapture
}
