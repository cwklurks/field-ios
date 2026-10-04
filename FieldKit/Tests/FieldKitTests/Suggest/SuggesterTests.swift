import Foundation
import Testing
@testable import FieldKit

// The asking: a pause after the last keystroke, one request at a time, and
// an answer only ever for the words it was asked about.
@MainActor
struct SuggesterTests {
    /// Answers each URL after its own delay, and remembers what it was asked.
    actor Fake: SuggestFetching {
        var asked: [URL] = []
        let delays: [String: Duration]
        let failing: Bool
        let echo: String?

        init(delays: [String: Duration] = [:], failing: Bool = false, echo: String? = nil) {
            self.delays = delays
            self.failing = failing
            self.echo = echo
        }

        func data(for url: URL) async throws -> Data {
            asked.append(url)
            let words = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "q" }?.value ?? ""
            try? await Task.sleep(for: delays[words] ?? .zero)
            if failing { throw URLError(.timedOut) }
            return Data(#"["\#(echo ?? words)",["\#(words) one","\#(words) two"]]"#.utf8)
        }
    }

    /// What arrived, in order.
    @MainActor final class Inbox {
        var got: [[String]] = []
    }

    func url(_ words: String) -> URL { Engine.google.suggestURL(for: words)! }

    @Test func asksAfterAPauseAndDelivers() async throws {
        let fake = Fake()
        let suggester = Suggester(fetch: fake, wait: .milliseconds(20))
        let inbox = Inbox()
        suggester.ask(url("swift")) { inbox.got.append($0) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(inbox.got == [["swift one", "swift two"]])
    }

    @Test func keystrokesInsideThePauseSendOnlyTheLast() async throws {
        let fake = Fake()
        let suggester = Suggester(fetch: fake, wait: .milliseconds(80))
        let inbox = Inbox()
        for words in ["sw", "swi", "swif", "swift"] {
            suggester.ask(url(words)) { inbox.got.append($0) }
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(await fake.asked == [url("swift")])
        #expect(inbox.got == [["swift one", "swift two"]])
    }

    @Test func aLateAnswerForOldWordsNeverShows() async throws {
        // The first answer takes far longer than the second.
        let fake = Fake(delays: ["swi": .milliseconds(300)])
        let suggester = Suggester(fetch: fake, wait: .zero)
        let inbox = Inbox()
        suggester.ask(url("swi")) { inbox.got.append($0) }
        try await Task.sleep(for: .milliseconds(50))
        suggester.ask(url("swift")) { inbox.got.append($0) }
        try await Task.sleep(for: .milliseconds(600))
        #expect(await fake.asked.count == 2)
        #expect(inbox.got == [["swift one", "swift two"]])
    }

    @Test func nothingToAskCancelsWhatWasOnItsWay() async throws {
        let fake = Fake(delays: ["swift": .milliseconds(100)])
        let suggester = Suggester(fetch: fake, wait: .zero)
        let inbox = Inbox()
        suggester.ask(url("swift")) { inbox.got.append($0) }
        try await Task.sleep(for: .milliseconds(20))
        // An address typed, Private, the switch off: nil.
        suggester.ask(nil) { inbox.got.append($0) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(inbox.got.isEmpty)
    }

    @Test func stoppingInsideThePauseSendsNothing() async throws {
        let fake = Fake()
        let suggester = Suggester(fetch: fake, wait: .milliseconds(80))
        let inbox = Inbox()
        suggester.ask(url("swift")) { inbox.got.append($0) }
        suggester.stop()
        try await Task.sleep(for: .milliseconds(300))
        #expect(await fake.asked.isEmpty)
        #expect(inbox.got.isEmpty)
    }

    @Test func aFailureIsSilent() async throws {
        let fake = Fake(failing: true)
        let suggester = Suggester(fetch: fake, wait: .zero)
        let inbox = Inbox()
        suggester.ask(url("swift")) { inbox.got.append($0) }
        try await Task.sleep(for: .milliseconds(200))
        #expect(await fake.asked.count == 1)
        #expect(inbox.got == [[]])
    }

    @Test func goneIsGone() async throws {
        let fake = Fake(delays: ["swift": .milliseconds(100)])
        let inbox = Inbox()
        var suggester: Suggester? = Suggester(fetch: fake, wait: .zero)
        suggester?.ask(url("swift")) { inbox.got.append($0) }
        try await Task.sleep(for: .milliseconds(20))
        suggester = nil
        try await Task.sleep(for: .milliseconds(300))
        #expect(inbox.got.isEmpty)
    }

    @Test func anAnswerForADifferentQueryIsRejected() async throws {
        let suggester = Suggester(fetch: Fake(echo: "old query"), wait: .zero)
        let inbox = Inbox()
        suggester.ask(url("swift")) { inbox.got.append($0) }
        try await Task.sleep(for: .milliseconds(150))
        #expect(inbox.got == [[]])
    }

    // MARK: - the session

    @Test func theSessionKeepsNothingAndWaitsLittle() {
        let config = EphemeralFetch.configuration()
        #expect(config.httpCookieStorage == nil)
        #expect(config.httpShouldSetCookies == false)
        #expect(config.httpCookieAcceptPolicy == .never)
        #expect(config.urlCache == nil)
        #expect(config.urlCredentialStorage == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(config.timeoutIntervalForRequest <= 3)
        #expect(config.timeoutIntervalForResource <= 5)
        #expect(config.waitsForConnectivity == false)
    }

    @Test func theRequestCarriesNoCookieOrReferrer() {
        let request = EphemeralFetch.request(for: url("swift"))
        #expect(request.httpShouldHandleCookies == false)
        #expect(request.value(forHTTPHeaderField: "Referer") == nil)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Mozilla/5.0")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "en")
    }
}
