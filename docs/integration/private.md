# Wiring Private into the browser (M5)

Private's own files are done and tested on their own, in `Field/Private/` and FieldKit's `Private/`. This file lists what to add to the frozen files, and where. Anchors are functions and lines as they stood on 2026-09-30; wire3 may have moved them since.

## What's there

| File | What it is |
|---|---|
| FieldKit `Private/PrivateLock.swift` | `PrivateLock`, the lock as a pure state machine (events in; `shade`, `.wipe` and `.authenticate` out), and `PrivateWipe.order` |
| `PrivateSpace.swift` | The session: `open() -> Tabs`, `dataStore` (one `nonPersistent()` per session), `configure(_:)` and `built(_:offer:announce:)` for its web views, `session` (ephemeral) and `fetch(_:)`, `holding`, `wipe()`. `PrivateFiles` purges tmp |
| `PrivateWeb.swift` | `harden(_:store:)`: PiP and AirPlay off, GPC (iOS 27), the no-WebRTC script (page world, all frames), the quiet-fields script, the pressed-image note. `menu(from:save:)` filters WebKit's long-press menu. `PrivateUIDelegate` puts that menu in front of a tab. `leaving(to:)` |
| `PrivateGate.swift` | The lock, cover and capture blank in the running app. It listens to the scene itself and needs no scene delegate. `FaceID` |
| `PrivateShade.swift` | The pre-built window that is the cover, the lock screen and the capture blank |
| `Hygiene.swift` | `PrivatePasteboard` (local only, 2-minute expiry, forgotten on wipe) and `Hygiene` (no `NSUserActivity` for private pages, generic notification text) |
| `PrivateLimits.swift` | The honest-limits sheet (`PrivateLimits`, `.present()`), and `PrivateWelcome`, a new private tab's page |
| `PrivateLook.swift` | `PrivateMark`, `PrivateSwitch` (the grid row's way in), `PrivateStrip` (the slide between the two tab sets) and `PrivateSide` (the private stage with the welcome over it) |
| `PrivateSettings.swift` | The two settings' keys, and `PrivateSettingsSection` for Settings |

## 1. Tabs know their space: `Field/Browser/Tab.swift` and `Tabs.swift`

A private tab needs Private's store before its web view exists, and Private's delegate after. One weak reference covers both; everyday tabs have none and behave as they do now.

```swift
// Tab.swift, beside `var visible`
/// Private's, for a private tab; nil for an everyday one.
@ObservationIgnored weak var space: PrivateSpace?

// Tab.build(), after the PaintRelay `addUserScript(…)`, before `content = …`
space?.configure(config)

// Tab.build(), straight after `self.web = web`
space?.built(web, offer: { [weak self] in self?.offer($0, $1) }, announce: { [weak self] in self?.announce($0) })

// Tab.askToLeave(for:), the offer's text
offer(space == nil ? Tab.leaving(to: url) : PrivateWeb.leaving(to: url), Toaster.Offer(title: "Open") { … })
```

```swift
// Tabs.swift, beside `weak var stage`
/// Private's, when these are its tabs: every tab made here gets it.
@ObservationIgnored weak var space: PrivateSpace? {
    didSet { all.forEach { $0.space = space } }
}

// Tabs.wire(_:), first line
tab.space = space
```

Then in `Field/Private/PrivateSpace.swift`, `open()`, uncomment `tabs.space = self`.

A private tab's visits go to a `HistoryStore` under `/dev/null` that `open()` makes, which never reads or writes. `finished` is left unwired for private tabs, so Saved's "Read later" never hears of them.

## 2. Browser holds Private: `Field/Browser/Browser.swift`

`tabs` becomes the set on screen, so every `browser.tabs` and `browser.tab` in the bar, the omnibox and BrowserView follows the switch without further changes.

```swift
// properties: `let tabs: Tabs` becomes
let everyday: Tabs
let privateSpace = PrivateSpace()
@ObservationIgnored private(set) lazy var gate = makeGate()
/// Private's tabs are on screen.
private(set) var privately = false
/// On screen: Private's tabs, or your everyday ones.
var tabs: Tabs { privately ? privateSpace.tabs ?? everyday : everyday }

// init: `tabs = restoring ? …` becomes `everyday = restoring ? …`, and the
// five hook lines under it say `everyday.` instead of `tabs.`.
// Browser.start(): `tabs.started = true` becomes `everyday.started = true`.
// flush(): `await tabs.flush()` becomes `await everyday.flush()`. Private has nothing to flush.

// MARK: - Private

/// From the grid's switch. The strip slides at once (StageView); the
/// session's tabs are made now if it's a new one.
func enterPrivate() {
    let fresh = privateSpace.tabs == nil
    let tabs = privateSpace.open()
    if fresh { wirePrivate(tabs) }
    tabs.chrome = everyday.chrome
    privately = true
    gate.entered()
    // A new session opens on its blank tab with the field, rising with the slide.
    if fresh { openField() }
}

func leavePrivate() {
    closeField()
    privately = false
    gate.left()
}

/// The hooks everyday tabs have, less Saved's `finished`.
private func wirePrivate(_ tabs: Tabs) {
    tabs.announce = { [toaster] in toaster.show($0) }
    tabs.offer = { [toaster] in toaster.show($0, offering: $1) }
    tabs.committed = { [bar] in bar.expand() }
    tabs.openField = { [weak self] in self?.openField() }
}

private func makeGate() -> PrivateGate {
    let gate = PrivateGate(space: privateSpace)
    gate.leave = { [weak self] in self?.leavePrivate() }
    // Wiped while inside (wipe-instead, or the clock): a new session, empty.
    gate.wiped = { [weak self] in
        guard let self, self.privately else { return }
        self.wirePrivate(self.privateSpace.open())
        self.privateSpace.tabs?.chrome = self.everyday.chrome
        self.openField()
    }
    return gate
}
```

`reopenClosedTab`, `newTab`, `switchTab`, `showTabs` and `hideTabs` need no change, since they go through `tabs`.

## 3. Two stages in a strip: `Field/Browser/Stage.swift` (StageView) and `BrowserView.swift`

StageView hosts both stages in a `PrivateStrip`, with Private to the right. Everything else in Stage stays as it is. Each set of tabs has its own Stage, grid and carousel, as now.

```swift
struct StageView: UIViewRepresentable {
    let browser: Browser          // in place of `tabs` and `bar`
    var openSaved: () -> Void = {}
    let openSettings: () -> Void

    final class Coordinator {
        var everyday: Stage?
        var side: PrivateSide?
        var privateStage: Stage? { side?.stage as? Stage }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PrivateStrip {
        let stage = makeStage(for: browser.everyday)
        context.coordinator.everyday = stage
        let strip = PrivateStrip(everyday: stage)
        // The switch's lift and the grid row's tone ride the same spring.
        strip.alongside = { [weak coordinator = context.coordinator] p in
            coordinator?.everyday?.privateProgress(p)
            coordinator?.privateStage?.privateProgress(p)
        }
        return strip
    }

    func updateUIView(_ strip: PrivateStrip, context: Context) {
        let c = context.coordinator
        _ = browser.tabs.current.web
        if let tabs = browser.privateSpace.tabs, c.privateStage.map({ $0.tabs !== tabs }) ?? true {
            let side = PrivateSide(stage: makeStage(for: tabs))
            c.side = side
            strip.hold(side)
        } else if browser.privateSpace.tabs == nil, !browser.privately {
            strip.release()
            c.side = nil
        }
        c.side?.welcomeShown = browser.privately && browser.tab.url == nil && !browser.tabs.gridShown
        let inside = browser.privately
        if (strip.progress > 0.5) != inside { strip.slide(toPrivate: inside) }
        c.everyday?.sync()
        c.privateStage?.sync()
    }

    private func makeStage(for tabs: Tabs) -> Stage {
        let stage = Stage(tabs: tabs, bar: browser.bar, scroller: Scroller(bar: browser.bar))
        stage.openSettings = openSettings
        stage.openSaved = openSaved
        stage.enterPrivate = { [browser] in browser.enterPrivate() }
        stage.leavePrivate = { [browser] in browser.leavePrivate() }
        tabs.stage = stage
        return stage
    }
}
```

In `Stage`, `private let tabs` becomes `let tabs`, and it gains the two hooks and passes the progress to its grid:

```swift
var enterPrivate: () -> Void = {}
var leavePrivate: () -> Void = {}

/// 0 on your tabs, 1 in Private: the grid's switch follows it.
func privateProgress(_ p: CGFloat) { grid?.privateProgress(p) }

// makeGrid(), with the other hooks
grid.onPrivate = { [weak self] entering in entering ? self?.enterPrivate() : self?.leavePrivate() }
```

In `BrowserView`, `StageView(tabs: browser.tabs, bar: browser.bar, …)` becomes `StageView(browser: browser, …)`.

Private is always dark, but only what belongs to it. The app's own `preferredColorScheme` stays as it is, or the everyday grid would turn dark on the first frame of the slide. `PrivateStrip.hold` already makes the private side dark. Two more changes do the rest:

```swift
// BrowserView: on `Trouble(…)` and on `Toast(…)`
.environment(\.colorScheme, browser.privately ? .dark : colorScheme)   // @Environment(\.colorScheme) private var colorScheme

// FieldSurfaceHost.updateUIViewController: the bar and the field
controller.view.overrideUserInterfaceStyle = browser.privately ? .dark : .unspecified
```

## 4. The way in: `Field/Tabs/TabGrid.swift` and `GridRow.swift`

`PrivateSwitch` takes the count's place in the middle of the row. Its `count` is the count's number, and it is the count, so it goes in `count`'s frame (`GridRow.count`).

```swift
// TabGrid: `private let count = UILabel()` becomes
private let count = PrivateSwitch()
var onPrivate: (Bool) -> Void = { _ in }

// init: the four `count.` lines become
count.addAction(UIAction { [weak self] _ in
    guard let self else { return }
    self.onPrivate(self.count.wantsPrivate)
}, for: .primaryActionTriggered)
row.addSubview(count)

// layoutSubviews(): `count.text = …` becomes
count.count = tabs.all.count

/// The strip's progress, inside its animation: the lift moves with it.
func privateProgress(_ p: CGFloat) {
    count.progress = p
    count.layoutIfNeeded()
}
```

A sideways pan on the grid's row moves the strip 1:1, as the pill does for pages. Make it a `UIPanGestureRecognizer` on `row` that calls `strip.track(translation.x)` and `strip.release(velocity:)`, reached through a `trackPrivate: (CGFloat) -> Void` and `releasePrivate: (CGFloat) -> Void` pair, wired the same way as `onPrivate`. It must not start on the card area, where the swipe closes a card.

## 5. The bar: `Field/Bar/Bar.swift` (BarContent)

The Mac's mark goes before the host, quiet:

```swift
// BarContent, beside `var tabCount`
var privately = false { didSet { if privately != oldValue { say(shown) } } }

// say(_:), where the label's text is set
if privately {
    let mark = NSTextAttachment(image: PrivateMark.image(pointSize: label.font.pointSize * 0.8, weight: .medium)!
        .withTintColor(Palette.UI.muted, renderingMode: .alwaysOriginal))
    let line = NSMutableAttributedString(attachment: mark)
    line.append(NSAttributedString(string: "  " + text))
    label.attributedText = line
} else {
    label.text = text
}
```

`shown` is the last URL `say` was given; keep it in a property. FieldSurface sets `bar.privately = browser.privately` wherever it calls `bar.show(url:…)`.

The long-press Copy (FieldSurface, `UIAction(title: "Copy" …)`) becomes:

```swift
{ _ in browser.privately ? PrivatePasteboard.copy(url) : Guarded.copy(url) }
```

## 6. Scene hooks and capture: nothing to add

`PrivateGate` listens for `UIScene.willDeactivateNotification`, `didEnterBackgroundNotification` and `didActivateNotification` with no queue, so it runs on the posting thread before the post returns. The shade window is therefore up before `sceneWillResignActive` and `sceneDidEnterBackground` return, which is before UIKit's snapshot. `PrivateGateTests.coveredBeforeTheSnapshot` checks this.

The gate also registers for `UITraitSceneCaptureState` on the window scene, the first time Private is entered. FieldApp's `.onChange(of: phase)` stays as it is.

## 7. Settings: `Field/Settings/SettingsView.swift`

```swift
// after section("Search engine")
section("Private") { PrivateSettingsSection() }
```

## 8. `project.yml`

```yaml
INFOPLIST_KEY_NSFaceIDUsageDescription: "Only to unlock Private, so nobody else can open it."
```

It goes under the Field target's `settings.base`, beside the camera and microphone strings. Without it, `.deviceOwnerAuthentication` can't use Face ID. `FaceID.canLock()` then depends on the passcode alone, and a phone with neither wipes on leaving.

## 9. Tests to add once wired

Add these to `FieldTests/PrivateSpaceTests.swift`. They go through the real Tab, which only gets Private's store once step 1 is in:

```swift
@Test func aPrivateTabUsesTheSpacesStore() async throws {
    let server = try await Self.server()
    defer { server.stop() }
    let space = PrivateSpace(temporary: temporary)
    let tab = space.open().current
    tab.load(server.url.appending(path: "set").appending(queryItems: [.init(name: "tab", value: nil)]))
    tab.build()
    let web = try #require(tab.web)
    #expect(web.configuration.websiteDataStore === space.dataStore)
    #expect(web.uiDelegate is PrivateUIDelegate)
    #expect(!web.configuration.allowsPictureInPictureMediaPlayback)
}
```

Also add a UI test for the critical flow (PLAN, Testing): enter Private from the grid, open a loopback page, leave, then check the container for the page's token. It reuses `PrivateSpaceTests.containerFiles(containing:)`.

## Motion: entering and leaving (proposal, per docs/motion.md)

Private is to the right of your tabs, a place you move to, the same way the pages under the bar sit side by side.

- **Entering, from the grid.** Tap the switch, or drag the row to the left. On the next frame both grids start moving on one glide, and the switch's lift slides to the mark on the same spring. The everyday grid goes left while the dark one comes in from the right edge, so the grid seems to turn dark from that edge, with no crossfade and no second step. Dragging follows the finger 1:1 and lets go with its speed. A tap mid-slide turns it around from where it is.
- **A new session** has no grid to show. It comes in as its blank page: the dark ground, with `PrivateWelcome` in the top half. Its field opens from the bar on the frame the slide starts, as the grid's + does, so the keyboard rises while the page slides in.
- **A session with tabs** comes in as its grid, as it was left.
- **Locked.** The strip slides in the same way, and the lock screen (the shade window) is up over it from the first frame. After Face ID it fades in 0.14 s, so the grid underneath is already in place.
- **Leaving** is the same motion, reversed. If the lock screen is up, "Your tabs" runs it.
- **Reduce Motion.** `Stage.glide` becomes the 0.14 s ease, as everywhere.

Check it with the video loop in docs/motion.md. There is no frame with two grids at rest, and the lift and the grids move together.

## Known gaps

- **Workers.** A page can still make a `WebTransport` in a dedicated worker, since user scripts don't run in workers (`PrivateWebTests` prints this on every run). WebRTC isn't available in workers, so the address leak through STUN is closed.
- **Add to Photos** saves the image the finger last came down on in the main frame. The image comes from `touchstart` in Field's world and is fetched with the private store's cookies. An image inside a frame says "Couldn't save that picture."
- **WebKit's own Copy and Share** are left alone. Copy uses the general pasteboard, which Field can't mark local-only. Both are on the limits screen.
- **The shade's window level** (10,000,010) is meant to sit over the keyboard's window, so the switcher never shows QuickType's suggestions. Check it on video with the keyboard up.
