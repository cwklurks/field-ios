# Search for Mac: a map for the Field iPhone port

Researched 2026-09-25 from a local checkout of [Search](https://github.com/driceroland/Search) (upstream 87328ea plus local, uncommitted changes)

The biggest reuse is the data and policy layer: Address, Engine, History, Session, Shield, Curtain, Reader, Vault and the bookmarks model are mostly Foundation/WebKit and can be shared. Nearly all UI and Browser.swift need rewriting.

**Uncommitted changes:** the checkout read had staged, uncommitted changes on perf/apple-silicon that weren't upstream. The Spotlight-style omnibox and `Palette.raised` come only from those changes (Design.swift:25,40; Omnibox.swift:54-233). Upstream had a glow ("Breath") under a plain field instead.

## 1. Design language

### Colours (Design.swift:13-59)

Every grey is a single white level, light / dark. Hex values are approximate, because `NSColor(white:)` is a grey colour space; convert to sRGB on iOS.

| Token | Light / dark | Approx. hex | Line |
|---|---|---|---|
| ground | 1.0 / 0.11 | #FFF / #1C1C1C | :30 |
| ink | 0.09 / 0.93 | #171717 / #EDEDED | :31 |
| muted | 0.55 / 0.58 | #8C8C8C / #949494 | :32 |
| faint | 0.83 / 0.32 | #D4D4D4 / #525252 | :33 |
| hairline | 0.91 / 0.20 | #E8E8E8 / #333 | :34 |
| wash (the live tab) | 0.937 / 0.175 | #EFEFEF / #2D2D2D | :35 |
| hover | 0.965 / 0.15 | #F6F6F6 / #262626 | :36 |
| raised (the address panel) | 1.0 / 0.16 | #FFF / #292929 | :40 |
| safe | green-700 / green-400 | #14803D / #4ADE80 | :43 |
| unsafe | amber-700 / amber-400 | #B5540A / #FABF24 | :44 |

There is no accent colour anywhere:
- Selected text is ink at 12% (Omnibox.swift:298-301, 345-348).
- Switches are ink, not blue (Settings.swift:599-616).
- The main button is an ink capsule with ground-coloured text (Settings.swift:639-642).
- Red appears only as `.red.opacity(0.75)` on "Remove" (Recall.swift:179) and a red rim at 35% when the field refuses input (Omnibox.swift:125).

### Typography

System font only, fixed sizes, no Dynamic Type.

- 34 medium: welcome title (Welcome.swift:67)
- 17 semibold: panel titles (Plate.swift:36)
- 15.5: address field (Omnibox.swift:254)
- 14: page error text (Stage.swift:194)
- 13: rows (Plate.swift:119, Omnibox.swift:157)
- 12.5: tab titles (TabBar.swift:473)
- 12: toasts (App.swift:552)
- 11.5: captions, pills, details (Plate.swift:123,143; Settings.swift:638)
- 9: tab status icons (TabBar.swift:468)

Weights are almost all regular; medium for captions, semibold only for titles. On iPhone, scale the whole ramp up by about 2-4pt and keep the ratios.

Reader mode uses 18px/1.72 `ui-serif`, h1 600 30px sans, max-width 38em, padding 72/24/160. It forces a white background and has no dark style (Reader.swift:74-94).

### Spacing and sizes

- Rows: 14 horizontal / 9 vertical (Recall.swift:187-188); `Line` rows 14/11 (Plate.swift:132-133).
- Panels: 22 horizontal, 18 top, 14 bottom (Plate.swift:41-43).
- Omnibox field: 18/14 padding around 22pt of text, 50pt tall (Omnibox.swift:15, 66-67); suggestion rows 12/8 inside 6 padding (Omnibox.swift:141, 185-186).
- `Metrics` (Design.swift:108-145): tab strip 52, tab 186 wide (80 below which it drops the title, 36 minimum), gap 2, pinned square 30, field max 560, sidebar 232 (176-440). Sidebar row height 28 (Side.swift:611).

### Corner radii (all `.continuous`)

- 16 panels (Plate.swift:59)
- 14 omnibox (Omnibox.swift:16)
- 11 cards (Plate.swift:87)
- 10 search-in-list field (Plate.swift:181)
- 9 tabs and rows (TabBar.swift:396,550; Omnibox.swift:194)
- 7 segmented-control chip (Settings.swift:580)
- icons: size x 0.22 (Icons.swift:283)
- capsules for pills and toasts

### Shadows and materials

No blur materials, on purpose (Omnibox.swift:89-96). In light mode a shadow lifts things; in dark mode the surface is one step lighter instead. This conflicts with iOS defaults, so keep it.

- Omnibox: 0.05 r1 y1 plus 0.10 r30 y14, with an ink 8% rim (Omnibox.swift:118-126)
- Panels: 0.16 r34 y12 plus a hairline (Plate.swift:61-65)
- Toasts: 0.10 r18 y6 (App.swift:558)
- Permission asks: 0.12 r20 y6 (App.swift:595)
- Swipe disc: 0.12 r16 y6 (Stage.swift:109)
- Dragged tab: 0.14 r12 y4 (TabBar.swift:611)
- When the field is raised over a page, the page gets a ground-coloured scrim at 74% (Omnibox.swift:25-28).

### Motion (Design.swift:151-155)

Only three curves:
- `glide`: spring(0.34, 0.82), for things moving between places
- `settle`: spring(0.30, 0.86), for things arriving or leaving
- `quick`: easeOut 0.14, for hover and state changes

Other timings:
- Refusal shake: 3 decaying swings of +/-7pt over easeOut 0.5 (Design.swift:236-251; Omnibox.swift:76).
- Loading spinner (`Ring`): 10pt, trim 0.78, 1.4 stroke, muted 70%, linear 0.85s (TabBar.swift:854-873).
- First-paint fade: 0.12s (Tab.swift:1335).
- Toast lifetime: 1.7s (Browser.swift:692).
- Transitions: field scale 0.97 + fade (App.swift:419); tabs scale 0.9 from the leading edge (TabBar.swift:430); the live-tab highlight glides between tabs via `matchedGeometryEffect` (TabBar.swift:551).

### Signature pieces

- **Spotlight omnibox.** One raised surface that grows downward, with a hairline under the field.
  - Magnifier 14 medium; placeholder "Search or enter an address" at ink 30% (Omnibox.swift:262).
  - Rows: favicon, globe or magnifier; key text in ink, title in muted.
  - An already-open tab gets a 5pt dot; the row picked with the arrow keys gets ink 12% plus a return glyph; hover is ink 5%.
  - The field sits 60pt above centre (Omnibox.swift:37-40).
  - The rest of the best match is typed in and selected; backspace really deletes it (Omnibox.swift:314-352).
- **Tabs.** Fixed width.
  - The live tab has the wash ground, and ink at 5.5% fills it from the left as you read down the page (TabBar.swift:537-548).
  - The close cross and the spinner share one slot (TabBar.swift:494-505).
  - There is no loading bar: `progress` is kept but never drawn (Tab.swift:190-193).
- **Pinned tab** is one letter (Tab.swift:359-362). Missing-favicon fallback is a letter in an ink 6% squircle (Icons.swift:284-292).
- **Private tab marker** is only `eye.slash` at 9pt, 70% (TabBar.swift:466-471).
- **Toasts** rise from the bottom in a hairline capsule (App.swift:549-561).
- **Load errors** replace the page with one sentence and "Try again" (Stage.swift:187-204; Browser.swift:2214-2229).
- **Swipe disc** for back/forward instead of sliding the page (Stage.swift:83-120).

### Voice

The README says: "a browser with nothing in the way... This one is a tool." In-app text is short declaratives, never exclamatory, and says what will happen:

- "Nothing yet." / "Nothing matches." (Recall.swift:55)
- "Signs you out of every site", "Only what was fetched to draw pages" (Recall.swift:125-129)
- "A tab that keeps nothing" (Browser.swift:1407)
- "Hidden — ⌘Z puts it back" (Browser.swift:1563)
- "Blocking off — reload to see the difference" (Browser.swift:892)
- "Third parties whose only job is to watch" (Settings.swift:370)
- "No site at that address." (Browser.swift:2217)

New features ship off by default (CONTRIBUTING.md). Nothing phones home, and there are no network suggestions.

### Polish to preserve on iPhone

1. No accent colour; selection, hover and picked states are ink at 12% / 5%.
2. An empty tab shows only the field, with no suggestions until you type (History.swift:187-190).
3. Refusal is a shake plus a red rim, never an alert.
4. Inline completion that backspace can remove.
5. History ranking that prefers a site's front page and recent, frequent visits (History.swift:185-262).
6. Only the two springs and one ease.
7. No white flash: the web view stays hidden until its first real paint (Tab.swift:1312-1339). On iOS use `isOpaque = false`, the ground colour, and a public first-paint signal, since this uses a private API.
8. A picture of the page covers a tab while it wakes from sleep (Stage.swift:26-37; Tab.swift:990-994).
9. The reading-progress fill in the live tab.
10. One-sentence toasts that vanish after 1.7s.
11. Errors shown in place of the page.
12. Page scripts run in a separate "Search" content world, so sites can't detect the app (Tab.swift:15-23). This fixed Google CAPTCHAs and refused sign-ins.

## 2. Features relevant to mobile

### Ad and tracker blocking (Shield.swift) — portable verbatim

- The list is hard-coded, not bundled from a file and not downloaded: 44 third-party domains (Shield.swift:57-70). No EasyList.
- Each domain becomes one `block` rule, `^https?://([^/]+\.)?domain`, third-party only (Shield.swift:85-94). One more rule hides 9 ad-slot selectors (Shield.swift:75-80, 95-98). 45 rules in total.
- It recompiles on every launch into `WKContentRuleListStore.default()` as "office-shield" and never checks for an already-compiled copy (Shield.swift:107-126). That's cheap at this size.
- Tabs that open before compiling finishes are queued and get the list when it's ready (Shield.swift:129-136).
- Per-site allowlist: a set in UserDefaults under "shield.paused", keyed by host minus "www." (Shield.swift:31-43).
- It is switched on or off per main-frame navigation by removing/re-adding the list on the tab's content controller (Shield.swift:49-53; Browser.swift:1972-1977). The toggle lives in Settings and reloads the page (Settings.swift:379-390).
- Larger lists would be new work: a converter plus caching.

### Anti-redirect, link cleaning, tracking parameters — none exist

No utm/fbclid/gclid stripping and no bounce or AMP unwrapping. What does exist:

- Navigation policy (Browser.swift:1894-1987):
  - downloads go to `.download`;
  - cmd-click, middle-click and shift-click peek are routed;
  - hidden-element CSS and the blocker are re-armed per navigation;
  - only a list of allowed schemes loads.
  - Any other scheme is handed to its app only if it's the main frame or a click. Clicked mailto/tel open directly; anything else asks through an `NSAlert` (Browser.swift:1994-2012).
- Response policy: redirects are allowed; `Content-Disposition: attachment` or a type WebKit can't show becomes a download (Browser.swift:2043-2067).
- Popup blocking: `javaScriptCanOpenWindowsAutomatically = false` (Tab.swift:110). `window.open` becomes a tab with its own fresh content controller (Browser.swift:2017-2040), which avoids a crash from shared message handlers.
- Verdict: the logic ports; `NSAlert`/`NSWorkspace` become `UIAlertController`/`UIApplication.open`.

### Element hiding — model portable, picker needs a touch redesign

Hidden.swift is only the "what's hidden here" panel (hover a row to preview, Hidden.swift:44-46, 80-83). The engine is Curtain.swift.

- Storage: `[host: [Veil]]` in hidden.json; each Veil has selector, label, note and date (Curtain.swift:11-23, 85-92). Saves are debounced 0.4s and written off the main thread.
- CSS: one `display:none !important` rule per selector, so one bad selector can't break the rest (Curtain.swift:71-81).
- Injection: a user script at `.atDocumentStart`, main frame only, in the Search content world, adds `<style id="office-veil">` (Curtain.swift:143-159; Tab.swift:598-604).
- Because user scripts are fixed per controller, `arm(hiding:)` removes and re-adds about 10 scripts before every main-frame navigation (Tab.swift:535-605).
- The picker script (Curtain.swift:163-378) builds a stable selector (id, then data-testid-style attributes, then stable classes, then an nth-of-type path). It is mouse-centric, so a tap works but there's no preview; iPhone needs a select-then-confirm step.
- Privacy gap: hiding something in a private tab is still saved (Browser.swift:1557-1563 has no private-tab check).

### Private tabs (`shy`) — portable verbatim

- Each private tab gets its own `.nonPersistent()` data store (Tab.swift:80-88). Links and popups from it reuse that store, so sign-in flows keep working (Browser.swift:1267-1268, 2031).
- Nothing is kept: no session entry (Browser.swift:998), no history (Browser.swift:2194, 1669), no reopen-closed entry (Browser.swift:1225), no per-site zoom (Tab.swift:258), no favicon written to disk (Icons.swift:161), no password-save offer (Browser.swift:1623). Extensions stay out unless a setting allows them (Tab.swift:92).
- Curtain.swift does not hide app content for privacy. Nothing hides the app in the app switcher; the iOS version needs to decide on that.

### Bookmarks — model portable, UI rewrite

Model in Bookmarks.swift:10-228: a tree of `{id, title, url?, children?}` (a folder has no url), saved whole to bookmarks.json on each change. Moves refuse to put a folder inside itself (Bookmarks.swift:100-112). The UI (Bookmarks.swift:236-657, `NSMenu`) and BookmarksBar need rewriting.

### History (History.swift) — pure Foundation, portable

- Keyed by the pretty address (no scheme, no www) (History.swift:57-60). Every deep-page visit also counts as a visit to the site's front page (History.swift:66-74).
- Score is visit count x exp(-days/30); prefix match 6, match after the first dot 3, match anywhere 2 (History.swift:241-262).
- Saved to history.json, debounced 1.5s, capped at the top 2,000 by score (History.swift:289-309).
- A seed list of well-known sites is offered until you've visited them (History.swift:315-336).
- It keeps only the last visit date and a count, not a timeline.

### Session (Session.swift) — portable

- Format: `{tabs:[{url,title,pin?,name?}], active}` per space (Session.swift:8-25).
- Written 1.2s after changes (Browser.swift:1014-1022) and flushed at quit (Links.swift:25-27). On iOS, flush when the app goes to background.
- On launch only the active tab loads; the rest are placeholders with no web view (Browser.swift:842-874).
- Unreadable files are set aside, not overwritten (Store.swift:107-113).

### Omnibox and search engines — logic portable, field rewrite

- Typed text becomes an address if it looks like a host, otherwise a search (Browser.swift:86-92; Address.swift:13-65).
- Eight preset engines plus a custom `%s` template (Engine.swift).
- Suggestions: 3 from history, plus a search row only when the text can't be an address (Browser.swift:1704-1738). Cmd-K switches between open tabs (Browser.swift:1743-1764). Return picks: arrow-key row, then the completion, then what was typed (Browser.swift:1828-1868).
- The AppKit text field (Omnibox.swift:243-378) needs a `UITextField` rewrite.

### Reader (Reader.swift) — portable

One JavaScript string that scores page blocks by amount of text, penalised for links; leaving reader mode reloads the page (Tab.swift:207-226). Add a dark stylesheet.

### Sleep (Sleep.swift) — policy portable

- After 30 minutes unseen; macOS memory warning drops that to 5 minutes, critical to 0 (Sleep.swift:25-49).
- Some tabs never sleep (Sleep.swift:66-81).
- To sleep: check for unsent typing, take a JPEG snapshot at quality 0.55, save `interactionState`, discard the web view (Tab.swift:806-849). Waking restores that state (Tab.swift:979-998). `revive()` reloads pages whose web process died (Tab.swift:949-971).
- The memory hook becomes iOS memory warnings plus process-termination handling.

### Recall (Recall.swift) — UI rewrite

It is just the History and Downloads panels. Keep the three-way "Clear…" choice (Recall.swift:114-139).

### Passwords and passkeys

- Vault.swift (Keychain + LocalAuthentication) and the form-watching script in Forms.swift port.
- Vault's site matching uses a private CFNetwork function loaded with `dlsym` (Passkeys.swift:340-344). Not App Store-safe; bundle the Public Suffix List instead.
- Passkeys.swift is built on a macOS-only browser API with an `NSWindow` anchor (Passkeys.swift:44-60, 81). Rewrite or drop; check the iOS entitlements.

### Performance worth copying

- Web views are built lazily on first use (Tab.swift:157-168).
- One shared process pool: measured 41-59ms down to 9-10ms before a load starts (Tab.swift:66-74). The API is deprecated, so measure on iOS.
- The blank tab's web view is pre-built 1s after launch (Browser.swift:845-855).
- Scroll position is reported in hundredths only, to avoid redraws (Tab.swift:721-731).
- File writes are debounced and off the main thread.
- Favicons (Icons.swift:20-200): the page is asked which icons it declares; the best is fetched and drawn into a 64px PNG. They are cached on disk, fresh for 7 days, with separate dark variants (`host@dark`). The uncommitted changes add a cache of known-missing icons and one shared no-cookie session.
- iPhone setup:
  - Set `allowsInlineMediaPlayback = true`. It defaults to false on iPhone, and without it videos can't play inside the page.
  - The user agent is built from the installed Safari.app version, which is macOS-only (Tab.swift:45-64); iOS needs a Mobile Safari-style string.

## 3. Code reuse

### Shareable verbatim (as a shared Swift package)

- Address.swift, Engine.swift, History.swift, Reader.swift, Shield.swift
- Registrable.swift, with a bundled suffix list injected
- Session.swift, which needs only `Space.firstID`
- Curtain.swift (model, CSS injection, message relay; the picker needs a touch pass)
- Forms.swift
- Vault.swift, after replacing its registrable-domain call
- Store.swift, minus the test-world and migration parts

### Near-verbatim

- Design.swift: swap `NSColor(name:)` for `UIColor(dynamicProvider:)`; `Motion`, `Logomark` and `Shake` copy as-is; `Look.apply` becomes `overrideUserInterfaceStyle`.
- Plate.swift parts (`Card`, `Rule`, `Line`, `Caption`, `Hunt`, `Nothing`, `Quick`) and Settings.swift:558-650 (`Segmented`, `Switch`, `Pill`) are pure SwiftUI; `onHover` does nothing on iOS.
- The bookmarks model (Bookmarks.swift:10-228), split out of the AppKit file.
- Favicons (`NSImage` to `UIImage`, `NSApp` appearance to trait collection) and `Mark` (Icons.swift:270-299).
- The omnibox panel view (Omnibox.swift:7-235).
- Sleep policy.

### Built around AppKit; rewrite

- Tab.swift: the tab lifecycle (lines 153-1072) is valuable but mixed with the `PageView` web view subclass and its mouse/keyboard overrides (Tab.swift:1185-1600), `NSImage`, and private APIs. Pull the lifecycle out into its own type.
- Browser.swift (2,311 lines) combines navigation, tab coordination and omnibox responsibilities in one type: lift the navigation delegate (Browser.swift:1891-2067) and omnibox logic (Browser.swift:1704-1868); rewrite the rest.
- App, TabBar, Side, Fold, Stage, SiteCard, Dialogs, StatusLine, ImageMenu, Peek.

### Drop

- Updater, Bench, Links (Apple Events; use scene URL handling), Import (reads Chrome profiles on disk).
- Extensions*/Crx: `WKWebExtension` exists on iOS 18.4+, but the ~5k lines are desktop Chrome-API fill-ins.
- Float (iOS has native picture-in-picture), FrameRate, Inspector, Lights, SpaceSwipe, AutoScroll, Swipe (use WebKit's back/forward gestures).

### App Store blockers

The macOS build ships outside the App Store; an iOS build can't use these private APIs:

- Tab.swift:125 (developer extras), 143-144 (page mute), 1081 (`_isPlayingAudio`), 1322 (first-paint events)
- Browser.swift:2175 (first-paint delegate callback)
- FrameRate.swift:52-75
- Passkeys.swift:341
