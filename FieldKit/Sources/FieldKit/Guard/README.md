# Navigation guard

`Guard.decide(_:shieldOn:)` turns a navigation into a `Verdict` before it leaves: the scheme gate, link shims unwrapped, tracking parameters stripped, AMP undone and the App Store kept out of reach of scripts (docs/PLAN.md, "Navigation guard"). It is pure and costs a few microseconds. The tables are in `Rules/`; `scripts/guard/update.sh` refreshes the upstream ones.

## Wiring it into the app

Load the rules once, off the main thread (9 ms on an M-series Mac, most of it the public suffix list):

```swift
let rules = await Task.detached { GuardRules.bundled }.value
let navigationGuard = Guard(rules: rules)
```

Until it has loaded, let navigations through. Then, in `webView(_:decidePolicyFor:preferences:decisionHandler:)`:

```swift
let action: WKNavigationAction
let nav = Navigation(
    url: url,
    source: action.sourceFrame.request.url ?? webView.url,
    kind: kind(action),   // .linkActivated → .link, .formSubmitted/.formResubmitted → .formSubmit,
                          // .backForward, .reload, .other; .typed for the app's own loads (below)
    isMainFrame: action.targetFrame?.isMainFrame ?? true,
    opensNewWindow: action.targetFrame == nil,
    userTapped: action.navigationType == .linkActivated
)
if navigationGuard.prefersHTTPS(nav, shieldOn: shield) {
    preferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP
}
switch navigationGuard.decide(nav, shieldOn: shield) {
case .allow: decisionHandler(.allow, preferences)
case .rewrite(let url):
    decisionHandler(.cancel, preferences)
    var request = URLRequest(url: url)
    request.setValue(action.request.value(forHTTPHeaderField: "Referer"), forHTTPHeaderField: "Referer")
    webView.load(request)
case .block: decisionHandler(.cancel, preferences)
case .askToLeave(let url): decisionHandler(.cancel, preferences); confirmThenOpen(url)
}
```

- `shield` is the per-site switch for the page's registrable domain. Off, only the scheme gate applies.
- Pass `.typed` for the app's own loads: from the field, and the `load()` that follows a rewrite (it comes back as `.other` for the URL just loaded). The guard treats them as asked for, like a tap, with no page to compare sites against. Decided that way, every rewritten address is allowed (`aRewriteIsLetThroughTheSecondTime`), so a rewrite can't loop. Passed as `.other` instead, a tapped shim to the App Store would be blocked on its second pass.
- For subframes, pass `isMainFrame: false`: only the scheme gate applies.

## Not done here

- **Universal links on JS redirects.** WebKit tries app links on any cross-host main-frame "allow" and carries a tap's permission into later script redirects (research §3). The plan's fix is to cancel and `load()` non-tapped cross-host navigations. With the app's own loads passed as `.typed` that could be a `.rewrite` to the same address, but it doubles every cross-host redirect (sign-in flows, bounce chains), so it's left for a decision. The guard blocks the App Store and custom schemes from scripts, which covers the common hijack.
- **Popups and tab-unders** stay with the app: `javaScriptCanOpenWindowsAutomatically = false` and the popup chip in `createWebViewWith`. `opensNewWindow` is carried for that and doesn't change a verdict.
- **Brave's `exclude` lists** in the query filter are empty and aren't read. The debounce table's excludes are honoured.
- **Stripping on copy and share**, which `pushState` addresses need, isn't a navigation: the app calls `Guard.stripped(_:)` for it.
