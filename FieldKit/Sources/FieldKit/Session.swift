// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation

// What was open last time. A list of addresses and their names, and which one
// you were looking at, as on the Mac; plus what a phone needs to bring a tab
// back without loading it: its id, which names its snapshot in Caches, and
// WebKit's `interactionState`, the back and forward list and where the page
// was scrolled to.

public enum Session {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        /// Empty for a blank tab.
        public var url: String
        public var title: String
        /// Opaque to Field: whatever `WKWebView.interactionState` gave.
        public var interactionState: Data?

        public init(id: UUID = UUID(), url: String, title: String, interactionState: Data? = nil) {
            self.id = id
            self.url = url
            self.title = title
            self.interactionState = interactionState
        }

        enum CodingKeys: String, CodingKey {
            case id, url, title, interactionState
        }

        /// The Mac's entries have no id and no state; its pin and name are
        /// passed over.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            url = try c.decode(String.self, forKey: .url)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            interactionState = try c.decodeIfPresent(Data.self, forKey: .interactionState)
        }
    }

    public struct Shape: Codable, Equatable, Sendable {
        public var tabs: [Entry]
        public var active: Int

        public init(tabs: [Entry] = [], active: Int = 0) {
            self.tabs = tabs
            self.active = Shape.clamp(active, tabs.count)
        }

        enum CodingKeys: String, CodingKey {
            case tabs, active
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let tabs = try c.decode([Entry].self, forKey: .tabs)
            self.init(tabs: tabs, active: try c.decodeIfPresent(Int.self, forKey: .active) ?? 0)
        }

        private static func clamp(_ active: Int, _ count: Int) -> Int {
            max(0, min(active, count - 1))
        }

        /// No file is an empty session, and so is a file that isn't one,
        /// which is set aside first rather than saved over. Anything else
        /// that stops the read (a protected file before first unlock)
        /// throws, and the caller mustn't save until a read has worked.
        public static func load(from file: URL) throws -> Shape {
            let data: Data
            do {
                data = try Data(contentsOf: file)
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return Shape()
            }
            guard let shape = try? JSONDecoder().decode(Shape.self, from: data) else {
                Store.quarantine(file)
                return Shape()
            }
            return shape
        }

        /// Off the main thread: with each tab's state inside, it can run to
        /// megabytes.
        public func save(to file: URL) throws {
            let data = try JSONEncoder().encode(self)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: file, options: .atomic)
        }
    }
}
