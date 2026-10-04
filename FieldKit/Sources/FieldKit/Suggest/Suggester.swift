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
    /// whatever was on its way.
    public func ask(_ url: URL?, deliver: @escaping @MainActor ([String]) -> Void) {
        stop()
        guard let url else { return }
        let mine = generation
        task = Task { [fetch, wait, weak self] in
            do {
                if wait > .zero { try await Task.sleep(for: wait) }
                let data = try await fetch.data(for: url)
                let words = SuggestResponse.words(from: data)
                guard !Task.isCancelled, let self, self.generation == mine else { return }
                deliver(words)
            } catch {
                // Cancelled, offline, slow or refused: no suggestions.
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

/// A session that keeps nothing: no cookies sent or taken, no cache, no
/// stored credentials, and not long to wait. URLSession sends no referrer of
/// its own, and the request says it has no cookies to handle.
public struct EphemeralFetch: SuggestFetching {
    public static let shared = EphemeralFetch()

    private let session: URLSession

    public init() {
        session = URLSession(configuration: Self.configuration())
    }

    public static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 3
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json, text/javascript"]
        return config
    }

    static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 2)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        return request
    }

    public func data(for url: URL) async throws -> Data {
        let (data, response) = try await session.data(for: Self.request(for: url))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }
}
