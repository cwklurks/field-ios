import FieldKit
import UIKit
import UniformTypeIdentifiers
import os

/// The navigation guard (FieldKit's Guard/README.md), once its rules have
/// loaded off the main thread after the first frame. Until then there's
/// none, and navigations pass unguarded.
enum Guarded {
    static var current: Guard?
    /// Asked for before the rules had loaded (see loaded()).
    private static var waiting: [CheckedContinuation<Guard, Never>] = []

    /// What the guard changed, under `guard` in the log. Addresses are private.
    nonisolated static let log = Logger(subsystem: "com.connork.field", category: "guard")

    /// Once, after the first frame. From then on the blocker's per-site
    /// switch keys by the same sites as the guard.
    static func load() {
        Task.detached(priority: .utility) {
            let rules = GuardRules.bundled
            await MainActor.run {
                let loaded = Guard(rules: rules)
                current = loaded
                ContentBlocking.shared.site = rules.site(of:)
                waiting.forEach { $0.resume(returning: loaded) }
                waiting = []
            }
        }
    }

    /// The guard, once its rules have loaded: a link from another app at
    /// launch waits the few milliseconds for them, to land clean.
    static func loaded() async -> Guard {
        if let current { return current }
        return await withCheckedContinuation { waiting.append($0) }
    }

    /// The address to copy or share: without its tracking parameters.
    static func stripped(_ url: URL) -> URL {
        current?.stripped(url) ?? url
    }

    /// A page's address on the pasteboard, stripped, as a link and as text.
    static func copy(_ url: URL) {
        let clean = stripped(url)
        UIPasteboard.general.setItems([[UTType.url.identifier: clean, UTType.utf8PlainText.identifier: clean.absoluteString]])
    }
}
