import CoreGraphics
import Foundation
import WebKit

/// A page, whole, from what's already loaded. WebKit draws it into a PDF in
/// the page's own process, so nothing is fetched and the main thread only
/// waits; turning that into a file, and a PDF into a picture, happens off it.
enum PageCapture {
    enum Kind: Sendable {
        /// Exact: text stays text, and the page is as long as it is.
        case pdf
        /// One tall PNG drawn from the PDF, smaller if the page is very long.
        case image

        var fileExtension: String { self == .pdf ? "pdf" : "png" }
    }

    /// Pixels to the point for the image: sharp in Messages and Photos, and
    /// with room for a long page before it has to shrink (TallImage).
    nonisolated static let imageScale: CGFloat = 2

    /// The whole document, top to bottom, wherever it's scrolled to.
    static func pdf(of web: WKWebView) async throws -> Data {
        try await web.pdf(configuration: WKPDFConfiguration())
    }

    /// The page's PDF written as `name` in a folder of its own under the
    /// temporary directory, or drawn into an image there. Off the main thread.
    nonisolated static func write(_ pdf: Data, as kind: Kind, named name: String) throws -> URL {
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(name)
        switch kind {
        case .pdf: try pdf.write(to: file, options: .completeFileProtection)
        case .image: try TallImage.write(pdf: pdf, scale: imageScale, to: file)
        }
        return file
    }

    /// Where captures wait to be shared. Each goes once its share sheet
    /// closes, and anything left from before goes with the next capture.
    nonisolated static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Capture", isDirectory: true)

    nonisolated static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The size of each of the PDF's pages, top to bottom.
    nonisolated static func pageSizes(_ pdf: Data) -> [CGSize] {
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages > 0 else { return [] }
        return (1...document.numberOfPages).compactMap { document.page(at: $0)?.getBoxRect(.mediaBox).size }
    }
}
