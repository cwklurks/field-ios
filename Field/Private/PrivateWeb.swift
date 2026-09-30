import UIKit
import WebKit

/// How a private web view differs from an everyday one. Only here: an
/// everyday tab keeps picture-in-picture, AirPlay, WebRTC and its menus.
enum PrivateWeb {
    /// The session's store, then no PiP or AirPlay (nothing of a private
    /// page outlives or leaves the app), GPC where iOS has it, no WebRTC
    /// or WebTransport, quiet fields, and a note of the picture pressed on.
    static func harden(_ config: WKWebViewConfiguration, store: WKWebsiteDataStore) {
        config.websiteDataStore = store
        config.allowsPictureInPictureMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false
        if #available(iOS 27, *) {
            config.defaultWebpagePreferences.globalPrivacyControlEnabled = true
        }
        let content = config.userContentController
        // In the page's own world, since that's where its globals are.
        content.addUserScript(WKUserScript(source: noPeers, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        content.addUserScript(WKUserScript(source: quietFields, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: Tab.world))
        content.addUserScript(WKUserScript(source: pressing, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Tab.world))
    }

    /// WebRTC and WebTransport, gone from every frame: they can reach the
    /// network around everything else (a STUN request shows your address).
    /// A frame made by script starts without user scripts, and its parent
    /// can reach into it at once, so each new frame is cleared the moment
    /// it's put in the page (and taught the same trick for its own frames).
    /// Another site's frame gets its own copy of this as it loads. A worker
    /// gets none: WebTransport is still there in one.
    static let noPeers = """
    (() => {
        const names = ["RTCPeerConnection", "webkitRTCPeerConnection", "RTCDataChannel", "RTCSessionDescription",
            "RTCIceCandidate", "RTCRtpSender", "RTCRtpReceiver", "RTCRtpTransceiver", "RTCDtlsTransport",
            "RTCIceTransport", "RTCSctpTransport", "RTCCertificate", "RTCDTMFSender", "RTCDTMFToneChangeEvent",
            "RTCTrackEvent", "RTCPeerConnectionIceEvent", "RTCPeerConnectionIceErrorEvent", "RTCDataChannelEvent",
            "RTCError", "RTCErrorEvent", "RTCRtpScriptTransform", "RTCRtpScriptTransformer", "RTCTransformEvent",
            "RTCEncodedAudioFrame", "RTCEncodedVideoFrame", "WebTransport", "WebTransportError",
            "WebTransportBidirectionalStream", "WebTransportDatagramDuplexStream", "WebTransportReceiveStream",
            "WebTransportSendStream"];
        const done = new WeakSet();
        const protect = (w) => {
            try {
                if (done.has(w.document)) return;
                done.add(w.document);
                for (const name of names) { try { delete w[name]; } catch (e) {} }
                patch(w);
                frames(w);
            } catch (e) {}
        };
        const frames = (w) => {
            try { for (let i = 0; i < w.length; i++) protect(w[i]); } catch (e) {}
        };
        const patch = (w) => {
            const after = (proto, key) => {
                const d = proto && Object.getOwnPropertyDescriptor(proto, key);
                if (!d) return;
                if (typeof d.value === "function") {
                    const f = d.value;
                    d.value = function (...a) { try { return f.apply(this, a); } finally { frames(w); } };
                } else if (d.set) {
                    const s = d.set;
                    d.set = function (v) { try { s.call(this, v); } finally { frames(w); } };
                } else {
                    return;
                }
                Object.defineProperty(proto, key, d);
            };
            for (const k of ["appendChild", "insertBefore", "replaceChild"]) after(w.Node.prototype, k);
            for (const k of ["append", "prepend", "after", "before", "replaceWith", "replaceChildren",
                "insertAdjacentElement", "insertAdjacentHTML", "innerHTML", "outerHTML", "setHTMLUnsafe"]) after(w.Element.prototype, k);
            for (const k of ["write", "writeln"]) after(w.Document.prototype, k);
            for (const k of ["contentWindow", "contentDocument"]) {
                for (const proto of [w.HTMLIFrameElement.prototype, w.HTMLFrameElement && w.HTMLFrameElement.prototype]) {
                    const d = proto && Object.getOwnPropertyDescriptor(proto, k);
                    if (!d || !d.get) continue;
                    const g = d.get;
                    d.get = function () { const v = g.call(this); frames(w); return v; };
                    Object.defineProperty(proto, k, d);
                }
            }
        };
        protect(window);
    })();
    """

    /// Every field asks the keyboard not to correct or check what's typed,
    /// which WebKit turns into autocorrection off. Password fields already
    /// are. In Field's own world: the page sees the attributes, not us.
    static let quietFields = """
    (() => {
        const fields = "input, textarea, [contenteditable]";
        const quiet = (el) => {
            if (el.getAttribute("autocorrect") !== "off") el.setAttribute("autocorrect", "off");
            if (el.getAttribute("spellcheck") !== "false") el.setAttribute("spellcheck", "false");
        };
        const sweep = (node) => {
            if (node.nodeType !== 1) return;
            if (node.matches(fields)) quiet(node);
            node.querySelectorAll(fields).forEach(quiet);
        };
        new MutationObserver((changes) => {
            for (const change of changes) {
                if (change.type === "attributes") sweep(change.target);
                else change.addedNodes.forEach(sweep);
            }
        }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ["contenteditable"] });
        // The last word, for one in a shadow root or made in between.
        addEventListener("focusin", (e) => {
            const el = e.composedPath()[0];
            if (el && el.nodeType === 1 && el.matches(fields)) quiet(el);
        }, true);
    })();
    """

    /// Notes the picture under the finger as it comes down, for Add to
    /// Photos, which WebKit's menu doesn't say.
    static let pressing = """
    addEventListener("touchstart", (e) => {
        const img = e.target && e.target.closest ? e.target.closest("img") : null;
        window.fieldPressedImage = img ? (img.currentSrc || img.src) : null;
    }, { capture: true, passive: true });
    """

    static let pressedImage = "window.fieldPressedImage || null"

    // MARK: - the long-press menu

    /// Private's Add to Photos, which asks first.
    static let saveImage = UIAction.Identifier("field.private.saveImage")

    /// WebKit's menu, less what would leave Private without asking: open in
    /// another app or in Safari, and Safari's Reading List. Add to Photos
    /// becomes one that asks (`save`). Share and Copy stay; the limits
    /// screen says those leave.
    static func menu(from suggested: [UIMenuElement], save: @escaping () -> Void) -> [UIMenuElement] {
        suggested.compactMap { element in
            if let menu = element as? UIMenu {
                return menu.replacingChildren(self.menu(from: menu.children, save: save))
            }
            guard let action = element as? UIAction else { return element }
            switch action.identifier.rawValue {
            case let id where id.hasPrefix("WKElementActionTypeOpenInExternalApplication"),
                 let id where id.hasPrefix("WKElementActionTypeOpenInDefaultBrowser"),
                 let id where id.hasPrefix("WKElementActionTypeAddToReadingList"):
                return nil
            case let id where id.hasPrefix("WKElementActionTypeSaveImage"):
                return UIAction(title: action.title, image: action.image, identifier: saveImage) { _ in save() }
            default:
                return action
            }
        }
    }

    /// The toast before a link opens another app, from a private tab.
    static func leaving(to url: URL) -> String {
        Tab.leaving(to: url).replacingOccurrences(of: ".", with: ", outside Private.", options: [.anchored, .backwards])
    }
}

/// Stands in front of a private tab as its web view's UI delegate: the
/// long-press menu is Private's, everything else goes to the tab. Only a
/// private web view has one, since a delegate that answers the menu at all
/// decides it, and everyday tabs keep WebKit's own.
final class PrivateUIDelegate: NSObject, WKUIDelegate {
    nonisolated(unsafe) private weak var tab: (NSObject & WKUIDelegate)?
    private let menu: (WKContextMenuElementInfo, WKWebView) -> UIContextMenuConfiguration?

    init(wrapping tab: NSObject & WKUIDelegate, menu: @escaping (WKContextMenuElementInfo, WKWebView) -> UIContextMenuConfiguration?) {
        self.tab = tab
        self.menu = menu
    }

    func webView(
        _ webView: WKWebView,
        contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
        completionHandler: @escaping @MainActor (UIContextMenuConfiguration?) -> Void
    ) {
        completionHandler(menu(elementInfo, webView))
    }

    nonisolated override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || tab?.responds(to: selector) == true
    }

    nonisolated override func forwardingTarget(for selector: Selector!) -> Any? {
        tab
    }
}
