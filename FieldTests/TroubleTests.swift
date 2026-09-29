import Foundation
import Testing
@testable import Field

/// A page that never came says so in one sentence, in the Mac's words.
struct TroubleTests {
    private func error(_ code: Int, _ domain: String = NSURLErrorDomain) -> NSError {
        NSError(domain: domain, code: code)
    }

    @Test func theMacsSentences() {
        #expect(Trouble.message(for: error(NSURLErrorCannotFindHost)) == "No site at that address.")
        #expect(Trouble.message(for: error(NSURLErrorDNSLookupFailed)) == "No site at that address.")
        #expect(Trouble.message(for: error(NSURLErrorNotConnectedToInternet)) == "No connection.")
        #expect(Trouble.message(for: error(NSURLErrorNetworkConnectionLost)) == "No connection.")
        #expect(Trouble.message(for: error(NSURLErrorTimedOut)) == "The site took too long to answer.")
        #expect(Trouble.message(for: error(NSURLErrorCannotConnectToHost)) == "The site refused the connection.")
        #expect(Trouble.message(for: error(NSURLErrorSecureConnectionFailed)) == "The connection isn't secure.")
        #expect(Trouble.message(for: error(NSURLErrorServerCertificateUntrusted)) == "The connection isn't secure.")
        #expect(Trouble.message(for: error(NSURLErrorBadServerResponse)) == "The page didn't load.")
    }

    /// Cancelled is a redirect, a stopped load or a second tap, and 102 is a
    /// page that became a download: neither is a failure.
    @Test func notFailures() {
        #expect(Trouble.message(for: error(NSURLErrorCancelled)) == nil)
        #expect(Trouble.message(for: error(102, "WebKitErrorDomain")) == nil)
    }
}
