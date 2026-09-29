# Field: ad blocking and anti-redirect research

Researched 2026-09-25; compile numbers measured on an M5 Max with SafariConverterLib 4.3.0.

**Short answer:** Put two precompiled `WKContentRuleList`s on each tab in Field: EasyList, and EasyPrivacy. Add one small native "navigation guard" inside `decidePolicyFor`. It unwraps link shims, strips tracking parameters, blocks app-link and scheme hijacks, and applies HTTPS-first. Leave out scriptlets and the heavier options in v1. I measured compile time, memory and disk size locally; the numbers are in section 1.

## 1. Content blocking

### Limits

- **Rules per list:** at most 150,000. It is hard-coded as `maxRuleCount` in [ContentExtensionParser.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionParser.cpp). An Apple engineer confirmed it in the [forums](https://developer.apple.com/forums/thread/734111), and it was raised from 50k in 2021 ([bug 205719](https://bugs.webkit.org/show_bug.cgi?id=205719)).
- **Number of lists:** there is no documented cap. AdGuard uses 6 lists and wBlock uses 5.
- **Main-actor rule:** call `WKContentRuleListStore` from the main actor. Brave crashed on iOS 26 until it did ([brave-browser#49722](https://github.com/brave/brave-browser/issues/49722), fixed in [brave-core#31483](https://github.com/brave/brave-core/pull/31483)).
- **Caching:** compiled lists persist across launches. `lookUp` is about 0.1 ms, and the compiled files are memory-mapped and shared with the web processes.
- **After an OS update:** `lookUp` silently recompiles from the source stored in the file when the format version changes (currently 21). So the first launch after an update can take seconds ([APIContentRuleListStore.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/APIContentRuleListStore.cpp)).
- **Don't ship compiled stores.** The format is tied to the WebKit version and the files are 20-55 MB each. Ship the JSON instead: gzipped, it is 0.5-0.8 MB per list.

### Measured here

Setup: SafariConverterLib 4.3.0 `ConverterTool`, lists fetched 2026-09-25, a Swift benchmark on an M5 Max running macOS 26.6.

| List | WebKit rules | Compile | Peak RSS* | Disk |
|---|---|---|---|---|
| EasyList | 65,940 (6,299 css) | 1.5 s | 330 MB | 30 MB |
| EasyPrivacy | 56,195 | 1.1 s | 260 MB | 22 MB |
| EasyList + EasyPrivacy merged | 122,134 | 2.5 s | 470 MB | – |
| AdGuard Base (optimized) + Mobile Ads | 40,918 | 1.8 s | 330 MB | 34 MB |
| AdGuard Tracking Protection | 101,577 | 2.6 s | – | 56 MB |
| EasyList Cookie | 9,421 | 0.9 s | – | – |

\*The peak RSS includes about 100 MB of process baseline. Converting text to JSON takes only 0.15-0.25 s.

- **Not measured:** iPhone compile times. I'd estimate close to these on A19-class chips and 2-3x slower on A15-class, but that is unverified.
- **Compile speed depends on regex shape.** AdGuard made compiles 2.8-5.5x faster just by changing the regexes its converter emits ([blog, Sep 2025](https://adguard.com/en/blog/adguard-for-ios-v4-5-12-regex-improvement.html)).

### Reproducing the measurements

The benchmark is [rule-list-bench.swift](rule-list-bench.swift). It compiles each JSON file into a fresh `WKContentRuleListStore`, then prints compile time, lookup time and on-disk size.

1. Download `ConverterTool` from the [SafariConverterLib v4.3.0 release](https://github.com/AdguardTeam/SafariConverterLib/releases). Next to it, create `swift-psl_PublicSuffixList.bundle/` holding `common.bin`, `negated.bin`, `asterisk.bin` and `version.txt` from [ameshkov/swift-psl](https://github.com/ameshkov/swift-psl/tree/HEAD/Sources/PublicSuffixList/Resources). The release binary crashes without that bundle.
2. Convert a list:
   ```sh
   ./ConverterTool convert -s 26.0 -a true --input-path easylist.txt \
     --safari-rules-json-path el.json --advanced-blocking-rules-path el.adv.txt
   ```
3. Build and run the benchmark. On this Mac, SwiftPM is broken, so use `swiftc` with the 26.5 SDK:
   ```sh
   SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
     xcrun swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
     rule-list-bench.swift -o rule-list-bench
   /usr/bin/time -l ./rule-list-bench ./store el.json ep.json
   ```
   The first argument is a scratch store directory, which is deleted and recreated. `time -l` reports peak RSS.

### Converters

- **[AdGuard SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib)** (v4.3.0, 2026-06-04, GPL-3): the best maintained. It supports Safari 26 `if-frame-url` for `domain.*` rules and `$method`.
  - Unsupported: `$redirect`, `$removeparam`, `$csp`, and HTML filtering.
  - Rules it can't express become "advanced rules" for an extension.
  - Gotcha: the release binary needs the `swift-psl` resource bundle next to it.
- **Brave** converts on the device with adblock-rust (`content-blocking` feature). It uses 4 generic lists capped at 150k, versioned in prefs, and cleans up stale identifiers ([ContentBlockerManager.swift](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/Brave/WebFilters/ContentBlocker/ContentBlockerManager.swift)).
- **DuckDuckGo** builds its rules from its Tracker Radar blocklist ([TrackerRadarKit](https://github.com/duckduckgo/TrackerRadarKit)). That list blocks trackers only, not ads. Its data is **CC BY-NC-SA 4.0**, so it's unsuitable for a commercial app.

### Which lists

- **Pick one of:**
  - EasyList + EasyPrivacy: no JavaScript needed. EasyList has no scriptlets; its 466 advanced rules are extended CSS.
  - AdGuard Base (optimized) + Mobile Ads: the optimized version drops rarely-used rules based on usage statistics ([filter policy](https://adguard.com/kb/general/ad-filtering/filter-policy/)). But 5,104 of its advanced rules are scriptlets that you would lose.
- **Avoid for breakage or size:** AdGuard Tracking Protection full (101k rules), social and annoyance lists, host-file lists (they block first-party too), and anti-porn lists (over 150k).

### Updates

- Bundle a snapshot in the app.
- A nightly CI job fetches the lists (they expire every 4 days), converts them, test-compiles on macOS, and publishes gzipped JSON plus a sha256 manifest.
- The app checks with ETag via `BGAppRefreshTask`, compiles under a new identifier, swaps it in, then removes the old one.

### Allowlisting a site

Do what Brave does: per main-frame navigation, add or remove the lists on that tab's `WKUserContentController` ([ContentBlockerHelper.swift](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/Brave/WebFilters/ContentBlocker/ContentBlockerHelper.swift)). It's instant, with no recompile. Compiling an `ignore-previous-rules` exception into the list instead costs seconds per toggle.

## 2. Cosmetic filtering and scriptlets

- **`css-display-none` in the rule list is the cheapest option.** WebKit groups the selectors into precompiled stylesheets. But EasyList puts about 13.6k generic selectors on every page, versus 3.9k for AdGuard optimized. The page-load cost of that isn't measured.
- **A `WKUserScript` at document start** is only needed for extended CSS, `:style`, or scriptlets.
- **Scriptlets are feasible.** Inject AdGuard Scriptlets into `WKContentWorld.page` at document start. The script set must be chosen per site before the page commits; Brave swaps each tab's user scripts inside `decidePolicyFor` ([BVC+TabPolicyDecider.swift](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/Brave/Frontend/Browser/BrowserViewController/BVC+TabPolicyDecider.swift)). Doing this for iframes is racy. Defer it to v2.
- **YouTube is not realistic to promise.** It needs `json-prune`/`set-constant` scriptlets that keep breaking, and server-side ad insertion is rolling out ([AdGuard, updated Aug 2026](https://adguard.com/en/blog/youtube-server-side-ad-insertion.html)).
- **An alternative path exists (untested).** Public `WKWebExtension` (iOS 18.4+) runs declarativeNetRequest, including `redirect`, `queryTransform.removeParams` and `modifyHeaders`, plus MAIN-world content scripts ([_WKWebExtensionDeclarativeNetRequestRule.mm](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/Extensions/Cocoa/_WKWebExtensionDeclarativeNetRequestRule.mm)). In a plain `WKContentRuleList`, `redirect` and `modify-headers` are inert unless you set the private `_activeContentRuleListActionPatterns` ([ContentExtensionsBackend.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/contentextensions/ContentExtensionsBackend.cpp)).

## 3. Anti-redirect and navigation protections

All of these apply to main-frame navigations in `decidePolicyFor(_:preferences:)`. That also covers JS navigations (`location=` arrives as `.other`) and GET form submissions. `pushState` doesn't navigate, so also strip on copy/share.

### Stripping tracking parameters

Use host-indexed sets, not a regex scan.

- [Brave query-filter.json](https://github.com/brave/adblock-lists/blob/master/brave-lists/query-filter.json) (MPL): 65 global parameters plus scoped ones (`igshid`, x.com `ref_src`, YouTube `si`). It deliberately keeps `utm_*`, and only strips cross-site GETs ([wiki](https://github.com/brave/brave-browser/wiki/Query-String-Filter)).
- [DDG tracking-parameters](https://github.com/duckduckgo/privacy-configuration/blob/main/features/tracking-parameters.json) (Apache-2): 25 parameters including `utm_*`, with 5 site exceptions.
- AdGuard URL Tracking filter: 291 global names and 2,248 site-scoped rules.
- [ClearURLs](https://github.com/ClearURLs/Rules): 206 providers, regex-heavy, last rules commit 2026-03-25.
- Apply: cancel, then `webView.load(URLRequest)` with the Referer copied over, as Brave does. On iOS 27, `WKWebpagePreferences.alternateRequest` avoids the second navigation; it is in the 27.0 SDK headers on this Mac.

### Unwrapping link shims

Do this before the request leaves.

- Sources: Brave [debounce.json](https://github.com/brave/adblock-lists/blob/master/brave-lists/debounce.json) (48 rules and 190 patterns, affiliate-heavy, applied only when eTLD+1 changes), uBO privacy `$urlskip` (217 rules), and ClearURLs redirections.
- Specific shims: Google `/url?q=` and `adurl=`, `l.facebook.com/l.php?u=`, `out.reddit.com`, `youtube.com/redirect?q=`.
- `t.co` and `bit.ly` are opaque shorteners and can't be unwrapped locally.

### De-AMP

- Rewrite URLs matching `google.*/amp/s/…` and `cdn.ampproject.org/c/s/…`.
- Add a small document-end script: on pages marked `html[amp]` or `html[⚡]`, read `link[rel=canonical]` and call `location.replace()`. That's Brave's [DeAmpScript.js](https://github.com/brave/brave-core/blob/master/ios/brave-ios/Sources/Brave/Frontend/UserContent/UserScripts/Scripts_Dynamic/Scripts/Sandboxed/DeAmpScript.js).
- Skip DDG's "deep extraction", which loads the page in the background with a 1.5 s timeout.

### Bounce tracking

Intelligent Tracking Prevention is on by default in WKWebView ([WebKit](https://webkit.org/blog/10882/app-bound-domains/)). It handles bounce trackers, including delayed ones ([WebKit](https://webkit.org/blog/11338/cname-cloaking-and-bounce-tracking-defense/)). The debounce table covers the rest. Safari's own link-parameter stripping is private SPI.

### Hijacks, popups and tab-unders

- **No public user-gesture flag.** `_isUserInitiated` is SPI. Use `navigationType == .linkActivated`, `targetFrame == nil` (new window), `sourceFrame`, and `modifierFlags`. `shouldPerformDownload` only reflects the `download` attribute.
- **Universal links:** WebKit tries app links on any cross-host main-frame "Allow". The "allowed" flag carries over from a tapped page to its later JS redirects ([FrameLoader.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebCore/loader/FrameLoader.cpp)). API loads never try app links ([WebPageProxy.cpp](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/WebPageProxy.cpp)).
- **Fix:** for non-`.linkActivated` cross-host GETs, cancel and re-`load()`. The private `_WKNavigationActionPolicyAllowWithoutTryingAppLink` also does it, but it risks App Review.
- **Custom schemes and `itms-apps`:** WKWebView never opens them itself. Only forward them on `.linkActivated`, with a confirm step.
- **Popups:** keep `javaScriptCanOpenWindowsAutomatically = false`, which is the iOS default. In `createWebViewWith`, open anchor `target=_blank` (`.linkActivated`) normally. Show script `window.open` calls (`.other`, I believe; verify on device) as a "popup blocked" chip.
- **Tab-unders:** WebKit already requires user activation for cross-origin iframes to navigate the top frame. Also cancel `.other` cross-site navigations of the opener for about 2 s after a popup opens.

### Cookie banners

- EasyList Cookie as a third list: 9.4k rules, zero JS. It hides banners but doesn't reject, so some pages stay scroll-locked.
- [DDG autoconsent](https://github.com/duckduckgo/autoconsent) (MPL-2, v16.42.0): actually clicks "reject". DDG iOS ships a 90 KB bundle, but it means JS plus messaging on every frame, and more breakage. Make it opt-in later.

### HTTPS

Keep `upgradeKnownHostsToHTTPS` (default YES), and set `preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP` per navigation (iOS 18.2+). No DDG upgrade list is needed. `globalPrivacyControlEnabled` is iOS 27 only.

## 4. Recommended pipeline for Field

1. **CI, nightly:** EasyList and EasyPrivacy go through SafariConverterLib into two JSON lists of about 66k and 56k rules. Optionally add AdGuard Mobile Ads (4.9k rules, 0.34 s). The same job publishes a small navigation-rules JSON: parameter sets, unwrap table, AMP patterns and exceptions. Bundle a snapshot too.
2. **Launch:** look up both lists (about 0.2 ms total, on the main actor). If either is missing, compile serially in the background, never blocking first paint (about 2.6 s on this Mac). Pages load unprotected until that finishes.
3. **Per tab:** attach the lists. Handle WebKit error 104 ("blocked by content blocker") with a "Load anyway" option.
4. **`decidePolicyFor` (main frame):**
   - scheme gate
   - unwrap
   - strip
   - app-link guard
   - HTTPS policy
   - rule-list set chosen by the allowlist

   Each step is O(1) host lookups plus at most one cancel-and-reload.
5. **User scripts:** only the de-AMP script, about 1 KB, main frame only.
6. **UX:** a shield toggle per site (eTLD+1). Turning it off removes the rule lists and skips stripping and unwrapping, then reloads. Also offer long-press "Reload without protection". There is no public per-request callback for a blocked-count badge; that's [bug 152598](https://bugs.webkit.org/show_bug.cgi?id=152598) and SPI.

## Unverified or not measured

- iPhone compile times.
- Runtime cost of the generic cosmetic CSS.
- The exact `navigationType` value for `window.open`.
- Whether iOS 27 has shipped.
- The `WKWebExtension` declarativeNetRequest path.
- YouTube server-side ad insertion rollout details, which come partly from secondary sources.

## Licensing

- EasyList: GPL-3 / CC BY-SA.
- AdGuard filters and uBO lists: GPL-3.
- Brave lists: MPL-2.
- DDG blocklist: non-commercial (CC BY-NC-SA).
