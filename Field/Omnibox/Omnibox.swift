// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import Foundation
import FieldKit
import Observation

/// What the field is asking and what it thinks you mean. The field writes to
/// it, the rows read from it, and each reads only what it draws, so a
/// keystroke redraws the rows it changed and nothing else.
@Observable final class Omnibox {
    /// Best first: places and past searches, then the engine's suggestions.
    private(set) var offers: [Suggestion] = []
    /// Whether there are any, apart from which: the panel grows and shrinks on
    /// this alone, not on every change to the list.
    private(set) var listed = false
    /// The row Return goes to: the one the field is finishing, by its id.
    private(set) var picked: String?
    /// Red rim until the next edit.
    private(set) var refused = false
    /// Bumped on each refusal, to shake again.
    private(set) var refusals = 0
    /// Rows the last keystroke left behind, kept in their place until the
    /// answer for the new words comes: drawn faded, and out of reach, since
    /// none of them is an answer to what is typed now.
    private(set) var fading: Set<String> = []
    /// How tall the rows may stand, from the field up to the safe area's
    /// top, told by the field (its coordinator). The farthest go first.
    var room: CGFloat = .infinity

    /// The engine's suggestions changed with no keystroke: the rows need
    /// measuring again (the field's coordinator).
    @ObservationIgnored var onLate: () -> Void = {}
    /// A row's words go into the field, to carry on from there.
    @ObservationIgnored var onFill: (String) -> Void = { _ in }

    @ObservationIgnored private(set) var draft: Draft
    @ObservationIgnored private let initial: URL?
    @ObservationIgnored private let history: HistoryStore
    /// Where the search engine is chosen, and the suggestions switch.
    @ObservationIgnored private let defaults: UserDefaults
    /// Asked at each keystroke, so a field that outlives a move into or out
    /// of Private still knows where it is. Until told, it is Private: nothing
    /// is sent and nothing is remembered.
    @ObservationIgnored private let privately: () -> Bool
    @ObservationIgnored private let suggester: Suggester
    /// Untouched, the field still stands for the page it opened on, all of
    /// it, not the shortened address it shows.
    @ObservationIgnored private var touched = false
    /// The rows from the phone, and the engine's beyond them.
    @ObservationIgnored private var near: [Suggestion] = []
    @ObservationIgnored private var far: [Suggestion] = []
    /// Rows waiting to leave when the current answer is ready (`fading`).
    @ObservationIgnored private var outgoing: [Suggestion] = []
    /// How long they wait for it, before going anyway.
    @ObservationIgnored private let patience: Duration
    @ObservationIgnored private var waiting: Task<Void, Never>?
    /// Fingers on rows. Until the last lifts, nothing that arrives late
    /// changes the rows, so the one under a finger is the one it takes.
    @ObservationIgnored private var touching = 0
    /// What was typed when the engine's rows were last asked for.
    @ObservationIgnored private var asked = ""

    /// The page the field opened on, while it still stands for it.
    var page: URL? { touched ? nil : initial }

    init(
        initial: URL?, history: HistoryStore, defaults: UserDefaults = .standard,
        privately: @escaping () -> Bool = { true }, suggester: Suggester = Suggester(),
        patience: Duration = .seconds(1)
    ) {
        self.initial = initial
        self.history = history
        self.defaults = defaults
        self.privately = privately
        self.suggester = suggester
        self.patience = patience
        draft = Draft(text: initial.map(Address.pretty) ?? "")
    }

    /// UIKit has changed the text. Returns what the field should hold now.
    func edited(to text: String, selection: Range<Int>, marked: Bool, cause: Draft.Cause) -> Draft {
        touched = true
        // Asked of what was typed, before anything is finished for it.
        let list = Offers.merge(
            places: history.suggestions(for: text),
            searches: history.searchSuggestions(for: text, template: template),
            typed: text
        )
        draft.edited(to: text, selection: selection, marked: marked, cause: cause) {
            Offers.completion(for: $0, among: list)
        }
        let request = Suggest.request(
            for: text, engine: engine, privately: privately(), enabled: suggesting, near: list
        )
        // What was showing waits for the answer, in no more room than it
        // had, so the panel neither shrinks nor grows until the answer
        // lands. An engine answer belongs to one query: its rows wait
        // faded, and can't be taken for the new words.
        let current = Set(list.map(\.id))
        let shown = offers.count
        outgoing = request == nil ? [] : (near + outgoing + far).filter { !current.contains($0.id) }
        outgoing = Array(outgoing.prefix(max(0, shown - list.count)))
        near = list
        far = []
        asked = text
        // A keystroke is never held: the field changed under the finger too.
        touching = 0
        publish()
        wait(for: text)
        if picked != draft.match?.id { picked = draft.match?.id }
        if refused { refused = false }
        suggester.ask(request, allowed: { [weak self] in
            guard let self else { return false }
            return Suggest.request(for: text, engine: self.engine, privately: self.privately(),
                                   enabled: self.suggesting, near: list) == request
        }) { [weak self] words in self?.answered(words, for: text) }
        return draft
    }

    func selected(_ selection: Range<Int>) {
        draft.selected(selection)
    }

    /// Return. The page it opened on while untouched, then the place the field
    /// finished, then what the words mean. Nil when they mean nothing, and
    /// the field says so.
    func submit() -> URL? {
        suggester.stop()
        let target = touched ? draft.match?.url : initial
        guard let url = target ?? Destination.url(for: draft.text, engine: engine, custom: custom) else {
            refused = true
            refusals += 1
            return nil
        }
        if touched {
            if let match = draft.match {
                remember(match)
            } else if Address.url(from: draft.text) == nil {
                remember(draft.text)
            }
        }
        return url
    }

    /// A row tapped: the field goes there next.
    func chose(_ offer: Suggestion) {
        suggester.stop()
        remember(offer)
    }

    /// A search's words into the field, without going.
    func fill(_ offer: Suggestion) {
        onFill(offer.key)
    }

    /// The field closed: nothing more is to be sent.
    func ended() {
        suggester.stop()
        waiting?.cancel()
    }

    /// A finger came down on a row, or lifted, or slid off. What arrived
    /// while it was down is shown when the last one lifts.
    func pressed(_ down: Bool) {
        touching = max(0, touching + (down ? 1 : -1))
        guard touching == 0, publish() else { return }
        onLate()
    }

    // MARK: -

    private var engine: Engine {
        defaults.string(forKey: "engine").flatMap(Engine.init(rawValue:)) ?? .standard
    }

    private var custom: String {
        defaults.string(forKey: "engine.custom") ?? ""
    }

    private var template: String { engine.template(custom: custom) }

    /// The Settings switch, or its default until it has been moved.
    private var suggesting: Bool {
        defaults.object(forKey: Suggest.defaultsKey) == nil
            ? Suggest.enabledByDefault : defaults.bool(forKey: Suggest.defaultsKey)
    }

    /// The engine's answer for exactly what is typed, or nothing: a late
    /// answer for other words was dropped on the way (Suggester), and this
    /// checks again.
    private func answered(_ words: [String], for text: String) {
        guard text == asked else { return }
        waiting?.cancel()
        outgoing = []
        far = Offers.remote(words, typed: text, near: near, template: template)
        late()
    }

    /// The rows left behind go, if the answer for `text` hasn't come in time.
    private func wait(for text: String) {
        waiting?.cancel()
        guard !outgoing.isEmpty else { return }
        waiting = Task { [weak self, patience] in
            try? await Task.sleep(for: patience)
            guard !Task.isCancelled, let self, text == self.asked else { return }
            self.outgoing = []
            self.late()
        }
    }

    /// A change no keystroke made, shown unless a finger is on a row.
    private func late() {
        guard touching == 0, publish() else { return }
        onLate()
    }

    /// Written only when they change: each write redraws whoever reads it.
    @discardableResult
    private func publish() -> Bool {
        let all = near + outgoing + far
        let gone = Set(outgoing.map(\.id))
        if fading != gone { fading = gone }
        guard offers != all else { return false }
        offers = all
        if listed == all.isEmpty { listed = !all.isEmpty }
        return true
    }

    private func remember(_ offer: Suggestion) {
        guard offer.kind == .search || offer.kind == .searched else { return }
        remember(offer.key)
    }

    private func remember(_ words: String) {
        guard !privately() else { return }
        history.searched(words)
    }
}
