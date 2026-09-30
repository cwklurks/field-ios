import Foundation
import Testing
import UIKit
import WebKit
@testable import Field

/// Private's web view configuration against real pages: no WebRTC or
/// WebTransport in any frame, quiet fields, GPC, and no PiP or AirPlay.
@Suite(.serialized)
@MainActor struct PrivateWebTests {
    /// A page that looks for WebRTC every way a page can: itself, fresh
    /// frames reached at once, a srcdoc frame, another site's frame and a
    /// worker, each reporting into `window.found`.
    static func server() async throws -> PrivateServer {
        try await PrivateServer.start { path, head in
            if path.hasPrefix("/child") {
                return .init(body: """
                <!doctype html><script>
                parent.postMessage({frame: "child", rtc: typeof RTCPeerConnection, wt: typeof WebTransport}, "*");
                </script>
                """)
            }
            if path.hasPrefix("/fields") {
                return .init(body: """
                <!doctype html><body><input id="a"><textarea id="b"></textarea><div id="c" contenteditable></div>
                <input id="pw" type="password"><script>
                setTimeout(() => { const d = document.createElement("input"); d.id = "d"; document.body.appendChild(d); }, 0);
                </script>
                """)
            }
            if path.hasPrefix("/headers") {
                let gpc = head.split(separator: "\r\n").first { $0.lowercased().hasPrefix("sec-gpc:") } ?? "none"
                return .init(body: "<!doctype html><p id=gpc>\(gpc)</p>")
            }
            let other = path.split(separator: "?").dropFirst().first.map(String.init) ?? ""
            return .init(body: """
            <!doctype html><body><script>
            const found = window.found = {};
            found.main = typeof RTCPeerConnection;
            found.dataChannel = typeof RTCDataChannel;
            found.webkit = typeof webkitRTCPeerConnection;
            found.transport = typeof WebTransport;
            // A fresh about:blank frame, reached at once: the usual way round.
            const a = document.createElement("iframe");
            document.body.appendChild(a);
            found.blank = typeof a.contentWindow.RTCPeerConnection;
            found.frames = typeof window.frames[0].RTCPeerConnection;
            // Parsed in, with no call that makes an element.
            const holder = document.createElement("div");
            holder.innerHTML = "<iframe></iframe>";
            document.body.appendChild(holder);
            found.inner = typeof window.frames[1].RTCPeerConnection;
            // A frame inside the fresh frame, made with its own document.
            const nested = a.contentDocument.createElement("iframe");
            a.contentDocument.body.appendChild(nested);
            found.nested = typeof a.contentWindow.frames[0].RTCPeerConnection;
            addEventListener("message", e => { found[e.data.frame] = e.data.rtc; if (e.data.wt) found[e.data.frame + "Transport"] = e.data.wt; });
            const s = document.createElement("iframe");
            s.srcdoc = "<script>parent.postMessage({frame: 'srcdoc', rtc: typeof RTCPeerConnection}, '*')<\\/script>";
            document.body.appendChild(s);
            const c = document.createElement("iframe");
            c.src = "\(other)child";
            document.body.appendChild(c);
            try {
                const w = new Worker(URL.createObjectURL(new Blob(["postMessage(typeof WebTransport)"])));
                w.onmessage = e => found.worker = e.data;
            } catch (e) { found.worker = "none"; }
            </script>
            """)
        }
    }

    func open(_ server: PrivateServer, _ config: WKWebViewConfiguration) async throws -> PrivatePage {
        let page = PrivatePage(config)
        try await page.open(server.url.appending(path: "rtc").appending(queryItems: [.init(name: server.otherSite.absoluteString, value: nil)]))
        _ = try await page.poll("window.found.child && window.found.srcdoc && window.found.worker ? 1 : null")
        return page
    }

    func found(_ page: PrivatePage) async throws -> [String: String] {
        try await page.page("window.found") as? [String: String] ?? [:]
    }

    /// Without Private's script, WebRTC is there in every frame: the check
    /// below means something.
    @Test func everydayPagesHaveWebRTC() async throws {
        let server = try await Self.server()
        defer { server.stop() }
        let page = try await open(server, WKWebViewConfiguration())
        let found = try await found(page)
        #expect(found["main"] == "function")
        #expect(found["blank"] == "function")
        #expect(found["child"] == "function")
    }

    @Test func noWebRTCInAnyFrame() async throws {
        let server = try await Self.server()
        defer { server.stop() }
        let space = PrivateSpace()
        let config = WKWebViewConfiguration()
        space.configure(config)
        let page = try await open(server, config)
        let found = try await found(page)
        for frame in ["main", "dataChannel", "webkit", "blank", "frames", "inner", "nested", "srcdoc", "child"] {
            #expect(found[frame] == "undefined", "\(frame): \(found[frame] ?? "missing")")
        }
        #expect(found["transport"] == "undefined")
        #expect(found["childTransport"] == "undefined")
        // A worker has no user scripts; said here so a change shows.
        print("Private: WebTransport in a worker is \(found["worker"] ?? "missing")")
    }

    /// Every field says autocorrect off and no spellcheck, those added
    /// later included, while the page's own script sees nothing of ours.
    @Test func fieldsAreQuiet() async throws {
        let server = try await Self.server()
        defer { server.stop() }
        let space = PrivateSpace()
        let config = WKWebViewConfiguration()
        space.configure(config)
        let page = PrivatePage(config)
        try await page.open(server.url.appending(path: "fields"))
        _ = try await page.poll("document.getElementById('d') ? 1 : null")
        try await Task.sleep(for: .milliseconds(100))
        for id in ["a", "b", "c", "d", "pw"] {
            let quiet = try await page.page("""
            (() => { const e = document.getElementById("\(id)");
            return e.getAttribute("autocorrect") === "off" && e.getAttribute("spellcheck") === "false"; })()
            """) as? Bool
            #expect(quiet == true, "\(id)")
        }
    }

    @Test func noPictureInPictureOrAirPlay() {
        let config = WKWebViewConfiguration()
        PrivateSpace().configure(config)
        #expect(!config.allowsPictureInPictureMediaPlayback)
        #expect(!config.allowsAirPlayForMediaPlayback)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 27, minorVersion: 0, patchVersion: 0))))
    func sendsGlobalPrivacyControl() async throws {
        let server = try await Self.server()
        defer { server.stop() }
        let config = WKWebViewConfiguration()
        PrivateSpace().configure(config)
        let page = PrivatePage(config)
        try await page.open(server.url.appending(path: "headers"))
        let header = try await page.page("document.getElementById('gpc').textContent") as? String
        #expect(header?.lowercased().replacingOccurrences(of: " ", with: "") == "sec-gpc:1")
        #expect(try await page.page("navigator.globalPrivacyControl") as? Bool == true)
    }

    // MARK: - the long-press menu

    func action(_ id: String) -> UIAction {
        UIAction(title: id, identifier: UIAction.Identifier(id)) { _ in }
    }

    /// Add to Photos asks first; what would open another app or Safari,
    /// or add to Safari's Reading List, is gone; the rest is WebKit's own.
    @Test func menuAsksBeforePhotosAndNeverLeaves() {
        var asked = 0
        let suggested: [UIMenuElement] = [
            action("WKElementActionTypeOpen"),
            action("WKElementActionTypeOpenInExternalApplication"),
            action("WKElementActionTypeOpenInDefaultBrowser"),
            UIMenu(title: "", options: .displayInline, children: [
                action("WKElementActionTypeCopy"),
                action("WKElementActionTypeSaveImage"),
                action("WKElementActionTypeAddToReadingList"),
            ]),
            action("WKElementActionTypeShare"),
        ]
        let menu = PrivateWeb.menu(from: suggested) { asked += 1 }
        func ids(_ elements: [UIMenuElement]) -> [String] {
            elements.flatMap { element -> [String] in
                if let menu = element as? UIMenu { return ids(menu.children) }
                return [(element as? UIAction)?.identifier.rawValue ?? "?"]
            }
        }
        #expect(ids(menu) == ["WKElementActionTypeOpen", "WKElementActionTypeCopy", PrivateWeb.saveImage.rawValue, "WKElementActionTypeShare"])
    }

    /// Private's delegate stands in front of the tab's and passes on
    /// everything but the menu.
    @Test func delegatePassesTheRestOn() {
        let tab = Tab(history: HistoryStore(directory: URL(filePath: "/dev/null"), seed: 0))
        let wrapper = PrivateUIDelegate(wrapping: tab) { _, _ in nil }
        let create = #selector(WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:))
        let menu = #selector(WKUIDelegate.webView(_:contextMenuConfigurationForElement:completionHandler:))
        #expect(wrapper.responds(to: create))
        #expect(wrapper.responds(to: menu))
        #expect(wrapper.forwardingTarget(for: create) as AnyObject === tab)
        #expect(!wrapper.responds(to: #selector(WKUIDelegate.webViewDidClose(_:))))
    }

    @Test func leavingSaysItLeavesPrivate() {
        #expect(PrivateWeb.leaving(to: URL(string: "mailto:a@b.c")!) == "This link opens Mail, outside Private.")
        #expect(PrivateWeb.leaving(to: URL(string: "weird://x")!) == "This link opens another app, outside Private.")
    }
}
