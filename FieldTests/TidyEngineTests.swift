import Foundation
import Testing
@testable import FieldKit
@testable import Field

/// Tidy's engine against a scripted model: groups come back as tab ids,
/// a refused batch is halved until the tab that tripped the guardrail is
/// alone, that tab goes to the rules, and without a model the rules do it
/// all. Nothing here loads Apple's model or NaturalLanguage.
nonisolated struct TidyEngineTests {
    static func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    static func tab(_ n: Int, _ title: String, _ url: String) -> TabInfo {
        TabInfo(id: id(n), title: title, url: URL(string: url)!)
    }

    /// Two topics, and a site per tab so the rules' same-site pass has
    /// nothing to do unless a test says so.
    static let tabs = [
        tab(1, "Flights to Lisbon", "https://flights.example/lis"),
        tab(2, "Hotels in Alfama", "https://hotels.example/alfama"),
        tab(3, "Sourdough starter", "https://bake.example/starter"),
        tab(4, "No-knead bread", "https://bread.example/noknead"),
        tab(5, "Lisbon tram 28", "https://tram.example/28"),
        tab(6, "Rye bread recipe", "https://rye.example/r"),
    ]

    /// One vector per topic word; anything else on its own axis.
    static let embed: @Sendable (String) -> [Double]? = { text in
        let title = text.lowercased()
        if title.contains("lisbon") || title.contains("alfama") { return [1, 0, 0] }
        if title.contains("bread") || title.contains("sourdough") { return [0, 1, 0] }
        return [0, 0, 1]
    }

    static let site: @Sendable (String) -> String = { $0 }

    func engine(_ model: FakeModel?) -> TidyEngine {
        TidyEngine(model: { model }, embed: Self.embed, site: Self.site)
    }

    /// Groups by the words in each numbered line's title, as a model might.
    static func byTopic(_ prompt: String) -> [Tidy.Proposal] {
        var trip: [Int] = [], baking: [Int] = []
        for (number, title) in FakeModel.lines(prompt) {
            let t = title.lowercased()
            if t.contains("lisbon") || t.contains("alfama") { trip.append(number) }
            if t.contains("bread") || t.contains("sourdough") { baking.append(number) }
        }
        return [.init(name: "Lisbon trip", ids: trip), .init(name: "Baking", ids: baking)]
    }

    // MARK: - the model's groups

    @Test func theModelsGroupsComeBackAsTabs() async {
        let model = FakeModel { Self.byTopic($0) }
        let found = await engine(model).suggest(Self.tabs)
        #expect(found.engine == .model)
        #expect(found.done)
        #expect(found.groups == [
            TidyGroup(name: "Lisbon trip", ids: [Self.id(1), Self.id(2), Self.id(5)]),
            TidyGroup(name: "Baking", ids: [Self.id(3), Self.id(4), Self.id(6)]),
        ])
    }

    /// Numbers that name no tab, and a tab named twice, are dropped.
    @Test func inventedAndRepeatedNumbersAreDropped() async {
        let model = FakeModel { _ in [.init(name: "Trip", ids: [1, 2, 99, 2]), .init(name: "Bake", ids: [2, 3, 4, 0])] }
        let found = await engine(model).suggest(Self.tabs)
        #expect(found.groups == [
            TidyGroup(name: "Trip", ids: [Self.id(1), Self.id(2)]),
            TidyGroup(name: "Bake", ids: [Self.id(3), Self.id(4)]),
        ])
    }

    /// Only web pages are sent: a blank tab, a data: page and the like
    /// aren't anybody's topic, and never leave the list.
    @Test func onlyWebPagesAreSent() async {
        let model = FakeModel { Self.byTopic($0) }
        let odd = [
            Self.tab(7, "Secret notes", "data:text/html,hello"),
            Self.tab(8, "Local file", "file:///private/var/x.html"),
            Self.tab(9, "Blank", "about:blank"),
        ]
        _ = await engine(model).suggest(Self.tabs + odd)
        let sent = model.prompts.joined(separator: "\n")
        #expect(!sent.contains("Secret notes"))
        #expect(!sent.contains("Local file"))
        #expect(!sent.contains("Blank"))
    }

    // MARK: - refusals

    /// A title that trips the guardrail sinks the batch it's in. The batch
    /// is halved and asked again until that tab is alone; it then goes to
    /// the rules, and everything else keeps the model's groups.
    @Test func aRefusedBatchIsSplitAndTheTabFallsBack() async {
        let model = FakeModel { prompt in
            if prompt.contains("tram 28") { throw TidyModelError.refused }
            return Self.byTopic(prompt)
        }
        let found = await engine(model).suggest(Self.tabs)
        #expect(found.engine == .model)
        let placed = found.groups.flatMap(\.ids)
        #expect(!placed.contains(Self.id(5)))
        #expect(Set(placed) == Set([1, 2, 3, 4, 6].map(Self.id)))
        // 6, refused → 3 + 3; the three with the tram → 1 + 2; → 1 + 1.
        #expect(model.prompts.count == 7)
    }

    /// Refused tabs are grouped among themselves by the rules: two pages on
    /// one site still land together.
    @Test func refusedTabsAreGroupedByTheRules() async {
        let tabs = Self.tabs + [
            Self.tab(7, "Blocked one", "https://news.example/a"),
            Self.tab(8, "Blocked two", "https://news.example/b"),
        ]
        let model = FakeModel { prompt in
            if prompt.contains("Blocked") { throw TidyModelError.refused }
            return Self.byTopic(prompt)
        }
        let found = await engine(model).suggest(tabs)
        let rules = found.groups.first { $0.ids.contains(Self.id(7)) }
        #expect(rules?.ids == [Self.id(7), Self.id(8)])
    }

    /// Too long for the context: halved and asked again, like a refusal.
    @Test func tooLongIsSplit() async {
        let model = FakeModel { prompt in
            if FakeModel.lines(prompt).count > 3 { throw TidyModelError.tooLong }
            return Self.byTopic(prompt)
        }
        let found = await engine(model).suggest(Self.tabs)
        #expect(model.prompts.map { FakeModel.lines($0).count } == [6, 3, 3])
        #expect(found.groups.map(\.name) == ["Lisbon trip", "Baking"])
        #expect(found.engine == .model)
    }

    /// Any other failure: the rules take that batch whole, without asking
    /// again.
    @Test func otherFailuresGoToTheRules() async {
        let model = FakeModel { _ in throw TidyModelError.failed }
        let found = await engine(model).suggest(Self.tabs)
        #expect(model.prompts.count == 1)
        // The model answered nothing, so the label mustn't say it did. The
        // simulator does this: "available", then every request fails.
        #expect(found.engine == .rules)
        #expect(found.groups == Tidy.suggest(Self.tabs, embed: Self.embed, site: Self.site))
    }

    /// No counter to be had: the whole list goes to the rules.
    @Test func aFailingCounterGoesToTheRules() async {
        let model = FakeModel(countFails: true) { Self.byTopic($0) }
        let found = await engine(model).suggest(Self.tabs)
        #expect(found.engine == .rules)
        #expect(model.prompts.isEmpty)
    }

    // MARK: - no model

    @Test func withoutAModelTheRulesDoIt() async {
        let found = await engine(nil).suggest(Self.tabs)
        #expect(found.engine == .rules)
        #expect(found.groups == Tidy.suggest(Self.tabs, embed: Self.embed, site: Self.site))
        #expect(!found.groups.isEmpty)
    }

    @Test func fewerThanTwoTabsIsNothingToDo() async {
        let model = FakeModel { Self.byTopic($0) }
        let found = await engine(model).suggest([Self.tabs[0]])
        #expect(found.groups.isEmpty)
        #expect(model.prompts.isEmpty)
    }

    // MARK: - batches

    /// A small context reads the tabs in batches; later batches are told the
    /// names so far, and a name used again joins that group.
    @Test func batchesShareNames() async {
        let model = FakeModel(budget: 130) { Self.byTopic($0) }
        let found = await engine(model).suggest(Self.tabs)
        #expect(model.prompts.map { FakeModel.lines($0).count } == [3, 3])
        #expect(model.prompts[1].contains("Lisbon trip"))
        // Tram 28, alone on the second batch's Lisbon side, joins the first's.
        #expect(found.groups.first { $0.name == "Lisbon trip" }?.ids == [Self.id(1), Self.id(2), Self.id(5)])
        #expect(found.groups.map(\.name) == ["Lisbon trip", "Baking"])
    }

    // MARK: - streaming

    /// Each group as the model finishes it, then the whole answer.
    @Test func groupsStreamInAsTheyArrive() async {
        let model = FakeModel(stepwise: true) { Self.byTopic($0) }
        var seen: [TidySuggestion] = []
        for await suggestion in engine(model).stream(Self.tabs) { seen.append(suggestion) }
        #expect(seen.count >= 2)
        #expect(seen.first?.done == false)
        #expect(seen.first?.groups.map(\.name) == ["Lisbon trip"])
        #expect(seen.last?.done == true)
        #expect(seen.last?.groups.count == 2)
    }

    /// Cancelled (the sheet went), it stops asking.
    @Test func cancellingStops() async {
        let model = FakeModel(budget: 60, delay: .milliseconds(200)) { Self.byTopic($0) }
        let engine = engine(model)
        let task = Task { for await _ in engine.stream(Self.tabs) {} }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        await task.value
        try? await Task.sleep(for: .milliseconds(300))
        #expect(model.prompts.count == 1)
    }

    // MARK: - add similar tabs

    @Test func similarAsksTheModel() async {
        let model = FakeModel(pick: { prompt in
            FakeModel.lines(prompt).filter { $0.1.contains("Lisbon") }.map(\.0) + [42]
        }) { _ in [] }
        let members = [Self.tabs[0], Self.tabs[1]]
        let loose = [Self.tabs[2], Self.tabs[4], Self.tabs[5]]
        let found = await engine(model).similar(named: "Lisbon trip", members: members, among: loose)
        #expect(found == [Self.id(5)])
    }

    @Test func similarWithoutAModelUsesTheRule() async {
        let members = [Self.tabs[0], Self.tabs[1]]
        let loose = [Self.tabs[2], Self.tabs[4], Self.tabs[5]]
        let found = await engine(nil).similar(named: "Lisbon trip", members: members, among: loose)
        #expect(found == [Self.id(5)])
    }

    @Test func similarRefusedFallsBackToTheRule() async {
        let model = FakeModel(pick: { _ in throw TidyModelError.refused }) { _ in [] }
        let members = [Self.tabs[0], Self.tabs[1]]
        let loose = [Self.tabs[2], Self.tabs[4]]
        let found = await engine(model).similar(named: "Lisbon trip", members: members, among: loose)
        #expect(found == [Self.id(5)])
    }
}

/// A language model that answers from a script, and remembers each prompt.
nonisolated final class FakeModel: TidyLanguageModel, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [String] = []
    private let budgetTokens: Int
    private let stepwise: Bool
    private let delay: Duration
    private let countFails: Bool
    private let answer: @Sendable (String) throws -> [Tidy.Proposal]
    private let pickAnswer: @Sendable (String) throws -> [Int]

    init(budget: Int = 10_000, stepwise: Bool = false, delay: Duration = .zero, countFails: Bool = false,
         pick: @escaping @Sendable (String) throws -> [Int] = { _ in [] },
         answer: @escaping @Sendable (String) throws -> [Tidy.Proposal]) {
        budgetTokens = budget
        self.stepwise = stepwise
        self.delay = delay
        self.countFails = countFails
        self.answer = answer
        pickAnswer = pick
    }

    var prompts: [String] { lock.withLock { asked } }

    /// The numbered tab lines of a prompt, as (number, title).
    static func lines(_ prompt: String) -> [(Int, String)] {
        prompt.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: " | ")
            guard parts.count == 3, let n = Int(parts[0]) else { return nil }
            return (n, parts[2])
        }
    }

    func budget(instructions: String) async -> Int { budgetTokens }

    /// A token a character: easy to reason about.
    func tokenCount(_ text: String) async throws -> Int {
        if countFails { throw TidyModelError.failed }
        return text.count
    }

    func propose(_ prompt: String, instructions: String) -> AsyncThrowingStream<[Tidy.Proposal], any Error> {
        lock.withLock { asked.append(prompt) }
        let (stream, continuation) = AsyncThrowingStream<[Tidy.Proposal], any Error>.makeStream()
        let task = Task { [answer, stepwise, delay] in
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                let groups = try answer(prompt)
                if stepwise {
                    for n in 1..<max(1, groups.count) { continuation.yield(Array(groups.prefix(n))) }
                }
                continuation.yield(groups)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func pick(_ prompt: String, instructions: String) async throws -> [Int] {
        lock.withLock { asked.append(prompt) }
        return try pickAnswer(prompt)
    }

    func prewarm(instructions: String) {}
}
