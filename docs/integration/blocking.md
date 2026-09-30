# Wiring content blocking into the app

Everything here is in `Field/Blocking/`. The frozen files need the lines below and nothing else. They were applied to a scratch copy of the tree at `1853196` plus this folder, which builds in Release, and that copy is what the numbers at the end were measured with.

## The API

| Call | When |
|---|---|
| `ContentBlocking.shared.prepare()` | Once, after the first frame. It looks the lists up, then compiles any that are missing or out of date in a lull. |
| `ContentBlocking.shared.site = rules.site(of:)` | Once the guard's `GuardRules` have loaded off the main thread. Until then, a small stand-in keys the shield. |
| `apply(to: controller, host:)` | Every main-frame navigation that's allowed, in `decidePolicyFor`. |
| `isShieldOn(for: host)` / `setShield(_:for:)` | The per-site switch, kept by registrable domain in UserDefaults `shield.off`. |
| `shieldAction(for: url, reload:)` | The switch as a menu item, or nil for a page with no site. |
| `ContentBlocking.blockedURL(from: error)` | Non-nil when WebKit's error 104 means the lists stopped the page itself. |
| `loadAnyway(url, in: web)` | Loads that one page without the lists. |
| `ready` | Every list is on every page whose shield is on. |

Pages load unprotected until the lists are ready. Each list goes onto the open pages the moment it's compiled, so what they load from then on is blocked without a reload.

## 1. Launch: `Field/FieldApp.swift`

Add `import FieldKit` at the top. In `firstFrame()`, put this **before** the `browser.start()` line. The blocker watches the keyboard, and it has to exist before the field focuses so that it sees the keyboard come up:

```swift
DispatchQueue.main.async {
    Signpost.log.emitEvent(Signpost.firstFrame)
    if !Baseline.isOn {
        ContentBlocking.shared.prepare()
        Task.detached(priority: .utility) {
            let rules = GuardRules.bundled
            await MainActor.run { ContentBlocking.shared.site = rules.site(of:) }
        }
    }
    if welcomed, !Baseline.isOn { browser.start() }
}
```

If the guard's wiring already loads `GuardRules` somewhere, drop the `Task.detached` and set `ContentBlocking.shared.site = rules.site(of:)` where the rules land on the main actor. `prepare()` does only a few microseconds of work before it returns. The lookUps and anything else it does are asynchronous.

## 2. The tab: `Field/Browser/Tab.swift`

Stored properties, beside `failure` and `watching`:

```swift
/// The address the blocker stopped, when that's why `failure` is set.
private(set) var blocked: URL?
```
```swift
/// The web view's, kept: `web.configuration` makes a copy on every call.
@ObservationIgnored private var content: WKUserContentController?
```

In `build()`, just before `let web = WKWebView(frame: .zero, configuration: config)`:

```swift
content = config.userContentController
```

In `sleep()`, after `self.web = nil`:

```swift
content = nil
```

`retry()` becomes the following. `reload()` also loses its `private`, because the shield menu item calls it. On a failed page it retries, and on any other page it reloads:

```swift
func retry() {
    if let blocked, let web {
        failure = nil
        self.blocked = nil
        ContentBlocking.shared.loadAnyway(blocked, in: web)
        return
    }
    guard let target = failed ?? url else { return }
    load(target)
}

func reload() {
    if failure != nil { retry() } else { web?.reload() }
}
```

In `fail(_:)`, straight after `settled()`:

```swift
if let stopped = ContentBlocking.blockedURL(from: error) {
    failed = stopped
    url = stopped
    blocked = stopped
    failure = "Field's blocker stopped this page."
    return
}
```

In `webView(_:didCommit:)`, beside `failed = nil`:

```swift
blocked = nil
```

In `webView(_:decidePolicyFor:decisionHandler:)`, in the `.allow` case, before `decisionHandler(.allow)`:

```swift
case .allow:
    if action.targetFrame?.isMainFrame == true, let content {
        ContentBlocking.shared.apply(to: content, host: action.request.url?.host())
    }
    decisionHandler(.allow)
```

**Together with the navigation guard** (FieldKit `Guard/README.md`), the rules are as follows:
- Call `apply` only on the path that ends in `.allow` for a main frame. When the guard answers `.rewrite`, don't call it; the `load()` of the new address comes back through `decidePolicyFor` and gets applied there.
- Pass `shieldOn: ContentBlocking.shared.isShieldOn(for: url.host())` to the guard. The guard and the lists then share one per-site switch.
- Take the host from the URL being navigated to, not from `webView.url`.

`.sameTab` needs nothing, because its `webView.load` comes back through `.allow`. Subframes need nothing either: a rule list on the controller covers every frame of the page.

## 3. "Load anyway": `Field/Browser/Trouble.swift` and `BrowserView.swift`

In `Trouble.swift`, the button's title becomes a property:

```swift
let message: String
var action = "Try again"
let retry: () -> Void
```
```swift
Button(action, action: retry)
```

In `BrowserView.swift`:

```swift
Trouble(message: failure, action: browser.tab.blocked == nil ? "Try again" : "Load anyway", retry: browser.tab.retry)
```

## 4. The per-site switch: `Field/Bar/FieldSurface.swift`

The address gets a long-press menu. In the block that sets up `bar.goBack`, `bar.canReopen` and so on, after `bar.canReopen = …`:

```swift
bar.address.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
    guard let tab = self?.browser.tab else { return done([]) }
    done([ContentBlocking.shared.shieldAction(for: tab.url, reload: tab.reload)].compactMap { $0 })
}])
```

The item reads "Turn Off Blocking on example.com", or "Turn On Blocking on example.com". It flips the switch for the whole site and reloads, and the reload applies the change through `decidePolicyFor`. On a page the blocker stopped, turning blocking off loads that page.

M4 hangs Save and Star on the same long-press, so both go in this one deferred menu. A `UIButton` menu opens on a long press and leaves the tap alone. However, the address's `.touchDown` action (`press(true)` and `prepare()`) still fires at the start of the long press, and `.touchCancel` undoes it. **This hasn't been checked on a device**: look at the press state and the field's warm-up before shipping it.

## Things to know

- **The lists:** EasyList, EasyPrivacy, and three domain lists (`domains-1…3`) made from HaGeZi Multi PRO and its native-tracker lists by `scripts/lists/domains.py`. About 288k rules in all, each list at most 60k. The domain lists never block a page itself (a typed address or a link to one still opens), and a tracker's own site (a registrable domain) is blocked only as a third party.
- **The one main-thread cost is WebKit parsing a list** before it compiles off the main thread: 43–61 ms per list on the iPhone 17e simulator. It happens only when a list is new: the first launch, and the first launch after a build that changed the lists (they change with each list refresh). Each parse waits for a lull (`Lull`): the app in front, no keyboard, and a default-mode run-loop timer firing on time, for 2 s before the first list and 0.5 s before each after it. That rules out a finger on a scroll view, coasting and busy stretches. 10 s after the first wait began, 0.5 s will do for any list, and the keyboard may be up if the app's own fields haven't been typed in and the keyboard hasn't moved for 2 s (typing into a page can't be seen). A tap that lands in one of those windows is delayed once.
- **Compile times** on the iPhone 17e simulator: EasyList 1.5 s, EasyPrivacy 1.1 s, each domain list 0.65–0.76 s. The peak footprint stays at EasyList's 274 MB; the lists are compiled one at a time. All five are ready about 11 s after a first launch left alone. The compiled lists take about 107 MB on disk.
- **After an iOS update**, WebKit's `lookUp` recompiles a list whose compiled format changed, from the source it keeps in the file. That wasn't measured, and where WebKit parses in that case is unverified.
- **Redirects after "Load anyway":** only the first navigation goes without the lists. A server redirect asks `decidePolicyFor` again, and the lists go back on for the redirect's target.
- **Measuring:** launch with `-FieldBlockingProbe YES`. It prints the lookUp and compile times, the longest main-thread gap during each, the time `apply` takes, and the memory footprint, to stdout and to the log under `com.connork.field` / `blocking`. Launch arguments are the only way to turn it on.
- **Refreshing the lists:** `scripts/lists/build.sh` (it needs `uv` and `jq`), then rebuild. Field's own rules are in `scripts/lists/`: `protected.txt` (shared sites never blocked whole), `allowlist.txt` (exceptions for sites the lists broke, added to every list) and `extra.txt`. Each list's identifier contains the sha256 of its JSON, so a changed list compiles again and the old one is removed on the next launch.
