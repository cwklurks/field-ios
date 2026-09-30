import FieldKit
import Foundation
import FoundationModels

/// The one seam between Tidy and a language model: Apple's on-device model
/// in the app, a scripted one in the tests and the harness. Everything that
/// isn't the model itself (the prompt, batching, checking what comes back,
/// splitting a refused batch) is TidyEngine's and FieldKit's, so it's tested
/// without one.
nonisolated protocol TidyLanguageModel: Sendable {
    /// How many tokens the tab list may take in one request, once the
    /// instructions, the schema and room for the answer are paid for.
    func budget(instructions: String) async -> Int
    func tokenCount(_ text: String) async throws -> Int
    /// Groups for one batch. Each element is every group finished so far,
    /// so they can be shown as they come; the last is the whole answer.
    /// Fails with TidyModelError.
    func propose(_ prompt: String, instructions: String) -> AsyncThrowingStream<[Tidy.Proposal], any Error>
    /// "Add similar tabs": the numbers of the tabs that belong.
    func pick(_ prompt: String, instructions: String) async throws -> [Int]
    /// Loads the model ahead of the first request.
    func prewarm(instructions: String)
}

/// What the engine needs to know of a model's failure.
nonisolated enum TidyModelError: Error, Equatable {
    /// The input or output tripped a guardrail, or the model declined:
    /// usually one title in the batch. Split the batch and ask again.
    case refused
    /// More than the context holds. Split the batch and ask again.
    case tooLong
    /// Anything else (rate limits, a language it doesn't do, assets not
    /// ready): the rules take the batch.
    case failed
}

// MARK: - Apple's on-device model

/// The groups the model writes, by guided generation: the shape is always
/// right, the numbers are checked afterwards (Tidy.validate).
@Generable
nonisolated struct TidyPlan {
    @Guide(description: "Groups of tabs about one topic or task", .maximumCount(10))
    var groups: [Topic]

    @Generable
    nonisolated struct Topic {
        @Guide(description: "A specific name of 1 to 3 plain words, no emoji, like Lisbon trip or ThinkPad shopping")
        var name: String
        @Guide(description: "The numbers of the tabs in this group")
        var ids: [Int]
    }
}

@Generable
nonisolated struct TidyPick {
    @Guide(description: "The numbers of the tabs that belong in the group")
    var ids: [Int]
}

/// Apple's on-device model behind TidyLanguageModel. Each batch gets a
/// fresh session, so one batch's text never eats into the next one's
/// context. Greedy sampling: the same tabs give the same groups.
nonisolated final class SystemTidyModel: TidyLanguageModel, @unchecked Sendable {
    static let shared = SystemTidyModel()

    /// Kept only so a prewarmed model stays loaded until it's first used;
    /// only the engine's actor touches it.
    private var warm: (instructions: String, session: LanguageModelSession)?

    /// Nil when there's no model on this phone, it's off, still
    /// downloading, or doesn't do the phone's language: then the rules run.
    static func ifAvailable() -> SystemTidyModel? {
        let model = SystemLanguageModel.default
        guard case .available = model.availability, model.supportsLocale() else { return nil }
        return shared
    }

    private var model: SystemLanguageModel { .default }
    private var options: GenerationOptions { GenerationOptions(samplingMode: .greedy) }

    func budget(instructions: String) async -> Int {
        // 4096 in 2025, 8192 on some hardware since: read, never assumed.
        // The simulator says 0 for a model it can't run; assume the least.
        let size = model.contextSize > 0 ? model.contextSize : 4096
        var overhead = instructions.utf8.count / 3 + 600
        if #available(iOS 26.4, *) {
            let words = try? await model.tokenCount(for: Instructions(instructions))
            let schema = try? await model.tokenCount(for: TidyPlan.generationSchema)
            if let words, let schema { overhead = words + schema }
        }
        // A quarter for the answer (a few tokens a tab, and the names), and
        // a little for the line of names already used.
        return max(200, size - overhead - size / 4 - 120)
    }

    func tokenCount(_ text: String) async throws -> Int {
        if #available(iOS 26.4, *) { return try await model.tokenCount(for: Prompt(text)) }
        // Before 26.4 there's no counter: a cautious guess, about three
        // bytes a token for English and fewer for most other scripts.
        return text.utf8.count / 3 + 1
    }

    func propose(_ prompt: String, instructions: String) -> AsyncThrowingStream<[Tidy.Proposal], any Error> {
        let options = self.options
        let (stream, continuation) = AsyncThrowingStream<[Tidy.Proposal], any Error>.makeStream()
        let session = takeSession(instructions)
        let task = Task {
            do {
                var finished = 0
                let response = session.streamResponse(to: prompt, generating: TidyPlan.self, options: options)
                for try await snapshot in response {
                    // Every group but the last is finished once the next begins.
                    let groups = snapshot.content.groups ?? []
                    let done = groups.dropLast().compactMap(Self.proposal)
                    if done.count > finished {
                        finished = done.count
                        continuation.yield(done)
                    }
                }
                let whole = try await response.collect().content
                continuation.yield(whole.groups.map { Tidy.Proposal(name: $0.name, ids: $0.ids) })
                continuation.finish()
            } catch {
                continuation.finish(throwing: Self.classify(error))
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    func pick(_ prompt: String, instructions: String) async throws -> [Int] {
        let session = takeSession(instructions)
        do {
            return try await session.respond(to: prompt, generating: TidyPick.self, options: options).content.ids
        } catch {
            throw Self.classify(error)
        }
    }

    func prewarm(instructions: String) {
        guard warm?.instructions != instructions else { return }
        let session = LanguageModelSession(model: model, instructions: instructions)
        session.prewarm()
        warm = (instructions, session)
    }

    /// The prewarmed session for the first request with its instructions,
    /// a new one after that.
    private func takeSession(_ instructions: String) -> LanguageModelSession {
        defer { warm = nil }
        if let warm, warm.instructions == instructions { return warm.session }
        return LanguageModelSession(model: model, instructions: instructions)
    }

    private static func proposal(_ topic: TidyPlan.Topic.PartiallyGenerated) -> Tidy.Proposal? {
        guard let name = topic.name, let ids = topic.ids else { return nil }
        return Tidy.Proposal(name: name, ids: ids)
    }

    /// The 26 errors and the 27 ones, sorted into what the engine does next.
    static func classify(_ error: any Error) -> TidyModelError {
        if error is CancellationError { return .failed }
        if #available(iOS 27.0, *), let error = error as? LanguageModelError {
            switch error {
            case .guardrailViolation, .refusal: return .refused
            case .contextSizeExceeded: return .tooLong
            default: return .failed
            }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .guardrailViolation, .refusal: return .refused
            case .exceededContextWindowSize: return .tooLong
            default: return .failed
            }
        }
        return .failed
    }
}
