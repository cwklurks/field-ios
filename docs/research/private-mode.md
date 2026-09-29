# Private mode on WKWebView for Field

Researched 2026-09-25

> **Scope note:** In Field, private mode is a separate space the user deliberately enters. Everything below applies only inside that space. Regular browsing must not feel locked down: no Face ID gate, capture blanking, keyboard restrictions, cover window or network hardening outside private mode.

**Summary:** Use `WKWebsiteDataStore.nonPersistent()`, not `forIdentifier:`. You can detect screen recording and mirroring and blank the screen when it happens. No public API can block screenshots. No public API can stop the keyboard learning what's typed into web pages.

Sources are Apple developer docs, WebKit source, and the source code of Brave, DuckDuckGo, Onion Browser and Telegram, as of September 2026.

## 1. Storage isolation

- **`nonPersistent()` (iOS 9).** Apple says it "stores data only in memory, and doesn't write that data to disk" ([doc](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/nonpersistent())). The WebKit source agrees:
  - Private sessions use an ephemeral `NSURLSessionConfiguration`. HSTS is stored on disk only for persistent sessions, no blob directory is created, and `URLCache` is nil ([NetworkSessionCocoa.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/NetworkProcess/cocoa/NetworkSessionCocoa.mm)).
  - The storage manager gets an empty path, so IndexedDB, localStorage, the Cache API and service workers all live in memory ([NetworkStorageManager.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/NetworkProcess/storage/NetworkStorageManager.cpp)).
  - The AVFoundation media cache is turned off ([HTMLMediaElement.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/html/HTMLMediaElement.cpp)).
- **Extra protections you only get with non-persistent stores:**
  - Screen Time usage recording is off (`setSuppressUsageRecording:!isPersistent`, [WKWebView.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm)).
  - Now Playing metadata is blanked ([MediaElementSession.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/html/MediaElementSession.cpp)).
  - Always-on logging and web push are off.
- **`WKWebsiteDataStore(forIdentifier:)` (iOS 17)** is a persistent profile stored on disk.
  - `remove(forIdentifier:)` needs every web view released first and can throw ([doc](https://developer.apple.com/documentation/webkit/wkwebsitedatastore/remove(foridentifier:completionhandler:)), [WebKit blog](https://webkit.org/blog/14423/building-profiles-with-new-webkit-api/)).
  - DuckDuckGo's Fire Mode uses it. It has to keep a "pending removal" list so it can retry the delete after a crash ([WebsiteDataFireWorker.swift](https://github.com/duckduckgo/apple-browsers/blob/main/iOS/DuckDuckGo/Fire/FireWorkers/WebsiteDataFireWorker.swift)). It also ships a Screen Time cleaner for iOS 26 (`WKWebsiteDataTypeScreenTime`), because persistent stores get recorded ([ScreenTimeDataCleaner.swift](https://github.com/duckduckgo/apple-browsers/blob/main/SharedPackages/ScreenTimeDataCleaner/Sources/ScreenTimeDataCleaner/ScreenTimeDataCleaner.swift)).
  - It's the wrong tool for incognito.
- **Brave's approach:** one shared non-persistent store for all private tabs, cleared with `removeData` and set to nil when private mode closes ([TabManager.swift](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/Brave/Frontend/Browser/TabManager.swift)).
- **Process pools:** `WKProcessPool` has been deprecated since iOS 15 and "no longer has any effect" ([doc](https://developer.apple.com/documentation/webkit/wkprocesspool)). WebKit never shares a web content process between two data stores anyway.
- **Things that still reach disk, which our code has to handle:**
  - Our own tab list, history, `interactionState` and thumbnails. Keep them in memory only.
  - Anything fetched with `URLSession.shared` (favicons, search suggestions) goes into the on-disk `URLCache`. Use `.ephemeral` instead; Firefox fixed the same leak.
  - When a page asks for a file upload, WebKit copies the picked file into our tmp folder (`WKWebFileUpload`, `WKVideoUpload`; [WKFileUploadPanel.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ios/forms/WKFileUploadPanel.mm)).
  - Downloads.
  - The app switcher snapshot (section 2).
- **Wiping, in order:** remove the web views, then `await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)`, then drop the store, clear the private tab model, and delete the tmp files. Run it inside `beginBackgroundTask`. If iOS kills the app, the in-memory data dies with it. Freed memory isn't zeroed, so forensics on a live, unlocked phone is out of scope.

## 2. Preventing visual capture

- **Screenshots: no public API.** Apple support staff (Jan 2025) pointed only to `userDidTakeScreenshotNotification`, which fires after the screenshot is taken ([thread](https://developer.apple.com/forums/thread/771826)).
  - **Secure text field trick:** host the content inside the secure layer of a `UITextField` with `isSecureTextEntry` on. Telegram ships this for secret chats, using key-value coding on the private `TextLayoutCanvasView` ([UIKitUtils.m](https://github.com/TelegramMessenger/Telegram-iOS/blob/master/submodules/UIKitRuntimeUtils/Source/UIKitRuntimeUtils/UIKitUtils.m)).
  - It's fragile: it broke in the iOS 17 betas ([thread](https://developer.apple.com/forums/thread/736112)) and relies on private class names, which is an App Review risk.
  - **Not verified:** whether it works on iOS 26/27, or with WKWebView's remotely hosted layers. If we use it at all, put it behind a kill switch.
- **Recording, mirroring, AirPlay:** watch `UITraitCollection.sceneCaptureState` (iOS 17) and blank the web view while it's `.active`.
  - `UIScreen.isCaptured` is deprecated in iOS 27.0 ([doc](https://developer.apple.com/documentation/uikit/uiscreen/iscaptured)).
  - Brave does this for its wallet views ([NoCaptureViewModifier](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/BraveUI/SwiftUI/NoCaptureViewModifier.swift)).
  - It detects capture; it doesn't prevent it. Audio is still recorded.
  - A developer reported (iOS 26.2) that the state reads inactive while a Live Activity is expanded ([thread](https://developer.apple.com/forums/thread/817446)).
- **App switcher:** Apple says "After your app enters the background and your delegate method returns, UIKit takes a snapshot" ([doc](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background)).
  - That snapshot is saved in `Library/SplashBoard/Snapshots` ([OWASP](https://mas.owasp.org/MASTG/tests/ios/MASVS-PLATFORM/MASTG-TEST-0059/)).
  - Show a pre-built cover window in `sceneDidEnterBackground`. Brave ([WindowProtection](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/Brave/Frontend/Passcode/WindowProtection.swift)) and DuckDuckGo ([OverlayWindowManager](https://github.com/duckduckgo/apple-browsers/blob/main/iOS/DuckDuckGo/Application/UICoordination/OverlayWindowManager.swift)) both do this.
  - In private mode, also cover in `sceneWillResignActive` so the live switcher card is hidden. Our own Face ID prompt and Control Center also trigger resign-active, so guard against re-lock loops.
  - `ignoreSnapshotOnNextApplicationLaunch()` only changes the image shown at relaunch ([doc](https://developer.apple.com/documentation/uikit/uiapplication/ignoresnapshotonnextapplicationlaunch())). Skip it.
- **Picture in Picture and AirPlay:** turn off `allowsPictureInPictureMediaPlayback` and `allowsAirPlayForMediaPlayback` in the private configuration.

## 3. Locking

- **API:** `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` (iOS 9; Face ID with passcode fallback) or `LARight` (iOS 16). Needs `NSFaceIDUsageDescription`. Create a new context for each unlock.
- **Safari's model** (Locked Private Browsing, iOS 17): locks when Safari leaves the foreground or the device locks, unless nothing is loaded or media is playing ([Apple](https://support.apple.com/en-us/105028)).
- **Who ships it:** Brave (`privateBrowsingLock`), Chrome iOS ("Lock Incognito tabs"), DuckDuckGo (whole-app lock). Firefox iOS only had it as a feature request (mid-2025).
- **Timeout:** keep the time we went to the background in memory only. Lock immediately by default.
- The lock only gates the UI; the data is still in memory. Offer "wipe instead of lock". Users can also lock our whole app with iOS 18's app lock ([Apple](https://support.apple.com/guide/iphone/lock-or-hide-an-app-iph00f208d05/ios)).

## 4. OS-level leakage

- **Spotlight, Handoff, Siri:** WKWebView creates none of these; only our own code can. For private tabs, never create an `NSUserActivity`, CoreSpotlight item, intent donation, widget entry or scene-restoration activity. Brave checks `!tab.isPrivate` before creating one ([UserActivityTabHelper](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/Brave/Helpers/UserActivityTabHelper.swift)).
- **Keyboard learning: no public API.**
  - `UITextInputTraits` has no learning switch.
  - WebKit only turns off `learnsCorrections` for password fields ([WKContentViewInteraction.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/ios/WKContentViewInteraction.mm)).
  - Firefox iOS had a user report of private words entering the dictionary ([#6121](https://github.com/mozilla-mobile/firefox-ios/issues/6121)).
  - Mitigations:
    - URL bar: set `autocorrectionType`, `spellCheckingType` and `inlinePredictionType` to off.
    - Web pages: inject a user script that adds `autocorrect="off" spellcheck="false"` to fields. WebKit maps this to autocorrection off.
    - Third-party keyboards: return false for `.keyboard` in `application(_:shouldAllowExtensionPointIdentifier:)`. This applies to the whole app, not just private mode ([doc](https://developer.apple.com/documentation/uikit/uiapplicationdelegate/application(_:shouldallowextensionpointidentifier:))).
  - **Not verified:** whether turning autocorrect off stops the dictionary learning.
- **Clipboard:** copies go to the general pasteboard, which syncs to the user's other devices. For our own copy actions, use `setItems(_:options:)` with `.localOnly` and `.expirationDate` ([doc](https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/localonly)). Brave declined to do this ([#146](https://github.com/brave/brave-ios/issues/146)).
- **Photos, downloads, share sheet:**
  - WebKit's image menu offers saving to Photos. Override `contextMenuConfigurationFor` to confirm first.
  - Save private downloads to tmp with `FileProtectionType.complete` ("cannot be read… while the device is locked", [doc](https://developer.apple.com/documentation/foundation/fileprotectiontype/complete)) and delete them on wipe.
  - `isExcludedFromBackup` is only for caches and support files ([doc](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup)).
  - Apps that receive a share keep their own history.
- **Other apps:** links that open another app (universal links, custom schemes) hand the URL to that app's history. Ask before leaving private mode.
- **Notifications:** use generic text in private mode.

## 5. Network-level leaks

- **WebRTC:** no public switch. The only option is a document-start user script in all frames that deletes `RTCPeerConnection` and `WebTransport`. Fresh iframes can get around it, so test it. Onion Browser dropped its WebRTC blocking in the release that relied on Orbot's VPN ([changelog](https://github.com/OnionBrowser/OnionBrowser/blob/3.X/CHANGELOG.md)).
- **DNS:**
  - `NWParameters.PrivacyContext.requireEncryptedNameResolution` (iOS 14; [WWDC20](https://developer.apple.com/videos/play/wwdc2020/10047)) covers our own process only. A developer saw WKWebView still sending plain DNS; Apple support staff (Jan 2026) confirmed it networks out of process and said to file a bug ([thread](https://developer.apple.com/forums/thread/812679)).
  - Real options:
    - `NEDNSSettingsManager` (system-wide; the user has to enable it in Settings).
    - `WKWebsiteDataStore.proxyConfigurations` (iOS 17; Onion Browser uses it).
  - Mysk (Aug 2026) showed that the proxy is bypassed by DNS prefetch (iOS 26.0), WebAuthn related-origin requests (iOS 18) and WebTransport (iOS 26.4) ([blog](https://mysk.blog/2026/08/04/webkit-proxy-icloud-private-relay-ip-leak/)).
- **iCloud Private Relay:** covers Safari, DNS queries and insecure HTTP from apps ([Apple](https://developer.apple.com/support/prepare-your-network-for-icloud-private-relay/)). Our WKWebView HTTPS page loads are not relayed (inferred from that page).
- **Fingerprinting:**
  - Apple's Advanced Fingerprinting Protection is private API (`_networkConnectionIntegrityPolicy`), so we can't use it.
  - Brave iOS adds noise with user scripts ([FarblingProtectionHelper](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/Brave/Frontend/Browser/UserScripts/FarblingProtectionHelper.swift)).
  - Keep the default Safari User-Agent and don't append app tokens.
- **Newer WebKit settings worth using:**
  - iOS 27: `globalPrivacyControlEnabled` ([doc](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/globalprivacycontrolenabled)) and `overrideReferrer`.
  - iOS 18.2: `preferredHTTPSNavigationPolicy` (HTTPS upgrade).
  - iOS 26.4: `securityRestrictionMode = .maximizeCompatibility` (no JIT, so slower).
- **Tracking parameters:** strip them ourselves in `decidePolicyFor`.

## 6. Recommended design, in order of value for effort

All of this is scoped to private mode only.

1. Use a non-persistent store per private session (or per tab for stricter isolation). Never persist private tabs, use an ephemeral `URLSession`, keep thumbnails in memory.
2. Show a pre-built cover window on background and on resign-active.
3. Wipe on exit (removeData, drop the store, purge tmp and downloads) inside a background task. Optionally auto-wipe after N minutes in the background.
4. Face ID lock, immediate by default.
5. No activities, Spotlight, Siri, widgets or restoration for private tabs; generic notifications.
6. Watch `sceneCaptureState` and blank the page during recording or mirroring.
7. Private configuration: PiP and AirPlay off, confirm before saving to Photos, protected tmp downloads, local-only pasteboard, autocorrect-off script. Rejecting third-party keyboards is app-wide, so it conflicts with regular browsing staying unrestricted; leave it off or make it an explicit user setting.
8. Network: GPC, HTTPS upgrade, a script disabling WebRTC, WebTransport and DNS prefetch, tracking-parameter stripping.
9. Optional: the secure-layer screenshot block (behind a remote kill switch) and fingerprint noise.

**What we must tell users we can't guarantee:**

- Blocking screenshots, or photos of the screen taken with another device.
- That the iOS keyboard won't learn words typed into websites.
- Hiding the IP or traffic from the network, DNS resolver or websites. It isn't a VPN, and fingerprinting still works.
- Anything the user saves, copies or shares; it leaves private mode.
- Recording detection is best-effort.
- Protection against someone who knows the passcode, or an unlocked phone that's been forensically imaged.

## Not verified

- Whether the secure-layer trick works on iOS 26/27 and with WKWebView.
- Whether turning autocorrect off stops keyboard learning.
- Whether WebRTC or STUN traffic bypasses `proxyConfigurations`.
- Whether iOS offers "save password" prompts inside third-party WKWebViews.
- How many frames get recorded before `sceneCaptureState` flips.
- Whether app switcher snapshots end up in backups.
