// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation

// What was open last time. A list of addresses and their names, and which one
// you were looking at, as on the Mac; plus what a phone needs to bring a tab
// back without loading it: its id, which names its snapshot in Caches, and
// WebKit's `interactionState`, the back and forward list and where the page
// was scrolled to. Tabs can sit in named groups (Tidy, M6), and each keeps
// when it was last looked at, for the stale-tab banner.

public enum Session {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        /// Empty for a blank tab.
        public var url: String
        public var title: String
        /// Opaque to Field: whatever `WKWebView.interactionState` gave.
        public var interactionState: Data?
        /// The group it's in, one of `Shape.groups`; nil when it's loose.
        public var group: UUID?
        /// When it was last on screen; nil until Field first sees it.
        public var viewed: Date?

        public init(id: UUID = UUID(), url: String, title: String, interactionState: Data? = nil,
                    group: UUID? = nil, viewed: Date? = nil) {
            self.id = id
            self.url = url
            self.title = title
            self.interactionState = interactionState
            self.group = group
            self.viewed = viewed
        }

        enum CodingKeys: String, CodingKey {
            case id, url, title, interactionState, group, viewed
        }

        /// The Mac's entries have no id and no state; its pin and name are
        /// passed over.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            url = try c.decode(String.self, forKey: .url)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            interactionState = try c.decodeIfPresent(Data.self, forKey: .interactionState)
            group = try c.decodeIfPresent(UUID.self, forKey: .group)
            viewed = try c.decodeIfPresent(Date.self, forKey: .viewed)
        }
    }

    /// A named set of tabs, shown as a section of the grid.
    public struct Group: Codable, Equatable, Sendable, Identifiable {
        public var id: UUID
        public var name: String

        public init(id: UUID = UUID(), name: String) {
            self.id = id
            self.name = name
        }
    }

    public struct Shape: Codable, Equatable, Sendable {
        public var tabs: [Entry]
        public var active: Int
        /// In the order the grid shows them. Only groups some tab is in.
        public var groups: [Group]

        /// A tab pointing at a group that isn't in `groups` is loose, and a
        /// group no tab is in is dropped, so the two always agree.
        public init(tabs: [Entry] = [], active: Int = 0, groups: [Group] = []) {
            var seen = Set<UUID>()
            let named = groups.filter { seen.insert($0.id).inserted }
            let known = Set(named.map(\.id))
            let tabs = tabs.map { entry -> Entry in
                guard let group = entry.group, !known.contains(group) else { return entry }
                var loose = entry
                loose.group = nil
                return loose
            }
            let used = Set(tabs.compactMap(\.group))
            self.tabs = tabs
            self.active = Shape.clamp(active, tabs.count)
            self.groups = named.filter { used.contains($0.id) }
        }

        enum CodingKeys: String, CodingKey {
            case tabs, active, groups
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let tabs = try c.decode([Entry].self, forKey: .tabs)
            self.init(tabs: tabs, active: try c.decodeIfPresent(Int.self, forKey: .active) ?? 0,
                      groups: try c.decodeIfPresent([Group].self, forKey: .groups) ?? [])
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
