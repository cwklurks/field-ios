// Adapted from Search by Office Commun (github.com/driceroland/Search), MIT License. See NOTICE.md.
import SwiftUI

/// What there is to say when the page never came: one line, in place of the
/// page, and the only thing worth offering, another go.
struct Trouble: View {
    let message: String
    var action = "Try again"
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(message)
                .ramp(.message)
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Button(action, action: retry)
                .buttonStyle(.plain)
                .ramp(.toast)
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.ground)
    }

    /// The sentence for a failed load, or nil when it isn't a failure.
    static func message(for error: Error) -> String? {
        let error = error as NSError
        // Cancelled is what a redirect, a stopped load or a second tap in
        // quick succession looks like from here.
        guard error.code != NSURLErrorCancelled else { return nil }
        // WebKit ends a page that turned into a download with "frame load
        // interrupted" (102) while the file goes on arriving.
        guard !(error.domain == "WebKitErrorDomain" && error.code == 102) else { return nil }
        switch error.code {
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return "No site at that address."
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
            return "No connection."
        case NSURLErrorTimedOut:
            return "The site took too long to answer."
        case NSURLErrorCannotConnectToHost:
            return "The site refused the connection."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
            return "The connection isn't secure."
        default:
            return "The page didn't load."
        }
    }
}
