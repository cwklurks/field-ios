import FieldKit
import SwiftUI

/// What the Tidy sheet shows and changes: the proposed groups as they
/// stream in, their names as edited, which tabs are checked, and which
/// group each is in. Nothing here touches the tabs themselves; Apply hands
/// the result to TidyFlow.
@MainActor @Observable final class TidyDraft {
    enum Mode: Equatable {
        /// Groups for every tab.
        case tidy
        /// "Add similar tabs" to the group `group`, called `name`.
        case similar(group: UUID, name: String)
    }

    struct Section: Identifiable, Equatable {
        let id: UUID
        var name: String
        var tabs: [UUID]
    }

    let mode: Mode
    /// Every tab the draft may show, by id.
    let info: [UUID: TabInfo]
    private(set) var sections: [Section] = []
    private(set) var thinking = true
    private(set) var engine: TidyEngineKind?
    private var unchecked = Set<UUID>()
    /// Each group's suggested name, for a name cleared by hand.
    @ObservationIgnored private var suggested: [UUID: String] = [:]
    /// A group keeps its identity while it streams in and grows, by name.
    @ObservationIgnored private var keys: [String: UUID] = [:]
    /// Tabs the person moved, and where: a later part of the stream
    /// doesn't move them back.
    @ObservationIgnored private var edited = false

    init(tabs: [TabInfo], mode: Mode = .tidy) {
        self.mode = mode
        info = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The engine's latest: every group so far.
    func receive(_ suggestion: TidySuggestion) {
        engine = suggestion.engine
        if !edited {
            sections = suggestion.groups.map { group in
                let key = group.name.lowercased()
                let id = keys[key] ?? UUID()
                keys[key] = id
                if suggested[id] == nil { suggested[id] = group.name }
                let name = sections.first { $0.id == id }?.name ?? group.name
                return Section(id: id, name: name, tabs: group.ids.filter { info[$0] != nil })
            }.filter { !$0.tabs.isEmpty }
        }
        thinking = !suggestion.done
    }

    /// "Add similar tabs": the tabs found, as one section named for the group.
    func receiveSimilar(_ ids: [UUID]) {
        guard case .similar(let group, let name) = mode else { return }
        suggested[group] = name
        let found = ids.filter { info[$0] != nil }
        sections = found.isEmpty ? [] : [Section(id: group, name: name, tabs: found)]
        thinking = false
    }

    // MARK: - edits

    func rename(_ section: UUID, to name: String) {
        guard let i = sections.firstIndex(where: { $0.id == section }) else { return }
        sections[i].name = name
        edited = true
    }

    func toggle(_ tab: UUID) {
        if unchecked.contains(tab) { unchecked.remove(tab) } else { unchecked.insert(tab) }
    }

    func isChecked(_ tab: UUID) -> Bool { !unchecked.contains(tab) }

    /// To the end of another group, checked.
    func move(_ tab: UUID, to section: UUID) {
        guard let to = sections.firstIndex(where: { $0.id == section }), !sections[to].tabs.contains(tab) else { return }
        sections = sections.map { var s = $0; s.tabs.removeAll { $0 == tab }; return s }
        sections[to].tabs.append(tab)
        unchecked.remove(tab)
        edited = true
    }

    // MARK: - the result

    /// What Apply makes: checked tabs only, a group only if it has one, and
    /// a name cleared by hand is the suggested one.
    var chosen: [TidyGroup] {
        sections.compactMap { section in
            let ids = section.tabs.filter { !unchecked.contains($0) }
            guard !ids.isEmpty else { return nil }
            let typed = section.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return TidyGroup(name: typed.isEmpty ? (suggested[section.id] ?? "Group") : typed, ids: ids)
        }
    }

    var chosenCount: Int { chosen.reduce(0) { $0 + $1.ids.count } }

    var canApply: Bool { !thinking && chosenCount > 0 }
}

/// Apply and Undo. Apply sets the new grouping at once and offers Undo in a
/// toast; Undo puts the grouping from before back as it was. The grouping
/// is Tabs' (docs/integration/tidy.md), reached through these closures.
@MainActor final class TidyFlow {
    private let grouping: () -> Session.Grouping
    private let regroup: (Session.Grouping) -> Void
    private let toast: (String, Toaster.Offer) -> Void

    init(grouping: @escaping () -> Session.Grouping,
         regroup: @escaping (Session.Grouping) -> Void,
         toast: @escaping (String, Toaster.Offer) -> Void) {
        self.grouping = grouping
        self.regroup = regroup
        self.toast = toast
    }

    func apply(_ draft: TidyDraft) {
        let chosen = draft.chosen
        let count = chosen.reduce(0) { $0 + $1.ids.count }
        guard count > 0 else { return }
        let before = grouping()
        let after: Session.Grouping
        let line: String
        switch draft.mode {
        case .tidy:
            after = before.applying(chosen)
            line = "Grouped \(count) \(count == 1 ? "tab" : "tabs")"
        case .similar(let group, let name):
            after = before.adding(chosen.flatMap(\.ids), to: group)
            line = "Added \(count) \(count == 1 ? "tab" : "tabs") to \(name)"
        }
        guard after != before else { return }
        regroup(after)
        toast(line, Toaster.Offer(title: "Undo") { [regroup] in regroup(before) })
    }
}
