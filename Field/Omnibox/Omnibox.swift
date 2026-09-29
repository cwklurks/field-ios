// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation
import FieldKit
import Observation

/// What the field is asking and what it thinks you mean. The field writes to
/// it, the rows read from it, and each reads only what it draws, so a
/// keystroke redraws the rows it changed and nothing else.
@Observable final class Omnibox {
    /// Best first.
    private(set) var offers: [Suggestion] = []
    /// Whether there are any, apart from which: the panel grows and shrinks on
    /// this alone, not on every change to the list.
    private(set) var listed = false
    /// The row Return goes to: the one the field is finishing.
    private(set) var picked: String?
    /// Red rim until the next edit.
    private(set) var refused = false
    /// Bumped on each refusal, to shake again.
    private(set) var refusals = 0

    @ObservationIgnored private(set) var draft: Draft
    @ObservationIgnored private let initial: URL?
    @ObservationIgnored private let history: HistoryStore
    /// Where the search engine is chosen.
    @ObservationIgnored private let defaults: UserDefaults
    /// Untouched, the field still stands for the page it opened on, all of
    /// it, not the shortened address it shows.
    @ObservationIgnored private var touched = false

    init(initial: URL?, history: HistoryStore, defaults: UserDefaults = .standard) {
        self.initial = initial
        self.history = history
        self.defaults = defaults
        draft = Draft(text: initial.map(Address.pretty) ?? "")
    }

    /// UIKit has changed the text. Returns what the field should hold now.
    func edited(to text: String, selection: Range<Int>, marked: Bool, cause: Draft.Cause) -> Draft {
        touched = true
        // Asked of what was typed, before anything is finished for it.
        let list = history.suggestions(for: text)
        draft.edited(to: text, selection: selection, marked: marked, cause: cause) {
            history.completion(for: $0, among: list)
        }
        // Written only when they change: each write redraws whoever reads it.
        if offers != list { offers = list }
        if listed == list.isEmpty { listed = !list.isEmpty }
        if picked != draft.match?.key { picked = draft.match?.key }
        if refused { refused = false }
        return draft
    }

    func selected(_ selection: Range<Int>) {
        draft.selected(selection)
    }

    /// Return. The page it opened on while untouched, then the place the field
    /// finished, then what the words mean. Nil when they mean nothing, and
    /// the field says so.
    func submit() -> URL? {
        let engine = defaults.string(forKey: "engine").flatMap(Engine.init(rawValue:)) ?? .standard
        let custom = defaults.string(forKey: "engine.custom") ?? ""
        let target = touched ? draft.match?.url : initial
        guard let url = target ?? Destination.url(for: draft.text, engine: engine, custom: custom) else {
            refused = true
            refusals += 1
            return nil
        }
        return url
    }
}
