import Foundation

// Tab groups as the grid and Tidy see them: which groups there are, in
// order, and which tab is in which. Taken from a session, changed as a
// whole (Tidy's Apply, "Add similar tabs") and put back as a whole, so Undo
// is only the grouping from before.

extension Session {
    public struct Grouping: Equatable, Sendable {
        public var groups: [Group]
        /// Tab id to group id; a tab not here is loose.
        public var membership: [UUID: UUID]

        public init(groups: [Group] = [], membership: [UUID: UUID] = [:]) {
            self.groups = groups
            self.membership = membership
        }

        /// Tidy's groups, applied: each tab named moves to its group, a
        /// group named like one already there (in any case) is that one,
        /// and any other gets a new id. Tabs not named stay where they are;
        /// a group left with no tabs goes.
        public func applying(_ suggested: [TidyGroup]) -> Grouping {
            var groups = self.groups
            var membership = self.membership
            for group in suggested where !group.ids.isEmpty {
                let key = Tidy.key(group.name)
                let id: UUID
                if let known = groups.first(where: { Tidy.key($0.name) == key }) {
                    id = known.id
                } else {
                    id = UUID()
                    groups.append(Group(id: id, name: group.name))
                }
                for tab in group.ids { membership[tab] = id }
            }
            let used = Set(membership.values)
            return Grouping(groups: groups.filter { used.contains($0.id) }, membership: membership)
        }

        /// "Add similar tabs": `tabs` join the group `id`, if it's there.
        public func adding(_ tabs: [UUID], to id: UUID) -> Grouping {
            guard groups.contains(where: { $0.id == id }) else { return self }
            var grown = self
            for tab in tabs { grown.membership[tab] = id }
            let used = Set(grown.membership.values)
            grown.groups = grown.groups.filter { used.contains($0.id) }
            return grown
        }

        public struct Section<Item> {
            /// Nil for the loose tabs.
            public let group: Group?
            public let items: [Item]
        }

        /// The grid's sections: each group in order with its tabs in the
        /// order given, then the loose tabs, which is where a new tab lands.
        /// Empty sections are left out, but with no tabs at all there's one
        /// loose section, as the grid had before groups.
        public func sections<Item>(_ items: [Item], id: (Item) -> UUID) -> [Section<Item>] {
            var byGroup: [UUID: [Item]] = [:]
            var loose: [Item] = []
            let known = Set(groups.map(\.id))
            for item in items {
                if let group = membership[id(item)], known.contains(group) {
                    byGroup[group, default: []].append(item)
                } else {
                    loose.append(item)
                }
            }
            var sections = groups.compactMap { group in
                byGroup[group.id].map { Section(group: group, items: $0) }
            }
            if !loose.isEmpty || sections.isEmpty { sections.append(Section(group: nil, items: loose)) }
            return sections
        }
    }
}

extension Session.Shape {
    public var grouping: Session.Grouping {
        var membership: [UUID: UUID] = [:]
        for tab in tabs { if let group = tab.group { membership[tab.id] = group } }
        return Session.Grouping(groups: groups, membership: membership)
    }

    /// The same tabs, grouped as `grouping` says. A tab it doesn't mention
    /// is loose; a tab it mentions that has since closed is passed over.
    public func regrouped(_ grouping: Session.Grouping) -> Session.Shape {
        let tabs = self.tabs.map { entry -> Session.Entry in
            var moved = entry
            moved.group = grouping.membership[entry.id]
            return moved
        }
        return Session.Shape(tabs: tabs, active: active, groups: grouping.groups)
    }
}
