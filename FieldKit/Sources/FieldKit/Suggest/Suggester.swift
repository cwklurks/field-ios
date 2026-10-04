import Foundation

/// The network, at the edge: a URL in, the body of a 200 out.
public protocol SuggestFetching: Sendable {
    func data(for url: URL) async throws -> Data
}

/// Asks the engine as you type: a short pause after the last keystroke, one
/// request at a time, the one before cancelled by each new keystroke, and an
/// answer delivered only for the very request it answers. Failures say
/// nothing; the rows from the phone are there either way.
@MainActor public final class Suggester {
    private let fetch: any SuggestFetching
    private let wait: Duration
    private var task: Task<Void, Never>?
    /// Bumped on every ask, so an answer can tell it has been overtaken
    /// even if its cancellation hasn't reached it yet.
    private var generation = 0

    public init(fetch: any SuggestFetching = EphemeralFetch.shared, wait: Duration = .milliseconds(120)) {
        self.fetch = fetch
        self.wait = wait
    }

    isolated deinit {
        task?.cancel()
    }

    /// Asks `url` after the pause, and hands what it suggests to `deliver`,
    /// unless another ask or a stop comes first. Nil asks nothing, and stops
    /// whatever was on its way. `allowed` rechecks privacy after the pause
    /// and before delivery. A current failure delivers an empty list.
    public func ask(
        _ url: URL?, allowed: @escaping @MainActor () -> Bool = { true },
        deliver: @escaping @MainActor ([String]) -> Void
    ) {
        stop()
        guard let url else { return }
        let mine = generation
        task = Task { [fetch, wait, weak self] in
            do {
                if wait > .zero { try await Task.sleep(for: wait) }
                guard !Task.isCancelled, allowed() else { return }
                let data = try await fetch.data(for: url)
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                    .first { $0.name == "q" || $0.name == "query" }?.value
                let words = SuggestResponse.words(from: data, for: query)
                guard !Task.isCancelled, let self, self.generation == mine, allowed() else { return }
                deliver(words)
            } catch {
                // A failed current request settles the pending rows too.
                guard !Task.isCancelled, let self, self.generation == mine, allowed() else { return }
                deliver([])
            }
        }
    }

    /// Nothing more is wanted: the field closed, or went.
    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
    }
}
