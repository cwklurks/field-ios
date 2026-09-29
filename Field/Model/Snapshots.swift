import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// A picture of each tab: what its card shows in the grid, what the carousel
/// shows beside the page, and what covers a sleeping tab while it wakes.
///
/// Kept as JPEG in Caches (iOS may clear them, and a tab without its picture
/// just shows its letter), and held decoded in memory up to a limit, so the
/// grid never decodes on the main thread. Encoding and decoding both happen
/// off it.
@MainActor final class Snapshots {
    /// Half the screen's width in points: sharp on a card, and soft only
    /// briefly as a wake cover, for about 3 MB decoded instead of 12.
    nonisolated static let width: CGFloat = 201

    /// Nil keeps them in memory only (private tabs, the perf tests' seed).
    let directory: URL?
    private let memory = NSCache<NSUUID, UIImage>()
    private var loading: [UUID: Task<UIImage?, Never>] = [:]

    init(directory: URL?) {
        self.directory = directory
        // About twenty pictures; the grid's visible cards and their
        // neighbours fit with room to spare.
        memory.totalCostLimit = 64 << 20
    }

    /// What's in memory, now. Nil means not loaded, not "none".
    func image(_ id: UUID) -> UIImage? {
        memory.object(forKey: id as NSUUID)
    }

    /// From memory, or read and decoded off the main thread.
    func load(_ id: UUID) async -> UIImage? {
        if let image = image(id) { return image }
        if let running = loading[id] { return await running.value }
        guard let file = file(id) else { return nil }
        let task = Task.detached(priority: .userInitiated) { Snapshots.decode(file) }
        loading[id] = task
        let image = await task.value
        loading[id] = nil
        if let image { keep(image, id) }
        return image
    }

    /// A new picture: in memory now, on disk shortly.
    func put(_ image: UIImage, for id: UUID) {
        keep(image, id)
        guard let file = file(id), let cg = image.cgImage else { return }
        Task.detached(priority: .utility) { Snapshots.encode(cg, to: file) }
    }

    func remove(_ id: UUID) {
        memory.removeObject(forKey: id as NSUUID)
        guard let file = file(id) else { return }
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file) }
    }

    /// Clears out pictures of tabs that are gone, off the main thread.
    func prune(keeping ids: Set<UUID>) {
        guard let directory else { return }
        let names = Set(ids.map { "\($0.uuidString).jpg" })
        Task.detached(priority: .background) {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where !names.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Memory is short: iOS empties the cache itself, but not before the
    /// warning's handlers have run.
    func trim() {
        memory.removeAllObjects()
    }

    private func keep(_ image: UIImage, _ id: UUID) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        memory.setObject(image, forKey: id as NSUUID, cost: Int(pixels) * 4)
    }

    private func file(_ id: UUID) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString).jpg")
    }

    /// Read and decoded here, not on first draw: `ShouldCacheImmediately`
    /// makes ImageIO produce the bitmap now.
    /// Its size in points is always `width` wide, whatever the screen.
    nonisolated static func decode(_ file: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { return nil }
        return UIImage(cgImage: image, scale: CGFloat(image.width) / Snapshots.width, orientation: .up)
    }

    nonisolated static func encode(_ image: CGImage, to file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = file.appendingPathExtension("part")
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return }
        _ = try? FileManager.default.replaceItemAt(file, withItemAt: temporary)
    }
}
