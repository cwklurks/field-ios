import Foundation

/// Tabs closed, newest first, each with the place it had, so reopening puts
/// it back there. Kept in memory only.
public struct RecentlyClosed<Item> {
    public struct Closed {
        public let item: Item
        public let index: Int
    }

    public let cap: Int
    private var stack: [Closed] = []

    public init(cap: Int = 20) {
        self.cap = cap
    }

    public var isEmpty: Bool { stack.isEmpty }
    public var count: Int { stack.count }
    /// Newest first.
    public var items: [Item] { stack.map(\.item) }

    /// Returns the one that fell off the end, if one did.
    @discardableResult
    public mutating func push(_ item: Item, at index: Int) -> Item? {
        stack.insert(Closed(item: item, index: index), at: 0)
        guard stack.count > cap else { return nil }
        return stack.removeLast().item
    }

    public mutating func pop() -> Closed? {
        stack.isEmpty ? nil : stack.removeFirst()
    }

    /// By position in `items`.
    public mutating func remove(at position: Int) -> Closed {
        stack.remove(at: position)
    }
}
