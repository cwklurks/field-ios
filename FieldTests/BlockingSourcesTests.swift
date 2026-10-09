import CryptoKit
import Foundation
import Testing
@testable import Field

/// Where each shipped list came from: every list file has a manifest entry
/// whose sha256 is its JSON's, a licence, and sources that are recorded and
/// kept in scripts/lists/sources, byte for byte. So the repository at any
/// commit holds the exact source of the lists it ships.
struct BlockingSourcesTests {
    private struct Manifest: Decodable {
        struct List: Decodable {
            let name: String
            let file: String
            let licence: String
            let sources: [String]
            let sha256: String
        }

        struct Source: Decodable, Equatable {
            let name: String
            let file: String
            let url: String
            let revision: String?
            let version: String
            let sha256: String
            let fetched: String
            let licence: String
            let note: String?
        }

        struct Tool: Decodable {
            let name: String
            let sha256: String
        }

        let tools: [Tool]
        let sources: [Source]
        let lists: [List]
    }

    private var directory: URL {
        get throws { try #require(BlockingManifest.bundled()?.directory) }
    }
    private var manifest: Manifest {
        get throws {
            let data = try Data(contentsOf: directory.appendingPathComponent("\(BlockingManifest.resource).json"))
            return try JSONDecoder().decode(Manifest.self, from: data)
        }
    }

    /// scripts/lists/sources in this checkout: the simulator reads the Mac's disk.
    private let sources = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "scripts/lists/sources", directoryHint: .isDirectory)

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test func everyShippedFileIsInTheManifestWithItsHash() throws {
        let manifest = try manifest, directory = try directory
        let shipped = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".json.gz") }
        #expect(!shipped.isEmpty)
        #expect(Set(shipped) == Set(manifest.lists.map(\.file)))
        for list in manifest.lists {
            let json = try Gzip.inflate(Data(contentsOf: directory.appendingPathComponent(list.file)))
            #expect(sha256(json) == list.sha256, "\(list.file) isn't what the manifest says")
        }
    }

    @Test func everyListHasALicenceAndRecordedSources() throws {
        let manifest = try manifest
        let recorded = Set(manifest.sources.map(\.name))
        for list in manifest.lists {
            #expect(["CC-BY-SA-3.0", "GPL-3.0-only"].contains(list.licence), "\(list.name): \(list.licence)")
            #expect(!list.sources.isEmpty, "\(list.name) has no sources")
            #expect(Set(list.sources).isSubset(of: recorded), "\(list.name) names a source with no record")
        }
        for source in manifest.sources {
            #expect(source.sha256.count == 64 && !source.version.isEmpty && !source.licence.isEmpty, "\(source.name)")
            #expect(source.url.hasPrefix("https://") && !source.fetched.isEmpty, "\(source.name)")
            // Pinned to a revision, or saying why it can't be.
            #expect(source.revision != nil || source.note != nil, "\(source.name) has no revision")
        }
        #expect(manifest.tools.map(\.name) == ["ConverterTool", "swift-psl"])
        #expect(manifest.tools.allSatisfy { $0.sha256.count == 64 })
    }

    /// The copies in the repository are the ones recorded, and the record
    /// the app ships is the repository's.
    @Test func theSourcesAreInTheRepository() throws {
        let manifest = try manifest
        let record = try JSONDecoder().decode(
            [Manifest.Source].self, from: Data(contentsOf: sources.appending(path: "sources.json"))
        )
        #expect(record == manifest.sources)
        let kept = try FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".txt.gz") }
        #expect(Set(kept) == Set(record.map(\.file)))
        for source in record {
            let text = try Gzip.inflate(Data(contentsOf: sources.appending(path: source.file)))
            #expect(sha256(text) == source.sha256, "\(source.file) isn't what sources.json says")
        }
    }
}
