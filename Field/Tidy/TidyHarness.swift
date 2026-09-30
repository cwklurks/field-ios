#if DEBUG
import FieldKit
import FoundationModels
import SwiftUI
import UIKit

/// `-FieldTidyHarness YES`: Tidy's whole flow over a stand-in for the grid,
/// on 21 made-up but realistic tabs, for the video and for a real run of
/// the on-device model. It reports whether the model is there, times the
/// first group and the last, prints the groups, then plays the sheet: a
/// rename, an uncheck, a move, Apply, and Undo from the toast.
///
/// `-FieldTidyEngine model|rules|script` picks the engine: the phone's own
/// (the model when it's there, the rules when not; the default), the rules
/// alone, or a script that streams fixed groups slowly, for filming the
/// streaming without a model. Everything lands in Documents/TidyHarness and
/// is printed as `[FieldTidyHarness] …`. Started by TidyHarnessLoader.m.
@objc(FieldTidyHarness) final class TidyHarness: NSObject {
    @objc static func start() {
        Task { await run() }
    }

    private static let out = URL.documentsDirectory.appendingPathComponent("TidyHarness", isDirectory: true)
    private static var report: [String] = []

    private static func run() async {
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        describeModel()
        await probeModel()

        let board = Board(entries: tabs)
        let toaster = Toaster()
        guard let window = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              let root = window.rootViewController else { return say("no window") }
        let screen = UIHostingController(rootView: BoardView(board: board, toaster: toaster)
            .tint(Palette.ink).dynamicTypeSize(...Ramp.cap))
        screen.modalPresentationStyle = .fullScreen
        screen.view.backgroundColor = Palette.UI.ground
        root.present(screen, animated: false)

        let engine = chosenEngine()
        engine.prewarm()
        TidySheets.prepareSoon(unless: { false })
        try? await Task.sleep(for: .seconds(3))

        // Off screen first: the real model's run, timed, before any video.
        let infos = board.entries.map { TabInfo(id: $0.id, title: $0.title, url: URL(string: $0.url)!) }
        let clock = ContinuousClock()
        let started = clock.now
        var first: Duration?
        var last = TidySuggestion(groups: [], engine: .rules, done: true)
        for await suggestion in engine.stream(infos) {
            if first == nil, !suggestion.groups.isEmpty { first = clock.now - started }
            last = suggestion
        }
        let total = clock.now - started
        say("engine \(last.engine), \(infos.count) tabs: first group after \(ms(first)), done after \(ms(total))")
        describe(last.groups, board: board)
        let similar = last.groups.first.map { group in
            (group, infos.filter { group.ids.contains($0.id) }, infos.filter { tab in !last.groups.contains { $0.ids.contains(tab.id) } })
        }
        if let (group, members, loose) = similar {
            let found = await engine.similar(named: group.name, members: Array(members.prefix(2)), among: loose + members.dropFirst(2))
            say("similar to \(group.name) (from its first two): \(found.compactMap { id in infos.first { $0.id == id }?.title }.joined(separator: " / "))")
        }
        save()

        // Now the sheet, for the video.
        let flow = TidyFlow(grouping: { board.grouping },
                            regroup: { grouping in withAnimation(Motion.calm(Motion.glide)) { board.grouping = grouping } },
                            toast: { toaster.show($0, offering: $1) })
        board.pressed = true
        let watch = FrameWatch()
        TidySheets.show(infos, flow: flow, engine: engine)
        board.pressed = false
        if let host = TidySheets.shownHost { watch.start(host) { say("sheet moved on frame \($0) after the tap") } }

        guard let draft = TidySheets.shownDraft else { return say("no sheet") }
        for _ in 0..<1200 where draft.thinking { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .seconds(1.2))

        if let one = draft.sections.first {
            let name = one.name
            for n in stride(from: name.count, through: 0, by: -1) {
                draft.rename(one.id, to: String(name.prefix(n)))
                try? await Task.sleep(for: .milliseconds(40))
            }
            let typed = "Lisbon weekend"
            for n in 1...typed.count {
                draft.rename(one.id, to: String(typed.prefix(n)))
                try? await Task.sleep(for: .milliseconds(70))
            }
            try? await Task.sleep(for: .seconds(0.6))
        }
        if let section = draft.sections.dropFirst().first, let tab = section.tabs.last {
            withAnimation(Motion.calm(Motion.quick)) { draft.toggle(tab) }
            try? await Task.sleep(for: .seconds(0.8))
        }
        if draft.sections.count >= 2, let tab = draft.sections[1].tabs.first {
            withAnimation(Motion.calm(Motion.settle)) { draft.move(tab, to: draft.sections[0].id) }
            try? await Task.sleep(for: .seconds(1))
        }
        say("applying \(draft.chosen.map { "\($0.name) (\($0.ids.count))" }.joined(separator: ", "))")
        TidySheets.shownApply?()
        try? await Task.sleep(for: .seconds(2.5))
        say("toast: \(toaster.text ?? "none")")
        toaster.take()
        try? await Task.sleep(for: .seconds(1.5))
        say("after undo: \(board.grouping.groups.count) groups")
        save()
        say("done")
    }

    // MARK: - engines

    private static func chosenEngine() -> TidyEngine {
        switch UserDefaults.standard.string(forKey: "FieldTidyEngine") {
        case "rules": TidyEngine(model: { nil })
        case "script": TidyEngine(model: { ScriptedModel() })
        default: TidyEngine()
        }
    }

    private static func describeModel() {
        let model = SystemLanguageModel.default
        say("device \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion), locale \(Locale.current.identifier)")
        say("SystemLanguageModel availability: \(model.availability)")
        say("supportsLocale: \(model.supportsLocale()), contextSize: \(model.contextSize)")
    }

    /// Straight at the model, to tell its failures apart from the engine's.
    private static func probeModel() async {
        let model = SystemLanguageModel.default
        if #available(iOS 26.4, *) {
            do { say("tokenCount(\"hello world\") = \(try await model.tokenCount(for: Prompt("hello world")))") }
            catch { say("tokenCount threw: \(error)") }
        }
        let session = LanguageModelSession(model: model, instructions: "Answer in one word.")
        do {
            let answer = try await session.respond(to: "What colour is the sky on a clear day?")
            say("respond: \(answer.content)")
        } catch {
            say("respond threw: \(error)")
        }
    }

    private static func describe(_ groups: [TidyGroup], board: Board) {
        for group in groups {
            say("  \(group.name)")
            for id in group.ids {
                say("    - \(board.entries.first { $0.id == id }?.title ?? "?")")
            }
        }
        let placed = Set(groups.flatMap(\.ids))
        let loose = board.entries.filter { !placed.contains($0.id) }.map(\.title)
        say("  (loose: \(loose.count)) \(loose.joined(separator: " / "))")
    }

    private static func ms(_ duration: Duration?) -> String {
        guard let duration else { return "never" }
        let (s, attos) = duration.components
        return "\(s * 1000 + attos / 1_000_000_000_000_000) ms"
    }

    private static func say(_ line: String) {
        report.append(line)
        print("[FieldTidyHarness] \(line)")
    }

    private static func save() {
        try? report.joined(separator: "\n").write(to: out.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: - the tabs

    /// 21 tabs as a person might have them: a trip, a laptop being chosen,
    /// bread, Swift work, and the odds and ends. Three untouched for weeks,
    /// one open twice, one TV recap a guardrail might trip over.
    static let tabs: [Session.Entry] = {
        let now = Date.now
        let list: [(String, String, Double)] = [
            ("Lisbon (LIS) flights from London | Google Flights", "https://www.google.com/travel/flights/search?q=LHR-LIS", 1),
            ("Memmo Alfama Hotel, Lisbon – Booking.com", "https://www.booking.com/hotel/pt/memmo-alfama.html", 1),
            ("Tram 28 in Lisbon: route, tickets and tips | Time Out", "https://www.timeout.com/lisbon/things-to-do/tram-28", 2),
            ("Time Out Market Lisboa", "https://www.timeoutmarket.com/lisboa/en/", 2),
            ("ThinkPad X1 Carbon Gen 13 Aura Edition | Lenovo US", "https://www.lenovo.com/us/en/p/laptops/thinkpad/thinkpadx1/x1-carbon-gen-13", 0.5),
            ("Lenovo ThinkPad X1 Carbon G13 review - Notebookcheck.net", "https://www.notebookcheck.net/Lenovo-ThinkPad-X1-Carbon-G13-review.html", 0.5),
            ("X1 Carbon vs T14s Gen 6, which one? : r/thinkpad", "https://www.reddit.com/r/thinkpad/comments/1abc/x1_carbon_vs_t14s/", 0.6),
            ("MacBook Air 13- and 15-inch with M4 - Tech Specs - Apple", "https://www.apple.com/macbook-air/specs/", 0.7),
            ("Simple Sourdough Starter From Scratch | King Arthur Baking", "https://www.kingarthurbaking.com/recipes/sourdough-starter-recipe", 20),
            ("A Beginner's Sourdough Bread Recipe | The Perfect Loaf", "https://www.theperfectloaf.com/beginners-sourdough-bread/", 20),
            ("Which size Dutch oven for a 1kg loaf? : r/Breadit", "https://www.reddit.com/r/Breadit/comments/1xyz/dutch_oven_size/", 22),
            ("Migrating to Swift 6 | Swift.org", "https://www.swift.org/migration/documentation/migrationguide/", 0.2),
            ("SE-0466: Control default actor isolation inference · swiftlang/swift-evolution", "https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md", 0.2),
            ("LanguageModelSession | Apple Developer Documentation", "https://developer.apple.com/documentation/foundationmodels/languagemodelsession", 0.1),
            ("Capture of non-sendable type in @Sendable closure - Stack Overflow", "https://stackoverflow.com/questions/78123456/capture-of-non-sendable-type", 0.3),
            ("Inbox (3) - Gmail", "https://mail.google.com/mail/u/0/#inbox", 0.05),
            ("London weather forecast - Met Office", "https://www.metoffice.gov.uk/weather/forecast/gcpvj0v07", 3),
            ("Fed holds rates steady as inflation cools | Reuters", "https://www.reuters.com/markets/us/fed-holds-rates-steady-2026-09-17/", 5),
            ("Breaking Bad 'Ozymandias' recap: the best hour of TV? | Vulture", "https://www.vulture.com/article/breaking-bad-ozymandias-recap.html", 4),
            ("Arsenal 2-1 Benfica: Champions League report - BBC Sport", "https://www.bbc.co.uk/sport/football/live/c123", 1),
            ("Lisbon (LIS) flights from London | Google Flights", "https://www.google.com/travel/flights/search?q=LHR-LIS", 6),
        ]
        return list.enumerated().map { i, tab in
            Session.Entry(id: UUID(uuidString: String(format: "7A1D0000-0000-0000-0000-%012d", i + 1))!,
                          url: tab.1, title: tab.0, viewed: now.addingTimeInterval(-tab.2 * 86_400))
        }
    }()

    /// Fixed groups, one every 450 ms, for filming the stream without a model.
    nonisolated struct ScriptedModel: TidyLanguageModel {
        func budget(instructions: String) async -> Int { 100_000 }
        func tokenCount(_ text: String) async throws -> Int { text.count / 4 }
        func propose(_ prompt: String, instructions: String) -> AsyncThrowingStream<[Tidy.Proposal], any Error> {
            let lines = prompt.split(separator: "\n").compactMap { line -> (Int, String)? in
                let parts = line.components(separatedBy: " | ")
                guard parts.count == 3, let n = Int(parts[0]) else { return nil }
                return (n, parts[2].lowercased())
            }
            func pick(_ words: [String]) -> [Int] { lines.filter { l in words.contains { l.1.contains($0) } }.map(\.0) }
            let groups = [
                Tidy.Proposal(name: "Lisbon trip", ids: pick(["lisbon", "lisboa", "alfama"])),
                Tidy.Proposal(name: "Laptop shopping", ids: pick(["thinkpad", "macbook"])),
                Tidy.Proposal(name: "Sourdough", ids: pick(["sourdough", "dutch oven"])),
                Tidy.Proposal(name: "Swift 6", ids: pick(["swift", "sendable", "languagemodel"])),
            ]
            return AsyncThrowingStream { continuation in
                let task = Task {
                    for n in 1...groups.count {
                        try? await Task.sleep(for: .milliseconds(450))
                        continuation.yield(Array(groups.prefix(n)))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        func pick(_ prompt: String, instructions: String) async throws -> [Int] { [] }
        func prewarm(instructions: String) {}
    }
}

/// Counts display frames from `start` to the first one where the sheet has
/// moved from where it began.
@MainActor private final class FrameWatch: NSObject {
    private var link: CADisplayLink?
    private var frames = 0
    private var origin: CGFloat?
    private weak var host: UIViewController?
    private var moved: (Int) -> Void = { _ in }

    func start(_ host: UIViewController, moved: @escaping (Int) -> Void) {
        self.host = host
        self.moved = moved
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick() {
        frames += 1
        guard frames < 120, let view = host?.presentationController?.presentedView ?? host?.view,
              let window = view.window else {
            if frames >= 120 { link?.invalidate() }
            return
        }
        let y = (view.layer.presentation() ?? view.layer).convert(view.bounds, to: window.layer).minY
        guard let origin else { self.origin = y; return }
        if abs(y - origin) > 0.5 {
            moved(frames)
            link?.invalidate()
        }
    }
}

// MARK: - a stand-in for the grid

@MainActor @Observable private final class Board {
    var entries: [Session.Entry]
    var grouping = Session.Grouping()
    var pressed = false

    init(entries: [Session.Entry]) { self.entries = entries }
}

/// Cards in two columns under their groups' names, the stale banner on top
/// and the bottom row with the Tidy button: the grid, roughly, as
/// docs/integration/tidy.md asks for it.
private struct BoardView: View {
    let board: Board
    let toaster: Toaster
    @Namespace private var cards

    var body: some View {
        let sections = board.grouping.sections(board.entries, id: \.id)
        let found = StaleTabs.find(board.entries, current: board.entries.first?.id)
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let line = StaleTabs.line(found) {
                        StaleBanner(line: line, onReview: {}, onClose: {})
                    }
                    ForEach(Array(sections.enumerated()), id: \.element.group?.id) { _, section in
                        if let group = section.group {
                            Text(group.name).ramp(.label).padding(.horizontal, 4).padding(.top, 4)
                        }
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                            ForEach(section.items) { entry in
                                card(entry).matchedGeometryEffect(id: entry.id, in: cards)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 90)
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            Toast(toaster: toaster).padding(.bottom, 64)
            row
        }
        .foregroundStyle(Palette.ink)
        .background(Palette.ground)
    }

    private func card(_ entry: Session.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SiteMark(url: URL(string: entry.url)!, size: 26)
            Text(entry.title).ramp(.caption).lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Palette.wash, in: .corner(Radius.card))
    }

    private var row: some View {
        HStack(spacing: 0) {
            ForEach(["gearshape", "bookmark", "plus"], id: \.self) { name in
                Image(systemName: name).font(.system(size: Ramp.row.size, weight: .medium)).frame(width: 44, height: 44)
            }
            Spacer()
            Text("\(board.entries.count) tabs").ramp(.row).foregroundStyle(Palette.muted)
            Spacer()
            Image(systemName: "rectangle.3.group")
                .font(.system(size: Ramp.row.size, weight: .medium))
                .frame(width: 44, height: 44)
                .background(Circle().fill(Palette.press).opacity(board.pressed ? 1 : 0))
            Text("Done").ramp(.row).fontWeight(.medium).frame(width: 80, height: 44)
        }
        .padding(.horizontal, 8)
        .frame(height: 50)
        .background(Palette.ground)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1 / 3) }
    }
}
#endif
