import FieldKit
import Foundation
import NaturalLanguage

/// Which of the two made a suggestion, for the sheet's honest label.
nonisolated enum TidyEngineKind: Sendable, Equatable {
    /// Apple's on-device language model.
    case model
    /// FieldKit's rules: same site, then sentence vectors (Tidy.suggest).
    case rules
}

nonisolated struct TidySuggestion: Sendable, Equatable {
    var groups: [TidyGroup]
    var engine: TidyEngineKind
    /// False while more is on its way.
    var done: Bool
}

/// Tidy's engine (M6): suggests groups for open tabs, on the phone and
/// nowhere else. Apple's on-device model when this phone has it, it's on,
/// and it does the phone's language; FieldKit's rules otherwise. The model
/// reads the tabs in batches its context has room for, each batch in a
/// fresh session. A batch the model refuses (a guardrail tripped by one
/// title, usually) is halved and asked again until the tab is alone, and
/// that tab goes to the rules. Its own actor, so none of it runs on the main
/// thread; cancelling the task that reads `stream` stops it.
///
/// Private tabs are never passed in (docs/integration/tidy.md); only web
/// pages are sent at all, so a blank tab or a data: page never is.
actor TidyEngine {
    static let shared = TidyEngine()

    private let model: @Sendable () -> (any TidyLanguageModel)?
    private let injectedEmbed: (@Sendable (String) -> [Double]?)?
    private let site: @Sendable (String) -> String
    /// Loaded on first use, one per language.
    private var vectors: [NLLanguage: TidyVectors] = [:]

    /// The model is asked for each time, since it can finish downloading, or
    /// be switched on, while the app runs. The tests pass a script, and a
    /// deterministic embedding in place of NaturalLanguage's (TidyVectors).
    init(model: @escaping @Sendable () -> (any TidyLanguageModel)? = TidyEngine.systemModel,
         embed: (@Sendable (String) -> [Double]?)? = nil,
         site: @escaping @Sendable (String) -> String = { GuardRules.bundled.site(of: $0) }) {
        self.model = model
        injectedEmbed = embed
        self.site = site
    }

    static let systemModel: @Sendable () -> (any TidyLanguageModel)? = {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-FieldTidyRules") { return nil }
        #endif
        return SystemTidyModel.ifAvailable()
    }

    static let instructions = """
        You sort a person's open browser tabs into groups by topic or task. \
        Each line is one tab: its number, its site, and its title. \
        Make groups of two or more tabs that belong together, like a trip being planned, \
        something being shopped for, or a subject being read about. \
        Name each group in 1 to 3 plain words, specific rather than general: \
        "Lisbon trip" rather than "Travel". No emoji. \
        Put each tab number in one group at most, and leave out tabs that fit no group.
        """

    static let similarInstructions = """
        You help a person add open browser tabs to one of their tab groups. \
        You're given the group's name and its tabs, then numbered tabs that aren't in it, \
        each with its site and title. Give the numbers of the tabs that belong in the group. \
        Give none if none belong.
        """

    // MARK: - suggesting groups

    /// The groups as they come: each suggestion has every group so far, and
    /// the last has `done` set.
    nonisolated func stream(_ tabs: [TabInfo]) -> AsyncStream<TidySuggestion> {
        let (stream, continuation) = AsyncStream<TidySuggestion>.makeStream()
        let task = Task {
            await self.run(tabs) { continuation.yield($0) }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    /// Only the finished answer.
    func suggest(_ tabs: [TabInfo]) async -> TidySuggestion {
        var last = TidySuggestion(groups: [], engine: .rules, done: true)
        for await suggestion in stream(tabs) { last = suggestion }
        return last
    }

    /// Loads the model, the sentence model and the site rules while the
    /// grid opens, so the tap on Tidy waits for none of them.
    nonisolated func prewarm() {
        Task(priority: .utility) { await self.warm() }
    }

    private func warm() {
        model()?.prewarm(instructions: Self.instructions)
        _ = site("example.com")
        if injectedEmbed == nil { _ = vectors(.english) }
    }

    private func run(_ given: [TabInfo], yield: (TidySuggestion) -> Void) async {
        let tabs = Self.web(given)
        guard tabs.count >= 2 else {
            return yield(TidySuggestion(groups: [], engine: .rules, done: true))
        }
        guard let model = model() else {
            return yield(TidySuggestion(groups: rules(tabs), engine: .rules, done: true))
        }
        let budget = await model.budget(instructions: Self.instructions)
        guard let batches = try? await Tidy.batches(tabs, budget: budget, count: { try await model.tokenCount($0) }) else {
            return yield(TidySuggestion(groups: rules(tabs), engine: .rules, done: true))
        }
        var groups: [TidyGroup] = []
        var refused: [TabInfo] = []
        for batch in batches {
            guard !Task.isCancelled else { return }
            await ask(model, batch, groups: &groups, refused: &refused, yield: yield)
        }
        guard !Task.isCancelled else { return }
        if !refused.isEmpty { groups = Tidy.merge(groups, rules(refused)) }
        // Every tab left for the rules is the rules' answer, whatever the
        // model said about being there.
        let answered = refused.count < tabs.count
        yield(TidySuggestion(groups: Self.shown(groups), engine: answered ? .model : .rules, done: true))
    }

    /// Groups of one are kept while batches are read, since a group's other
    /// tabs may come in a later batch, but a group needs two to be shown.
    private static func shown(_ groups: [TidyGroup]) -> [TidyGroup] {
        groups.filter { $0.ids.count >= 2 }
    }

    /// One batch. Refused or too long, it's halved and each half asked on
    /// its own; a tab refused alone, or a batch that failed some other way,
    /// is left for the rules.
    private func ask(_ model: any TidyLanguageModel, _ batch: [TabInfo], groups: inout [TidyGroup],
                     refused: inout [TabInfo], yield: (TidySuggestion) -> Void) async {
        let before = groups
        let names = before.map(\.name)
        do {
            for try await proposals in model.propose(Self.prompt(batch, names: names), instructions: Self.instructions) {
                groups = Tidy.merge(before, Tidy.validate(proposals, batch: batch, minimum: 1), minimum: 1)
                yield(TidySuggestion(groups: Self.shown(groups), engine: .model, done: false))
            }
        } catch {
            groups = before
            guard !Task.isCancelled else { return }
            let error = error as? TidyModelError ?? .failed
            guard error != .failed, batch.count > 1 else {
                refused += batch
                return
            }
            let mid = batch.count / 2
            await ask(model, Array(batch[..<mid]), groups: &groups, refused: &refused, yield: yield)
            await ask(model, Array(batch[mid...]), groups: &groups, refused: &refused, yield: yield)
        }
    }

    static func prompt(_ batch: [TabInfo], names: [String]) -> String {
        let reuse = names.isEmpty ? "" : "Groups so far; reuse a name when a tab fits: \(names.joined(separator: ", "))\n\n"
        return reuse + "Tabs:\n" + Tidy.render(batch)
    }

    // MARK: - add similar tabs

    /// Which of `candidates` belong in the group called `name`, which has
    /// `members` now. The Firefox pattern: easier than grouping from nothing.
    func similar(named name: String, members given: [TabInfo], among candidates: [TabInfo]) async -> [UUID] {
        let members = Self.web(given)
        let memberIDs = Set(members.map(\.id))
        let loose = Self.web(candidates).filter { !memberIDs.contains($0.id) }
        guard !members.isEmpty, !loose.isEmpty else { return [] }
        guard let model = model() else { return rulesSimilar(members, loose) }

        let budget = await model.budget(instructions: Self.similarInstructions) - Tidy.render(members).utf8.count / 3
        guard let batches = try? await Tidy.batches(loose, budget: max(200, budget), count: { try await model.tokenCount($0) }) else {
            return rulesSimilar(members, loose)
        }
        var found: [UUID] = []
        for batch in batches {
            guard !Task.isCancelled else { return [] }
            found += await pick(model, name: name, members: members, batch)
        }
        let chosen = Set(found)
        return loose.map(\.id).filter { chosen.contains($0) }
    }

    private func pick(_ model: any TidyLanguageModel, name: String, members: [TabInfo], _ batch: [TabInfo]) async -> [UUID] {
        let group = members.prefix(12).map { "- \(Tidy.host(of: $0.url) ?? "") | \($0.title.prefix(70))" }.joined(separator: "\n")
        let prompt = "Group: \(name)\nIn it now:\n\(group)\n\nTabs:\n\(Tidy.render(batch))"
        do {
            let numbers = try await model.pick(prompt, instructions: Self.similarInstructions)
            var seen = Set<Int>()
            return numbers.filter { $0 >= 1 && $0 <= batch.count && seen.insert($0).inserted }.map { batch[$0 - 1].id }
        } catch {
            guard !Task.isCancelled else { return [] }
            let error = error as? TidyModelError ?? .failed
            guard error != .failed, batch.count > 1 else { return rulesSimilar(members, batch) }
            let mid = batch.count / 2
            return await pick(model, name: name, members: members, Array(batch[..<mid]))
                + pick(model, name: name, members: members, Array(batch[mid...]))
        }
    }

    // MARK: - the rules

    private func rules(_ tabs: [TabInfo]) -> [TidyGroup] {
        let embed = embedder(for: tabs)
        return Tidy.suggest(tabs, embed: embed, site: site)
    }

    private func rulesSimilar(_ members: [TabInfo], _ candidates: [TabInfo]) -> [UUID] {
        let embed = embedder(for: members + candidates)
        return Tidy.similar(to: members, among: candidates, embed: embed, site: site)
    }

    /// Vectors in the tabs' main language, one model for all of them so
    /// they can be compared. English when there's no telling.
    private func embedder(for tabs: [TabInfo]) -> (String) -> [Double]? {
        if let injectedEmbed { return injectedEmbed }
        // Titles run together read as anything (Indonesian, once), so only
        // the languages with vectors are considered, and only a clear lead
        // beats English.
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .spanish, .french, .german, .italian, .portuguese, .simplifiedChinese]
        recognizer.processString(tabs.map(\.title).joined(separator: ". "))
        let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first ?? (.english, 0)
        let found = vectors(confidence > 0.6 ? language : .english)
        return (found.usable ? found : vectors(.english)).vector
    }

    private func vectors(_ language: NLLanguage) -> TidyVectors {
        if let known = vectors[language] { return known }
        let made = TidyVectors(language: language)
        vectors[language] = made
        return made
    }

    /// Web pages only, each once.
    static func web(_ tabs: [TabInfo]) -> [TabInfo] {
        var seen = Set<UUID>()
        return tabs.filter { tab in
            guard let scheme = tab.url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
            return seen.insert(tab.id).inserted
        }
    }
}
