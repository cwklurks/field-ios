import Foundation
import Testing
import UIKit
@testable import Field

/// The tab on screen at launch has its picture for the first frame: read
/// off the main thread from the start of the launch, and picked up, or
/// briefly waited for, when the page is first placed.
@MainActor struct SnapshotsTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "SnapshotsTests-\(UUID().uuidString)")

    private func picture() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        return UIGraphicsImageRenderer(size: CGSize(width: Snapshots.width, height: 40), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: Snapshots.width, height: 40))
        }
    }

    /// A picture on disk for a new id.
    private func saved() throws -> UUID {
        let id = UUID()
        let cg = try #require(picture().cgImage)
        Snapshots.encode(cg, to: directory.appendingPathComponent("\(id.uuidString).jpg"))
        return id
    }

    @Test func waitsForThePrefetchAndKeepsIt() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try saved()
        let snapshots = Snapshots(directory: directory)
        snapshots.prefetch(id)
        let image = try #require(snapshots.picture(id, waiting: 1))
        #expect(image.size.width == Snapshots.width)
        #expect(snapshots.image(id) === image)
    }

    @Test func anAsyncLoadJoinsThePrefetch() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try saved()
        let snapshots = Snapshots(directory: directory)
        snapshots.prefetch(id)
        let image = try #require(await snapshots.load(id))
        #expect(snapshots.picture(id, waiting: 0) === image)
    }

    /// Only the launch's prefetch is waited for: nothing else is read on
    /// the main thread.
    @Test func neverReadsTheDiskItself() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = try saved()
        #expect(Snapshots(directory: directory).picture(id, waiting: 0.1) == nil)
    }

    @Test func givesWhatsInMemoryFirst() {
        let snapshots = Snapshots(directory: nil)
        let id = UUID()
        let image = picture()
        snapshots.put(image, for: id)
        #expect(snapshots.picture(id, waiting: 0) === image)
    }

    @Test func noPictureIsNil() {
        let snapshots = Snapshots(directory: directory)
        let id = UUID()
        snapshots.prefetch(id)
        #expect(snapshots.picture(id, waiting: 0.1) == nil)
    }
}
