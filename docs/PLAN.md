# Field: plan

Field is an iPhone browser in the spirit of [Search](https://github.com/driceroland/Search) for the Mac: small, fast, quiet, nothing in the way. It has one field, your tabs and the page. Ads and trackers are gone before the page draws, and links arrive clean. Private browsing is a separate place, sealed shut.

Planned 2026-09-25. The research behind every decision is in [`docs/research/`](research/); each file cites its sources and lists what it could not verify.

## Decisions so far

| Decision | Choice |
|---|---|
| Platform | iPhone only, iOS 26.0 minimum, built with Xcode 27 (iOS 27 SDK) |
| Code | This repo. The Mac app ([Search](https://github.com/driceroland/Search)) stays untouched; portable code is copied in with its MIT notice |
| Audience | TestFlight for friends first, App Store later (paid developer account). No private APIs, ever |
| Name | Field ("Field Browser" on the App Store), bundle ID `com.connork.fieldbrowser` (com.connork.field was taken), team Connor Klann (`H435XM227M`) |
| Private mode | A separate space you deliberately enter. All hardening lives there; everyday browsing never feels locked down |
| Tor | Built in (C tor + IPtProxy), shipping in **release 2**, after private mode is solid |
| AI | On-device only: Apple's Foundation Models, with a non-LLM fallback. Nothing leaves the phone |
| Look | Both bottom-bar looks stay: Liquid Glass, or the Mac's solid raised surface. You choose on first launch, and can change it in Settings |
| Smooth | A measured requirement, not a feeling: every milestone meets the budgets in "Smooth" below on the iPhone 17 |

## The shape of the app

**Regular Field** behaves like a normal browser. It remembers tabs, history and sign-ins, and supports picture-in-picture and AirPlay. It has no lock. Its only protections are the invisible ones (blocking, clean links), each with a per-site off switch.

**Private** is a place you go into. It is always dark, shows the Mac's `eye.slash` mark in the bar, and has its own tabs. It keeps nothing on disk, locks with Face ID when you leave, and is covered in the app switcher. It blanks during screen recording and is wiped when you close it. Leaving it returns you to your regular tabs exactly as they were.

### Screens

- **The page, with one bottom pill: `‹  address  ▢3`.** The positions never move. Long-press back for forward and history. Swipe sideways on the pill to change tabs, swipe up for the tab grid. Scrolling down shrinks the pill to the host name. Edge swipes go back and forward; pull down to reload.
- **New tab.** The field is focused with the keyboard up. Starred pages sit just above the keyboard, and as you type the suggestions take their place. Empty until you type, as on the Mac.
- **Tab grid.** Two columns of cards; swipe a card away to close it. Groups show as sections. A **Tidy** button appears once there are 8 or more tabs.
- **Saved.** One list with optional folders. Starred pages form the new-tab grid. "Read later" is a filter: saved pages you haven't opened since.
- **Welcome.** One screen on first launch: the bar shown over a page in both looks, side by side. Tap one to choose; it takes effect straight away. Nothing else is asked.
- **Settings.** The bar look, search engine, blocking, private-mode options, and later Tor.

### Taste, carried over from the Mac

The design tokens come from Search's `Sources/Search/Design.swift`; [`research/mac-app-map.md`](research/mac-app-map.md) lists them all.

- **Colour.** No accent colour. Selection is ink at 12%, pressed is ink at 5%. The Mac's grey levels (ground, ink, muted, faint, hairline, wash, raised) become `UIColor(dynamicProvider:)`.
- **Motion.** Exactly three curves: `glide` spring(0.34, 0.82), `settle` spring(0.30, 0.86), `quick` easeOut 0.14.
- **Shape.** Continuous corners of 16/14/11/9. A refused input shakes with a red rim, never an alert.
- **No white flash.** The web view stays hidden until the page's first paint, and a sleeping tab shows a picture of itself while it wakes.
- **Voice.** Short declarative copy, one-sentence toasts that vanish after 1.7 s, and load errors shown in place of the page.
- **Type.** The Mac's ramp plus about 2–3 pt, scaled with Dynamic Type up to a cap.
- **Haptics.** Rare: a selection tick when a tab snaps into place, a light tap on close.

### Smooth

Smoothness is checked on the iPhone 17 (120 Hz) in a Release build, with Instruments and XCTest's performance metrics, not by eye. Every milestone's "done" includes these:

- **No hitches.**
  - What counts: frames that miss their deadline in the core interactions. So far those are scrolling a page while the bar shrinks, opening the field and typing, and the welcome choice. M2 adds swiping between tabs and opening the tab grid.
  - Budget: under 2 ms of hitch time per second of interaction. Apple calls under 5 good.
- **Launch.** A cold launch shows its first frame within 400 ms. The field accepts typing within 30 ms of a bare `UITextField`'s own time (the `BaselineTests` control), because on the iPhone 17 even a bare field needs about 520 ms, most of it iOS loading its keyboard. The first web view is built after the first frame, never before it.
- **Input.**
  - A tap shows its response on the next frame.
  - Typing drops no frames.
  - A keystroke's average latency is within 1 ms of the bare-field control, and the slowest within 5 ms. On the iPhone 17 a bare field averages 9.2 ms, over one 120 Hz frame, because of iOS's own keyboard work, so a fixed 8.3 ms budget can't be met.
  - Ranking 2,000 history entries takes under 2 ms, guarded by a FieldKit test.

  Measured 2026-09-27 on the iPhone 17. Bare field: 520 ms to ready, 9.2 ms average and 10.2 slowest per keystroke. Field: 538 ms, 9.3 ms and 13.8 ms.
- **Motion.**
  - Only the three curves.
  - Every animation can be interrupted, and gestures track the finger 1:1, then hand their velocity to the spring.
  - Nothing waits for an animation to finish before accepting the next touch.
  - With Reduce Motion on, the springs become the 0.14 s fade.
- **Main thread.** No disk reads or writes, no JSON work and no web view creation during an animation. Signposts mark every core interaction so Instruments can show exactly where time goes.

## Architecture

- **Project.** XcodeGen `project.yml` (the generated `.xcodeproj` isn't committed) and Swift 6 with main-actor default isolation.
- **Two modules:**
  - **`FieldKit`**, a local Swift package with no UIKit and no WebKit where possible. It holds the logic and is tested fast with `swift test` on the Mac:
    - address parsing and search engines (ported from `Address.swift`, `Engine.swift`);
    - history ranking (`History.swift`);
    - session format (`Session.swift`);
    - the Saved model;
    - registrable domains, with a bundled Public Suffix List instead of the Mac's private CFNetwork call;
    - the **navigation guard**, a pure function from a navigation to a decision;
    - Tidy's clustering and validation.
  - **`Field`**, the app. It has a SwiftUI shell and wraps `WKWebView` in one `UIViewRepresentable` that swaps tab web views in and out, so SwiftUI never rebuilds them. A `UITextField` wrapper serves as the field. Not SwiftUI's `WebPage`: it can't do popups, downloads, pull-to-refresh or `interactionState`, and iOS 27 didn't fix that.
- **Web views.** One shared regular `WKWebsiteDataStore`, one shared set of compiled rule lists and `WKWebView.obscuredContentInsets` for the floating bar. Page scripts run in their own content world, as on the Mac, so sites can't detect them.
- **Tabs.**
  - The current tab and 2–3 recent ones stay live; the rest sleep as `interactionState` plus a snapshot.
  - On a memory warning, more of them sleep.
  - If a tab's web process dies, the tab reloads (it is recreated after 3 failures).
- **Storage.** JSON files in Application Support, as on the Mac (`history.json`, `session.json`, `saved.json`). Writes are debounced and happen off the main thread, flushed when the app goes to the background.
- **Blocking.**
  - Lists: EasyList + EasyPrivacy (via AdGuard's SafariConverterLib) plus HaGeZi Multi PRO and native-tracker domain lists, about 288k rules in five lists; 100% on adblock.turtlecute.org with no breakage on 18 major sites. SafariConverterLib is GPL-3, but it runs at build time and never ships in the app.
  - Compilation: the gzipped JSON ships in the app and compiles once in the background on first launch (about 2.5 s on a fast chip, not on the first-paint path). After that, `lookUp` loads it in about 0.2 ms.
  - Per-site off switch: add or remove the lists on that tab's content controller, as the Mac's `Shield.swift` does. It's kept by registrable domain (UserDefaults `shield.off`), and the navigation guard reads the same switch. When the lists stop a page itself, it offers "Load anyway", which loads that one navigation without them.
  - The one main-thread cost is WebKit parsing a new list before it compiles (43–61 ms per list on the simulator), only on the first launch after the lists change. Each parse waits for a lull (`Lull`): the app in front, no keyboard, the run loop idle. `-FieldBlockingProbe YES` logs the times.
  - v1 lists refresh with each build, not over the network.
- **Navigation guard** (main frame, in `decidePolicyFor`), in order:
  1. scheme gate
  2. unwrap link shims (Google `/url`, `l.facebook.com`, `out.reddit.com`, YouTube redirect, Brave's debounce table)
  3. strip tracking parameters (host-indexed sets from Brave's query filter and DuckDuckGo's list)
  4. de-AMP
  5. app-link and App Store hijack guard (cross-host navigations the user didn't tap get cancelled and reloaded)
  6. HTTPS-first
  7. the per-site shield

  Script popups become a small "Popup blocked" chip. Every step is a hash lookup plus at most one cancel-and-reload.
- **Private space.** One non-persistent data store per private session (sign-ins work across its tabs) and an ephemeral `URLSession` for its favicons. Its tab list and thumbnails live only in memory. Wiping it tears down the web views, removes all website data, drops the store and purges temporary files, inside a background task.
  - The cover goes up on the scene's own deactivate and background notifications, on the posting thread, so it's in place before UIKit takes the switcher's snapshot (`PrivateGateTests`).
  - Known gaps: a page can still open a `WebTransport` from a dedicated worker, since user scripts don't run in workers. WebKit's own Copy and Share use the general pasteboard, which Field can't mark local-only; the limits screen says so.
- **Capture.** "Capture Page" on the address's long press makes a PDF of what's already loaded (`WKWebView.pdf()`, no network), or an image drawn from it, at most 16,384 px on the long side. The system screenshot also offers Full Page, except in Private. Images a page lazy-loads that were never scrolled into view stay as placeholders.
- **Tidy.**
  - Engine: `SystemLanguageModel` when it's available and supports the language. Otherwise `NLEmbedding` clustering plus same-site heuristics.
  - Results: a preview sheet (rename, move, uncheck), then Apply with Undo. Tabs the model refuses fall back one by one.
  - Private tabs are never included.
  - Without the model, the rules compare the nouns of each title, with the site's name cut, as averaged word vectors (`TidyVectors`). On two sets of realistic tabs, 88% and 77% of the pairs they grouped were right, against 19% and 45% for whole-title sentence vectors. The same-site pass uses the registrable domain, so Gmail and Google Flights both group as "Google".
  - Foundation Models doesn't run in the iOS 27 simulator, so there only the rules are seen. `-FieldTidyHarness YES` runs the flow over a stand-in grid.
  - A tab untouched for 7, 14 (the default) or 30 days is stale (Settings › Tabs untouched for). The grid offers to review or close stale tabs, and never closes one without a tap.

## Milestones

Each milestone ends in something you can use on your iPhone. "Done" means that criterion is met on a real device, not just the simulator.

### M0 · Foundations (done 2026-09-26)
Repo, `project.yml`, `FieldKit` with address parsing, engines and history ported and tested, and the design tokens as a light and dark sample sheet.
**Done when** `swift test` and `xcodebuild test` pass and the app installs on your iPhone.

### M1 · One good tab
- The page and the bottom pill, in both looks.
- Welcome: first launch asks for the bar look (see "The shape of the app"); Settings can change it.
- The field: address or search, with inline completion from history that backspace removes.
- No white flash, errors in place, pull to reload, edge swipes, the pill shrinking on scroll, toasts.

**Done when** you'd happily use one tab all day, and the M1 interactions meet the "Smooth" budgets on your iPhone, as measured by the `FieldPerf` scheme.

Also in M1 (from the M0 review):
- History saves run through one serial actor, so an older snapshot never lands last.
- The app refuses to save history until a load succeeds.

### M2 · Tabs
- The tab grid, swiping the pill between tabs, and the new-tab page.
- Sleeping tabs, session restore, recovery from a crashed page, Recently Closed.

**Done when** 30 tabs come back after a force-quit, and nothing is lost when memory runs low.

### M3 · Blocking and clean links
- The list build script and background compilation.
- The per-site shield and the navigation guard with tables.
- The popup chip, and "Load anyway" when the blocker stops a page.

**Done when** the guard's test tables pass and a checklist of real pages behaves: a news site with ads, a Google result link, a Facebook outbound link, an AMP link, a page that tries to throw you into the App Store. First launch must not paint any slower.

### M4 · Saved
- Save and star from the pill's long-press or the share menu, with a suggested folder.
- The Saved list with folders and "Read later", starred pages on the new tab.
- Saving a tab group as a folder, and opening a folder as tabs.

**Done when** saving is one gesture and finding a saved page takes a few taps.

### M5 · Private
- The separate dark space and the Face ID lock (immediate by default), the cover in the app switcher, blanking during recording.
- Wipe on close, plus an optional auto-wipe after N minutes away.
- Nothing ever reaches Spotlight, Handoff, Siri or widgets.
- A script turning off autocorrect in page fields, a local-only clipboard for our copy actions, no WebRTC, no PiP or AirPlay.
- A confirm step before saving to Photos, and before any link opens another app.
- The honest-limits screen (below).

**Done when** after closing private mode nothing from it can be found on the phone (checked against a list of places), and the app switcher never shows a private page.

### M6 · Tidy
- The Tidy button, the preview sheet and Undo, on both engines.
- A deterministic "12 tabs untouched for 2 weeks" review banner.

**Done when** Tidy gives groups you'd keep on an Apple Intelligence iPhone and something sensible on one without it, in a few seconds.

### Release 1 · TestFlight
- App icon (an asset catalog with `ASSETCATALOG_COMPILER_APPICON_NAME`).
- NOTICE.md and its MIT attribution shown in the app (Settings › About), since TestFlight distributes copies.
- Privacy label: "Data Not Collected".
- Export compliance: Apple's encryption only, so exempt.
- App Store Connect record, and beta review for external testers.

### M7 · Tor (release 2)
- A `TorEngine` protocol with a C-tor implementation (Tor.framework's xcframework as a SwiftPM binary target, not CocoaPods) and IPtProxy bridges (obfs4, Snowflake, WebTunnel).
- One store per Tor tab: SOCKS5 `proxyConfigurations` with its own credentials (its own circuits), set before the web view exists. Navigations are refused unless tor is up and the proxy is set.
- Lockdown Mode on by default.
- Blocked: DNS prefetch, WebAuthn and WebTransport.
- All app networking for Tor tabs goes through the same proxy, and fails closed.
- Tor stops when Field goes to the background and restarts on return.
- "New circuit" and "New identity".
- If Orbot is running, Field doesn't start its own Tor client.

**Done when** a leak matrix on a real iPhone shows no direct traffic for any request type. The matrix covers fetch, XHR, WebSocket, media, WebRTC, WebTransport, prefetch, beacon, downloads, favicons, and second and later navigations. It is re-run on every iOS release, and export compliance is re-answered.

### Later, not planned
Reader mode, the Mac's hide-anything picker (it needs a touch redesign), password saving (check iOS AutoFill in `WKWebView` first), cookie-banner handling, scriptlets, over-the-air list updates, iPad.

## Testing

- **FieldKit logic is test-first with Swift Testing**: address parsing, the guard's unwrap, strip and AMP tables, history ranking, the Saved model, Tidy's validation of model output (invented or duplicate tab ids get dropped).
- **UI tests cover only the critical flows**: open an address, switch tabs, enter private mode then leave and check it's wiped.
- **Device checks can't be automated.** Each milestone's "done" line is a checklist for them, and Tor adds its leak matrix.

## What Field tells people it can't do

Put plainly in private mode and Tor:

- **Screenshots:** iOS has no way for an app to stop them, or a photo of the screen.
- **Keyboard:** iOS may still learn words typed into websites.
- **IP address:** without Tor, private mode doesn't hide it from networks or websites.
- **Tor isn't Tor Browser:** sites can tell it's an iPhone using Tor. If you're at real risk, use Tor Browser on a computer, or Tails.
- **Anything you save, copy or share leaves private mode.**

## Still to check on a device

These are unverified in the research; each one belongs to the milestone that needs it:

- iPhone rule-list compile times (M3).
- A public first-paint signal to replace the Mac's private API (M1).
- Whether the iOS 27 toolbar minimise works with a web view's scrolling (M1).
- The `navigationType` WebKit reports for `window.open` (M3).
- Whether autocorrect off stops keyboard learning (M5).
- The on-device model's context size, 4k or 8k (M6).
- Every Tor leak (M7).

## Status

M0 to M6 and the Release 1 work are built; Tor (M7) isn't started. The milestones above are kept as the plan they were built from. To build and test Field, see the README; [`perf.md`](perf.md) and [`motion.md`](motion.md) are how a change is checked, and CONTRIBUTING.md is how to send one.
