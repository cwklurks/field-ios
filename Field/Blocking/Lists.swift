import Foundation

/// What scripts/lists/build.sh shipped: which lists, in which files, and a
/// sha256 of each list's JSON. Each list is compiled under an identifier
/// made from that sha, so a build with a changed list compiles it again,
/// and one without leaves the compiled copy alone.
nonisolated struct BlockingManifest: Decodable, Sendable, Equatable {
    struct List: Decodable, Sendable, Equatable {
        let name: String
        let file: String
        let rules: Int
        let sha256: String
    }

    let lists: [List]
    /// Where the list files sit: beside the manifest.
    var directory: URL?

    private enum CodingKeys: String, CodingKey { case lists }

    /// Every identifier Field compiles under starts with this; anything else
    /// in the store isn't Field's to remove.
    static let prefix = "field.blocking."
    static let resource = "blocking-manifest"

    var identifiers: [String] {
        lists.map { "\(Self.prefix)\($0.name).\($0.sha256.prefix(16))" }
    }

    /// Lists Field compiled once that this build no longer ships.
    func stale(among stored: [String]) -> [String] {
        let wanted = Set(identifiers)
        return stored.filter { $0.hasPrefix(Self.prefix) && !wanted.contains($0) }
    }

    static func bundled(_ bundle: Bundle = .main) -> BlockingManifest? {
        bundle.url(forResource: resource, withExtension: "json").flatMap(load(from:))
    }

    static func load(from url: URL) -> BlockingManifest? {
        guard let data = try? Data(contentsOf: url),
              var manifest = try? JSONDecoder().decode(BlockingManifest.self, from: data) else { return nil }
        manifest.directory = url.deletingLastPathComponent()
        return manifest
    }
}

/// The lists ship gzipped (about 0.6 MB each instead of 7). Foundation only
/// inflates raw deflate, so this reads gzip's header and trailer around it
/// (RFC 1952).
nonisolated enum Gzip {
    enum Failure: Error { case notGzip, corrupt }

    static func inflate(_ data: Data) throws -> Data {
        let bytes = [UInt8](data.prefix(10))
        guard bytes.count == 10, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8, data.count >= 18 else {
            throw Failure.notGzip
        }
        let flags = bytes[3]
        var start = data.startIndex + 10
        func skipString() throws {
            guard let end = data[start...].firstIndex(of: 0) else { throw Failure.corrupt }
            start = end + 1
        }
        if flags & 0x04 != 0 {
            guard start + 2 <= data.endIndex else { throw Failure.corrupt }
            start += 2 + Int(data[start]) + Int(data[start + 1]) << 8
        }
        if flags & 0x08 != 0 { try skipString() }
        if flags & 0x10 != 0 { try skipString() }
        if flags & 0x02 != 0 { start += 2 }
        let end = data.endIndex - 8
        guard start <= end else { throw Failure.corrupt }
        let size = data[end + 4 ..< data.endIndex].reversed().reduce(0) { $0 << 8 | Int($1) }
        guard let inflated = try? (data[start..<end] as NSData).decompressed(using: .zlib) as Data,
              inflated.count & 0xffff_ffff == size else { throw Failure.corrupt }
        return inflated
    }
}
