# Field for iPhone: UX, stack and build setup

Researched 2026-09-25

**Decision already made:** the bottom bar will be built in both looks, a Liquid Glass pill and the Mac app's solid raised surface, behind a switch. The final choice gets made on a real device. Section 3 covers when glass fits and what it costs.

**Bottom line:** build a SwiftUI app shell with `WKWebView` wrapped in `UIViewRepresentable`. That is the same pattern the Mac app uses (`WebStage: NSViewRepresentable` in `Search/Sources/Search/Stage.swift`). SwiftUI's `WebPage` is missing popups, downloads and pull-to-refresh, and those gaps still exist in iOS 27.

---

## 1. Tech stack

**Performance is the same whichever you pick.** In WebKit's source, `WebPage` is a thin wrapper over a private `WKWebView` subclass (`backingWebView: WebPageWebView`), which apps cannot reach (it is behind `@_spi(CrossImportOverlay)`). Scrolling and rendering come from the same engine either way, so the choice comes down to which APIs you can reach.
https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Swift/WebPage.swift

**What WebPage covers** (iOS 26, with some additions in iOS 27):

- **Navigation policy:** `NavigationDeciding` gives `decidePolicy(for:preferences:)`, the response policy and auth challenges. iOS 27 adds `willSubmit(formInfo:)`.
- **Configuration:** `Configuration.websiteDataStore` is a real `WKWebsiteDataStore`, so `proxyConfigurations` and `init(forIdentifier:)` work. `userContentController` is a real `WKUserContentController`, so content rule lists and user scripts work. `urlSchemeHandlers` is also there.
- **Snapshots:** `exported(as: .image(region:…snapshotWidth:…))` produces thumbnails.
- **Process crashes:** these arrive as `NavigationError.webContentProcessTerminated`.
- **View modifiers:** `webViewBackForwardNavigationGestures`, `webViewOnScrollGeometryChange`, `webViewContextMenu`, `findNavigator`.

Sources:
- https://developer.apple.com/documentation/webkit/webpage
- https://developer.apple.com/documentation/webkit/webpage/configuration
- https://developer.apple.com/videos/play/wwdc2025/231/

**Gaps in WebPage (all verified):**

- **No `createWebViewWith`.** WebKit's `WKUIDelegateAdapter` only implements alert, confirm, prompt, file picker and sensor/media permission. So `target=_blank` links and `window.open` (including OAuth popups that need `window.opener`) fail. There's also no `javaScriptCanOpenWindowsAutomatically`. An Apple DTS engineer's advice is to wrap `WKWebView` instead.
  - https://developer.apple.com/forums/thread/803351
  - https://troz.net/post/2025/swiftui-webview/
- **No download handling.** There is no `navigationAction:didBecomeDownload` hook in the adapter.
- **`.refreshable` doesn't work on WebView.** An Apple engineer confirmed this (FB19105514).
  - https://developer.apple.com/forums/thread/789361
- **No `interactionState`**, so session restore is limited.
- **No `scrollView` access.** That rules out `refreshControl`, `contentInset`, `keyboardDismissMode` and a scroll delegate for fine control of toolbar collapse.
- **iOS 27 didn't close these.** It added `willSubmit`, `alternateRequest`, `overrideReferrer` and GPC to WebPage, but nothing for new windows.
  - https://webkit.org/blog/18325/webkit-features-for-safari-27-0/

**UIKit shell vs SwiftUI shell:** Firefox iOS and DuckDuckGo both use UIKit with `WKWebView`. I confirmed they use `interactionState`, `takeSnapshot` and `webViewWebContentProcessDidTerminate`. For an app this small, a SwiftUI shell is fine. Use one representable container that swaps tab web views in and out, so SwiftUI never recreates them. Drop to a `UITextField` representable for the address field, as the Mac app does with `AddressField`.

---

## 2. Interaction patterns worth copying

**History:**

- iOS 15's floating bottom bar drew heavy backlash, and in beta 6 Apple made it optional.
  - https://techcrunch.com/2021/08/18/apple-walks-back-controversial-safari-changes-with-ios-15-beta-6-update/
- iOS 26 made **Compact** the default layout: back button, URL field and a ••• menu. Share, bookmarks and the tab button moved into the menu, and the bar shrinks to a URL pill on scroll. Swiping on the URL bar to switch tabs and flicking up for the tab overview survived. Top, Bottom and Compact are still options in iOS 27.
  - https://sixcolors.com/post/2025/09/ios-26-review-through-a-glass-liquidly/
  - https://www.macrumors.com/guide/ios-26-safari-features/

**Reception:** NN/g criticised the iOS 26 design:

- Tabs are hidden behind a menu.
- The forward button appears and disappears ("changing the size and location of a target makes the interface harder to learn").
- The URL is hard to read and targets are cramped.

Six Colors: "I still struggle to remember whether the control I want is accessed via the location bar or the More button."
- https://www.nngroup.com/articles/liquid-glass/

**What people loved in Arc Search:**

- Every control sits on the bottom edge.
- Swiping left or right on the bar cycles through tabs.
- The tab switcher looks like the app switcher, with swipe-up to close.
- Flicking up toggles to the previous tab.
- Old tabs are archived automatically.
- Favourites sit right above the keyboard, and autocomplete can be scrolled.
- The bar collapses when you scroll.

Sources:
- https://www.macstories.net/reviews/arc-search-for-iphone/
- https://arc.net/blog/arc-search-hidden-features

**Recommended set:**

- **One bottom pill:** back, field, tabs. Keep the tab button visible and keep positions fixed. Long-press back for forward and history, so no button pops in and out.
- **Gestures:** swipe sideways on the pill to switch tabs, swipe up on it for the tab grid, and use edge swipe for back/forward (`allowsBackForwardNavigationGestures`).
- **Scrolling:** collapse to a host-only pill when scrolling down; expand on scroll up or tap.
- **New tab:** the field is already focused with the keyboard up, and suggestions plus favourites sit directly above the keyboard (`keyboardLayoutGuide`, iOS 15+).
- **Tab grid:** two-column cards with swipe-to-close.
- **Pull-to-refresh:** a `UIRefreshControl` on `webView.scrollView`.
- **Haptics:** sparse. Selection feedback on tab snap, a light impact on close (`sensoryFeedback`, iOS 17).

---

## 3. Liquid Glass

**SwiftUI APIs (iOS 26):**

- `glassEffect(_:in:)` with `Glass.regular`, `.clear` or `.identity`, plus `.tint()` and `.interactive()`.
- `GlassEffectContainer(spacing:)` with `glassEffectID` and `glassEffectUnion` for morphing.
- `.buttonStyle(.glass)` and `.buttonStyle(.glassProminent)`.
- `ToolbarSpacer` and `sharedBackgroundVisibility`.
- `safeAreaBar(edge:)` for custom bars.
- `scrollEdgeEffectStyle(.hard/.soft)`.
- `tabBarMinimizeBehavior(.onScrollDown)`, which applies to `TabView` only.

iOS 27 adds `toolbarMinimizeBehavior(.onScrollDown, for:)`. Whether it follows a `WKWebView`'s scrolling is **unverified**.

Sources:
- https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- https://developer.apple.com/videos/play/wwdc2025/323/
- https://developer.apple.com/videos/play/wwdc2026/269/

**UIKit APIs (iOS 26):**

- `UIGlassEffect` (`isInteractive`, `tintColor`) in a `UIVisualEffectView`.
- `UIGlassContainerEffect`.
- `UIButton.Configuration.glass()`.
- `UIScrollView.topEdgeEffect` and `bottomEdgeEffect`.
- `UIScrollEdgeElementContainerInteraction`, which lets your custom bar shape the scroll edge effect.
- **`WKWebView.obscuredContentInsets`** (iOS 26), which tells WebKit what area the floating chrome covers. This one is essential for a bottom bar, and it applies to both the glass and solid looks.

**When to use glass vs solid.** Apple's guidance: "best reserved for the navigation layer that floats above the content", and "always avoid glass on glass". Use `.clear` only over media, with a dimming layer.
- https://developer.apple.com/videos/play/wwdc2025/219/

For this browser:

- **Glass look:** the pill and the tab button, using regular glass inside one container.
- **Solid look:** the Mac app's raised surface, used for the same pill.
- **Always solid:** the page, the new-tab page, tab-grid cards and the suggestion list.

**Performance.** Apple: "Creating too many Liquid Glass effect containers and applying too many effects to views outside of containers can degrade performance." Glass can't sample other glass, so keep the chrome in one container. Battery figures in blog posts are **unverified**.

**Accessibility.**

- These adjustments apply automatically to the system material, including custom `glassEffect`: Reduce Transparency makes it frostier, Increase Contrast makes it black or white with a border, and Reduce Motion removes the elastic behaviour.
- iOS 26.1 added a Clear/Tinted switch. iOS 27 replaced it with a slider under Settings › Appearance.
  - https://www.macrumors.com/how-to/ios-27-tone-down-liquid-glass-transparency/
- Whether the slider affects third-party glass is **unverified**.
- Still check `accessibilityReduceTransparency` for any blur or gradient you draw yourself.

---

## 4. Performance on iPhone

**Process model.** Each web view renders in a WebContent process outside the app. `WKProcessPool` is deprecated as of iOS 15 ("Creating and using multiple instances of WKProcessPool no longer has any effect", from WebKit's `WKProcessPool.h`). Share one data store (or one per space via `forIdentifier`), one `WKUserContentController` and the compiled rule lists across tabs. Whether Site Isolation ships on iOS is **unverified**.

**Process termination.** Under memory pressure iOS kills the WebContent process, which leaves a blank view.

- Handle `webViewWebContentProcessDidTerminate`: if the tab is visible, reload it (Firefox retries up to 3 times in a row); if not, mark it to reload when selected.
- Sometimes only recreating the web view fixes it.
  - https://nevermeant.dev/handling-blank-wkwebviews/

**Discarding tabs.** Firefox iOS has "zombie" tabs: no `WKWebView` exists until the tab is selected, and it is then created from saved `interactionState`. Keep the current tab plus about 2–3 recent ones live (that number is my suggestion, not measured). On a memory warning, save each other tab's `interactionState` and a snapshot, then release it.

**Restoring sessions.**

- `interactionState` (iOS 15+) is an opaque value. Firefox and DuckDuckGo write it to disk per tab (DuckDuckGo's `TabInteractionStateDiskSource`).
- iOS 26 adds `WKWebsiteDataStore.fetchData(of:)` and `restoreData` for local and session storage.
  - https://webkit.org/blog/17333/webkit-features-in-safari-26-0/

**Cold start.**

- One third-party measurement found the first `WKWebView` blocked the main thread for 280–450 ms (iPhone 11, iOS 15.5).
  - https://github.com/exponea/exponea-ios-sdk/issues/112
- Draw the chrome and focused field first, then restore only the selected tab.
- DuckDuckGo warms up by loading `about:blank` in a hidden web view: "WKWebsiteDataStore is basically non-functional until a web view has been instanciated and a page is successfully loaded" (`DataStoreWarmup.swift`).
- Compile rule lists once and use `lookUpContentRuleList` on later launches.

**Thumbnails for the tab grid.**

- `takeSnapshot` with `WKSnapshotConfiguration.snapshotWidth` set to the card width, so it renders at that scale.
- Set `afterScreenUpdates = false` for an immediate capture.
- Take the snapshot when leaving a tab and cache it.
- For the zoom animation, use `snapshotView(afterScreenUpdates:false)` (standard UIKit, not checked in this research).

---

## 5. Project and build setup

**On this Mac (ready):**

- **Xcode 27.0 (27A266a)** is installed with the iPhoneOS 27.0 SDK. The licence is accepted and `xcodebuild` works.
- **The iOS 27.0 simulator runtime** (`24A434`) is installed. Available simulators include iPhone 17, iPhone 17e, iPhone Air, iPhone 18 Pro and iPhone 18 Pro Max.
- **`xcodegen` 2.46.0** is installed via Homebrew.

**Xcode versions.** Xcode 27 includes the iOS 27 SDK and Swift 6.4, needs macOS Tahoe 26.6 or later (this Mac runs 26.6), and runs on Apple silicon only.
- https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes

The iOS 26 SDK needs Xcode 26. Since 28 April 2026, App Store uploads must be built with Xcode 26 or later.
- https://developer.apple.com/news/upcoming-requirements/

**Command Line Tools alone cannot build an iOS app.** Apple's page says the CLT package holds only "the same macOS SDK…", and "Commands such as `xcodebuild` and `xctrace` only ship with Xcode."
- https://developer.apple.com/documentation/xcode/installing-the-command-line-tools

Also only in `Xcode.app`:

- the iPhoneOS and iPhoneSimulator SDKs and platforms
- `simctl` and `devicectl`
- `actool` (asset catalogs and icons)
- provisioning integration

SwiftPM can't produce an iOS `.app` either.

**Project format.** Use **XcodeGen**: a `project.yml` with `type: syncedFolder` (Xcode 16 buildable folders), then run `xcodegen generate`. Put code shared with the Mac app (rule lists, omnibox parsing) in a local Swift package that both targets use. Tuist is overkill for one app. A hand-kept `.xcodeproj` works, but changing settings then means clicking through Xcode.

**Free Apple ID vs paid program.** Free accounts get a Personal Team: profiles expire after 7 days, up to 3 devices, 3 apps per device, 10 App IDs per 7 days, and no TestFlight or App Store.
- https://developer.apple.com/support/compare-memberships/

The iPhone also needs Developer Mode turned on. `-allowProvisioningUpdates` "requires a developer account to have been added in Xcode's Accounts preference pane", so there is one GUI step: sign in once. App Store Connect API keys (`-authenticationKeyPath`) need the paid program.

**CLI commands:**

```sh
xcodegen generate
xcodebuild -scheme Field -destination 'platform=iOS Simulator,name=iPhone 17' build test
xcrun simctl boot|install|launch …

# On a device
xcodebuild -scheme Field -destination 'platform=iOS,id=<udid>' \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build
xcrun devicectl device install app --device <udid> <path/to/Field.app>
```

The `devicectl` syntax and simulator names were checked locally against Xcode 27.0.

---

## Couldn't verify

- Whether `toolbarMinimizeBehavior` or `safeAreaBar` work with a web view's scrolling.
- Whether the iOS 27 glass slider affects third-party apps.
- Liquid Glass battery and GPU cost figures.
- Site Isolation status on iOS.
- Cold-start timings on current hardware.
- The 2–3 live-tab limit is a suggestion, not a measurement.
