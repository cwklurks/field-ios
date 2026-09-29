# Tor mode for Field's private tabs

Researched 2026-09-25

**Decision:** Tor is built into Field using the recommended architecture: embedded C tor (iCepa Tor.framework) plus IPtProxy for bridges. It ships in the second release, after private mode.

**Bottom line:** Embed C tor (via iCepa Tor.framework's prebuilt xcframework) plus IPtProxy for bridges. Give each Tor tab its own non-persistent `WKWebsiteDataStore` with a SOCKS5 `ProxyConfiguration`, and turn on per-webview Lockdown Mode. Keep Arti behind an interface and swap it in later: Arti itself is ready, but its iOS packaging is a year stale. We must tell users plainly that this is "Tor routing", not Tor Browser.

## 1. Embedding options

### (a) Arti embedded

- Upstream is mature. The latest release is Arti 2.6.0 (crates.io 2026-09-02; blog dated Sept 1). The README says "Arti is a full-featured Tor client… suitable for general client usage" (as of Aug 2026).
  - https://gitlab.torproject.org/tpo/core/arti/-/raw/main/README.md
  - https://blog.torproject.org/arti_2_6_0_released/
- Compatibility.md (Feb 2026) says "Arti is the preferred Tor client for new feature development". Two client features are still missing: Conflux and circuit padding machines.
  - https://gitlab.torproject.org/tpo/core/arti/-/raw/main/doc/Compatibility.md
- The iOS packaging lags badly:
  - Tor.framework's `arti.xcframework` is **Arti 1.7.0**, released 2025-10-30. It was last shipped in v408.22.1 on 2026-02-04.
  - Guardian Project's `arti-mobile` also ships 1.7.0.1. Last commit was 2026-07-07.
  - The onionmobile guide says Arti on mobile is "still quite experimental and not actively maintained."
  - https://guide.onionmobile.dev/tor-on-ios/arti-and-onionmasq-on-ios.md
  - https://gitlab.com/guardianproject/tormobile/arti-mobile
- Arti's own iOS doc says "no proper bindings are provided".
  - https://gitlab.torproject.org/tpo/core/arti/-/blob/main/doc/iOS.md
- The prebuilt C API has only two calls: `start_arti(state_dir, cache_dir, obfs4_port, snowflake_port, …, socks_port, dns_port, log_fn)` and `stop_arti()`. There is no control port, so no circuit listing, closing or NEWNYM.
- Size, measured from the ios-arm64 static library before dead-stripping: about 28 MB of `__TEXT`.
- Memory: I found no published figures.

### (b) C tor via iCepa Tor.framework

- Actively maintained. v409.13.1 shipped on 2026-09-25 (tor 0.4.9.13, OpenSSL 3.6.4); v409.12.1 shipped 2026-09-22.
  - https://github.com/iCepa/Tor.framework/releases
- Onion Browser uses it today.
- It is distributed through CocoaPods only, and CocoaPods trunk goes read-only on **2026-12-02**.
  - https://blog.cocoapods.org/CocoaPods-Specs-Repo/
- Size, measured the same way: tor + OpenSSL + libevent + lzma is about 8 MB of `__TEXT` on arm64.
- TorManager, the convenience wrapper, has had no push since 2025-09.

### (c) Orbot as a system VPN

- Orbot iOS v1.12.0 (2026-06-30). The App Store seller is now "The Tor Project, Inc".
- It is the strongest option against leaks, because everything goes through the tunnel. Onion Browser's FAQ: "With Orbot, these problems were gone" (WebRTC, A/V).
- The Network Extension is capped at 50 MB, so tor gets killed. The default is `MaxMemInQueues` 5 MB.
  - https://orbot.app/en/faqs/
  - https://onionbrowser.com/faqs
- It conflicts with our goal: it tunnels the whole device, including normal tabs. You can detect it via OrbotKit.

### (d) Other options

- Onionmasq (Arti on packets) is available on iOS only as an experimental podspec.
- Tor VPN is Android-only (beta, Arti + onionmasq).
  - https://blog.torproject.org/tor-vpn-beta/
- No iOS browser has shipped an alternative engine under the EU/Japan rules, and there is no Tor Browser for iOS.
  - https://support.torproject.org/tormobile/tormobile-3/

## 2. Routing WKWebView

### The API

- `WKWebsiteDataStore.proxyConfigurations: [ProxyConfiguration]` exists from iOS 17. Apple's page for it has **no discussion text**.
- `ProxyConfiguration` offers `init(socksv5Proxy:)`, `init(httpCONNECTProxy:)`, `applyCredential(username:password:)` and `allowFailover` (off by default).
  - https://developer.apple.com/documentation/network/proxyconfiguration
  - WWDC23 session 10002, "Ready, set, relay": https://developer.apple.com/videos/play/wwdc2023/10002/
- Proxy-side DNS: hostnames go to the proxy, which is why .onion loads in Onion Browser's built-in mode.

### How Onion Browser does it

- It sets `ProxyConfiguration(socksv5Proxy:)` on the store **before** creating the WKWebView. If tor isn't up, it defers creating the view.
- It refuses every navigation unless tor is started and the store's `proxyConfigurations` is non-empty.
- It proxies its own `URLSession`s. If tor is down it points them at an invalid loopback endpoint, so they fail closed.
- It ships Lockdown Mode at its Silver/Gold security levels.
- Code: `Tab.swift:494`, `BaseNavigationDelegate.swift:27`, `TorManager.swift:333` in https://github.com/OnionBrowser/OnionBrowser (3.X branch).

### Known leaks

- Mysk (2026-08-04) found three bypasses: `dns-prefetch` (iOS 26.0+), WebAuthn Related Origin fetches made by the OS (iOS 18+), and WebTransport over direct QUIC (iOS 26.4+).
  - https://mysk.blog/2026/08/04/webkit-proxy-icloud-private-relay-ip-leak/
- Onion Browser 3.4.1 fixed dns-prefetch with a content rule that blocks the `ping` resource type. It says Lockdown covers the rest.
- WebKit's `UnifiedWebPreferences.yaml` marks PeerConnection (WebRTC), WebTransport, ServiceWorkers, WebGL and WebAudio as `disableInLockdownMode`. It does **not** mark WebAuthn.
  - https://github.com/WebKit/WebKit/blob/main/Source/WTF/Scripts/Preferences/UnifiedWebPreferences.yaml
- Onion Browser's FAQ says built-in mode **leaks the real IP via WebRTC** and "audio and video streams cannot be tunneled."
  - https://onionbrowser.com/faqs
- Onion Browser's changelog records app-side leaks it had to fix: favicons, live search, downloads and bookmark sync.
  - https://raw.githubusercontent.com/OnionBrowser/OnionBrowser/3.X/CHANGELOG.md
- OCSP from trustd, WebSockets, preconnect and service workers: I could not verify these one by one.

### Normal tabs direct and Tor tabs proxied at the same time: yes, with evidence

- Psylo gives every tab ("silo") a different proxy IP.
  - https://mysk.blog/2025/06/17/introducing-psylo/
- webspace_app PR #605 measured four data stores reaching four distinct upstreams in one process. It also confirmed on a device that `applyCredential` is sent.
  - https://github.com/theoden8/webspace_app/pull/605
- Warning, unverified: the same PR reports that a WebView's *later* navigations went DIRECT in their Flutter harness. That contradicts Onion Browser and Psylo in production, but it is exactly why we need our own leak-test matrix.
- `applyCredential` had a bug confirmed by Apple DTS in 2023 (FB13350370).
  - https://developer.apple.com/forums/thread/734679

## 3. .onion, bridges, isolation, lifecycle

- **.onion:** works through SOCKS hostnames. Onion client auth works through the control port (C tor only).
- **Bridges:** IPtProxy runs in-process: Lyrebird 0.8.1 (obfs4, meek_lite, WebTunnel), Snowflake 2.14.1 and DNSTT. It supports SwiftPM; last commit 2026-09-16. C tor points `ClientTransportPlugin` at its local ports. Arti's `start_arti` takes obfs4 and snowflake ports, and upstream supports unmanaged PTs via `proxy_addr`.
  - https://github.com/tladesignz/IPtProxy
- **Isolation:**
  - tor's `IsolateSOCKSAuth` is on by default, and Arti's SOCKS layer also isolates by auth (`crates/arti/src/proxy/socks.rs`). A unique SOCKS username per tab gives each tab its own circuits.
    - https://spec.torproject.org/socks-extensions.html
  - This is per *tab*, not per first party like Tor Browser, because the proxy is set per data store.
  - "New circuit" means `CLOSECIRCUIT` over the control port (Onion Browser does this). "New identity" means a new non-persistent store, a new credential and `SIGNAL NEWNYM`.
  - Fallback if credentials misbehave: a separate `SocksPort` per tab. Separate ports never share circuits.
- **Background:**
  - iOS suspends the app about 5 s after it goes to the background; `beginBackgroundTask` buys a little more time.
    - https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time
  - Onion Browser stops tor when that time runs out and restarts it on return. Its changelog notes a "broken state when app was in background for too long" fix.
  - Nothing runs while suspended, so there is no battery drain in the background.
- **Bootstrap time and battery:** I found no primary measurements (unverified). My estimates: a warm start with a cached consensus in Caches takes a few seconds; a cold start on LTE takes about 5–20 s; bridges and Snowflake take longer.

## 4. Fingerprinting

### What Tor Browser has that we can't match

- Letterboxing.
- One shared UA per OS family (all Android users report "Android 10").
- UTC timezone and a spoofed locale.
- Canvas extraction blocking.
- NoScript security levels.
- First-party isolation.
- WebRTC that is proxied, with non-proxied UDP disabled.

Sources:
- https://support.torproject.org/tor-browser/features/fingerprinting-protections/
- https://blog.torproject.org/new-release-tor-browser-130/

### What WKWebView gives us

Per-navigation JS on/off, per-webview Lockdown Mode (no JIT, WebGL or WebRTC; close to Tor Browser's "Safer"), and a UA string override. JavaScript can still see the real engine and iOS version, and timezone/locale shims are detectable.

- https://developer.apple.com/documentation/webkit/wkwebpagepreferences/islockdownmodeenabled

### What Onion Browser admits

WebKit "has very few levers… best, if you look very much like every other iOS user." The Tor Project says WebKit "prevents Onion Browser from having the same privacy protections as Tor Browser."

- https://onionbrowser.com/faqs
- https://support.torproject.org/tormobile/tormobile-3/

### Suggested honest wording

> Tor tabs hide your IP address and let you open .onion sites. This is not Tor Browser. Apple requires WebKit, so websites can tell you're on an iPhone using Tor, and a site can recognise you within a tab or if you log in. We turn off features that could leak your real IP (WebRTC calls, passkeys, WebTransport, some media). If you are at high risk, use Tor Browser on desktop or Android, or Tails.

## 5. App Store and legal

- The Guidelines (last updated June 8, 2026) have no Tor rule.
  - 2.5.6 requires WebKit; we comply.
  - 5.4 governs NEVPNManager VPN apps only; an in-app proxy isn't one.
  - https://developer.apple.com/app-store/review/guidelines/
- Onion Browser (since 2012; 3.4.1 on 2026-08-21), Orbot and Psylo are all live on the App Store. I found no recent rulings against them.
- Regional risk: Apple removed around 60 VPN/proxy apps in Russia in 2024 and delists in China.
  - https://mjtsai.com/blog/2024/07/05/apple-removes-vpn-apps-from-russian-app-store/
- Export: we bundle non-OS crypto (OpenSSL / Rust crypto).
  - Apple says to set `ITSAppUsesNonExemptEncryption` and complete the questionnaire.
    - https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
  - Onion Browser declares `false`; that is their legal call.
  - France (ANSSI) controls "secure communications" apps.
  - **Get counsel.** I expect "YES, standard algorithms, mass market," but I have not verified that.

## 6. Recommendation

### Architecture

- A `TorEngine` protocol (start, SOCKS endpoint, bootstrap progress, new circuit, stop) with a `CTorEngine` implementation.
- Consume Tor.framework's `tor.xcframework` as a SwiftPM `binaryTarget` with a checksum, and vendor its MIT Obj-C `Core`/`CTor` wrapper. Do **not** use CocoaPods.
- IPtProxy through SwiftPM.
- Revisit Arti once Tor.framework or arti-mobile ships a 2.x build with a control/RPC surface.

### Integration steps

1. Start tor lazily on the first Tor tab: `SocksPort auto`, a Unix-socket control port with cookie auth, `ClientOnly 1`, data dir in Caches. Show bootstrap progress.
2. For each Tor tab:
   - Create `WKWebsiteDataStore.nonPersistent()`.
   - Set `proxyConfigurations = [SOCKS5]` with `applyCredential(tabUUID, nonce)` **before** creating the WKWebView.
   - Leave `allowFailover` false.
   - Normal tabs keep their unproxied store.
3. Tor tabs' `WKWebpagePreferences`: `isLockdownModeEnabled = true` by default; offer a JS toggle.
4. Content rules for Tor tabs: block `ping` (dns-prefetch). Add a document-start, all-frames script that removes `PublicKeyCredential`/`navigator.credentials` and `WebTransport`. Block `media` unless our leak test shows A/V is proxied on iOS 26.
5. Navigation gate in `decidePolicyFor`: refuse if tor isn't started or the store's proxy list is empty.
6. App networking for Tor tabs: every request (favicons, suggestions, downloads) goes through an ephemeral `URLSession` with the same proxy, failing closed. No LinkPresentation previews, Handoff/`NSUserActivity`, Spotlight or history; blur the snapshot.
7. Lifecycle: on background, run a background task, then stop tor; on foreground, restart and block Tor-tab navigations until a circuit exists.
8. Bridges: an IPtProxy controller plus `UseBridges` / `ClientTransportPlugin`; include Snowflake and WebTunnel.
9. Orbot: if OrbotKit reports it running, don't start embedded tor (that would be Tor-over-Tor) and say so in the UI.
10. Automated leak matrix on a real device for every iOS release. Log the source IP per request type: fetch, XHR, WebSocket, HLS/`<video>`, WebRTC, WebTransport, dns-prefetch, preconnect, beacon, download, favicon, second and later navigations. Also run https://leaks.psylo.app.

### Risks

- New WebKit leaks with each iOS release; three were found in 2026.
- The unverified "later navigations go direct" report.
- The A/V and WebRTC leaks if Lockdown is off.
- `applyCredential` regressions.
- Tor.framework's CocoaPods sunset.
- The small anonymity set of iOS-WebKit Tor users.
- Bootstrap latency on cellular.
- Regional delisting.
- Export paperwork.

## Couldn't verify

- Arti's memory use.
- Linked (post-dead-strip) binary sizes.
- Bootstrap and battery numbers.
- Whether A/V still bypasses the proxy on iOS 26.
- OCSP/trustd behaviour.
- Whether web content processes are shared between proxied and direct stores.
- Whether blocking the `ping` resource type fully stops dns-prefetch (Onion Browser ships it; I didn't test it).
- The export classification.
