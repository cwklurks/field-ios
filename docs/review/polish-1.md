# Polish review 1: Field on video

Reviewed 2026-09-28 against [`docs/motion.md`](../motion.md) and PLAN.md ("Taste", "Smooth"), on the iPhone 17 simulator (60 Hz, headless), Release build (FieldPerf scheme).

## How this was checked

- **Driver:** `FieldPerfTests/CriticTour.swift` has one XCUITest per interaction, with touch marks on. It serves its own loopback pages: the perf article, and a "tone" page (white, then a dark hero, then white, then mid grey). Both pages carry a 2 pt magenta "heartbeat" at the left edge, so the recorder never idles.
- **Recording:** `simctl io recordVideo --codec h264`, resampled to 60 fps. Frame numbers below are in that resampled timeline, counted from the start of the named video. Strips are tiled with each frame's number in its corner.
- **Files:**
  - Strips: `/tmp/field-review/critic/` (called `critic/` below).
  - Videos: `critic/<test>-<look>-<mode>.mp4`.
  - Re-checks on the later build: `critic/v2/`.
- **Two builds:**
  - Main pass: built about 16:20.
  - Re-check: about 20:08. It picked up the edits to FieldSurface.swift, BarSwipe.swift and Stage.swift made in the meantime. P1-01, 02, 03, 04 and 05 were re-recorded on it and **still reproduce**; their `P2-*` strips are from that build.
- **Caveat:** the simulator recorder's timestamps jitter by a few ms, and it drops frames when the Mac is busy. So a single repeated frame is **not** counted as an app stall here. Only multi-frame pauses, overlaps, jumps and ordering are reported, and each one was seen on at least two runs or in both looks.
- **Response counts:** "Lift" means the last frame with the touch ring; L+1 is the first frame after it.

## Defects, most visible first

### P1-01 · blocker · Cancel by swiping the keyboard down (glass and solid, light)
**What's wrong:** the field follows the keyboard down, but once the keyboard is gone the field *stays a field* until the finger lifts: full URL selected, magnifier showing, page still dimmed. On the lift it swaps to the bar's centred host in one frame, then the dim fades. That is a sequence (keyboard, then wait, then snap, then fade), not a shrink that rides the keyboard.
- **Evidence (glass):**
  - `critic/P-swipe-slow-glass-light.png`: frames 1300–1417, step 3. The field sits without a keyboard from about 1378 to 1417.
  - `critic/P-swipe-landing-glass-light.png`: 1360–1375.
  - `critic/P-swipe-lift-glass-light.png`: 1418 is the field, 1419 is the bar text. Scrim 1419–1426.
- **Evidence (solid):**
  - `critic/P-swipe-lift-solid-light.png`: the old build jumped field → bar *and* undimmed in one frame, 1236 → 1237.
  - `critic/v2/…`, strip `critic/P2-swipe-full-solid-light.png`: the latest build still shows the field without a keyboard from 1347 to 1386, and the snap at 1389.
- **Likely cause:** `Field/Bar/FieldSurface.swift`.
  - The close only starts on `keyboardWillHide`, which UIKit sends at the touch's end for interactive dismissal.
  - Nothing maps the keyboard guide's height to the field→bar morph while the finger drags.
  - `showBar` swaps the row for the address at once (`bar.address.isHidden = false`, `surface.row.isHidden = true`) instead of morphing the text.

### P1-02 · blocker · Swipe the keyboard partway down and let go (glass and solid)
**What's wrong:** letting go of a half-dragged keyboard closes the field instead of letting the keyboard spring back. The sequence is:
1. The keyboard jumps back to full height for a frame.
2. It vanishes in one frame, with no animation.
3. The bar appears mid-screen and drops.
4. The dim pops off in one frame.
- **Evidence:**
  - `critic/P-swipe-partial-glass-light.png` (1790–1906): tracking is fine.
  - `critic/P-swipe-partial-release-glass-light.png`: 1917 has the keyboard back up under the bar text, and 1918 has no keyboard at all. The dim is gone at 1921.
  - `critic/P-swipe-partial-release-solid-light.png`: 1714 has the keyboard with no field, and 1715 has no keyboard.
  - Latest build: `critic/P2-swipe-partial-release-solid-light.png`, 1885 → 1886 → 1889.
- **Likely cause:** in `FieldSurface`, one of these closes the field on the release, even though the keyboard is coming back:
  - `keyboardHiding`;
  - `coordinator.onEnded` → `.editingEnded`;
  - the `Scrim`'s tap recognizer.

  The close then runs with no keyboard curve to ride.

### P1-03 · blocker · Suggestions arrive on top of the field (every look)
**What's wrong:** when the rows first appear, they are drawn *over* the field's own text and slide up through it. For about 6 frames, two addresses overlap: a row's "weather.gov" sits on top of the field's "weather.gov".
- **Evidence:**
  - `critic/P-rows-arrive-glass-light.png`: frames 1464–1475. The overlap is at 1466–1471.
  - Latest build: `critic/P2-rows-arrive-glass-light.png`, 1318–1323.
- **Likely cause:** `Field/Bar/SurfaceView.swift` `layoutSubviews`, driven by `FieldSurface.edited()`'s `.quick` animation.
  - The rows' frame grows from zero height, standing on the row.
  - The hosted SwiftUI content is laid out at full size straight away and isn't clipped (`rows.clipsToBounds` is false).
  - The field row has no background to hide it.

### P1-04 · major · Go, or cancel, with suggestions showing
**What's wrong:**
1. The bar's content (back, host, ring, count) appears inside the still-tall field surface.
2. The suggestion rows stay at full opacity for 3–4 frames (the row's "weather.gov" and the bar's "weather.gov" are both on screen).
3. The rows fade.
4. The surface keeps its height as an *empty white slab* above the bar, and only then collapses onto it.
- **Evidence:**
  - `critic/P-go-glass-light.png`: 1674–1685. Both addresses show at 1676–1682; the empty slab is at 1684–1685.
  - Latest build: `critic/P2-go-glass-light.png`, 1527–1538 (empty slab at 1536–1537).
  - Cancel: `critic/P-cancel-rows-glass-light.png`, 1507–1522 (empty slab at 1515–1516).
- **Likely cause:** in `FieldSurface.showBar`, the rows fade on `.quick` while the surface's height follows the keyboard curve, which is much longer. The rows' height isn't collapsed or clipped along with the shape.

### P1-05 · major · Closing a card in the grid (swipe and ✕)
**What's wrong:** after a card closes, the grid's scroll position **jumps in one frame**. Then the remaining cards travel diagonally through each other in a pile for about 8 frames before settling.
- **Evidence:**
  - `critic/P-card-swipe-glass-light.png`: 1588–1611. Jump at 1603 → 1604, pile at 1604–1611.
  - `critic/P-card-x-glass-light.png`: 1730–1753. Jump at 1736 → 1737.
  - Latest build: `critic/P2-card-swipe-reflow-glass-light.png`, jump at 1726 → 1727.
- **Likely cause:** `Field/Tabs/TabGrid.swift` `reflow()` / `layoutCards(moving:)`.
  - The content offset is clamped or set outside the spring. `layoutSubviews` also resets `contentSize` when it rewrites `count.text`.
  - The spring moves cards straight to their new frames with no ordering or z-order, so they cross.

### P1-06 · major · Glass bar and field on a white page (light)
**What's wrong:** on a blank tab or a new tab, the glass surface is white on white. There is no visible edge or shadow, so the field is placeholder text floating above the keyboard and the bar is a floating "Search or enter an address  8". It looks unfinished.
- **Evidence:**
  - `critic/P-grid-new-glass-light.png`: 1873–1888.
  - `critic/P-blank-cancel-glass-light.png`: 2062–2077.
  - `critic/P-cold-blank-glass-light.png`: 776–836.
- **Likely cause:** `SurfaceBackground.paint()` in `Field/Bar/SurfaceView.swift`. The glass is tinted with ground at 0.6 over a ground-coloured page, and the glass look has no rim or lift. Solid has one.

### P1-07 · major · Launch on a blank tab (and after the Welcome's Continue) is stepwise
**What's wrong:** the sequence is:
1. White.
2. The *bar* fades in, with its back and count showing.
3. The bar turns into the field at the bottom.
4. The field sits with no keyboard for about 0.5–0.8 s.
5. The keyboard rises and carries it up.

That is four separate beats, where the contract says a blank tab presents the field directly.
- **Evidence:**
  - `critic/P-cold-blank-glass-light.png`: 650–836, step 6. The bar is at 776, the field at 782–824, and the keyboard starts at 830.
  - `critic/P-cold-blank-solid-dark.png`: 520–613. The bar is at 529, the field at 535–586, and the keyboard at 589.
  - `critic/P-welcome-continue-glass-light.png`: 1339–1357.
- **Likely cause:**
  - `Browser.start()` sets `fieldOpen` on the turn after the first frame.
  - `FieldSurface.sync()` then runs the tap morph (`handle(.open)` → `showField`) from the bar, instead of starting in the field.
  - The focus then waits for the keyboard.

### P1-08 · major · Glass tone catches up late after a tab switch
**What's wrong:** after swiping to another tab, the glass keeps the previous tab's tone, then changes colour **on its own** while nothing moves.
- On Tab 7, it turned dark about 1.8 s after landing (frames 1250 → 1360).
- On Tab 8, it stayed dark over pink for about 0.75 s, then flipped light (1391 → 1436).
- **Evidence:**
  - `critic/P-bar-tone-late-flip-glass.png`: frames 1236–1371, step 9.
  - `critic/P-barswipe-tone-glass-light.png`: 1386–1425.
- **Likely cause:** `Field/Bar/Tone.swift` `ToneSampler`. `watch()` resets the reading but only samples when the offset changes or after the 2 s idle. A tab switch or wake doesn't call `look()`.

### P1-09 · major · Welcome: the two previews look the same
**What's wrong:** the preview page's text ends well above the bar, so the Glass preview has nothing to show through. Glass and Solid differ only by a faint shadow, which defeats the screen's one question.
- **Evidence:** `critic/P-welcome-previews-light.png` (frame 1040). Dark: `critic/P-welcome-dark.png`.
- **Likely cause:** `Field/Bar/BarPreview.swift`. The page content is too short to run under the bar.

### P1-10 · major · Settings › Appearance › Dark changes nothing while the sheet is up
**What's wrong:** the segment moves to Dark, but the sheet and everything visible stay light for the whole 3.5 s it was selected.
- **Evidence:** `critic/P-settings-sequence.png`, frames 1400 / 1470 / 1600 / 1700 / 1760 / 1900 of `critic/testSettings-x-light.mp4`. This run had no `-look` or `-bar.look` arguments, and the Bar look choice *did* take effect.
- **Likely cause:** unclear from the video. `FieldApp`'s `.preferredColorScheme(look.scheme)` on the root doesn't seem to reach the presented sheet, or doesn't update from the `@AppStorage` write in `SettingsView`.

### P1-11 · major · The bar ghosts over the grid on open, and crossfades with the grid's row on close
**What's wrong:**
- **Opening:** the bar stays fully drawn over the shrinking page for about 3 frames, then fades *over the cards*: "127.0.0.1" and the "9" are drawn across the card's text.
- **Choosing a card:** the bar fades in while the grid's bottom row is still there. At 1300–1301, "Search or en[9 Tabs]ter an address … Done" overlap, so two rows of chrome are on screen at once.
- **Evidence:**
  - `critic/P-grid-open-glass-light.png`: 1096–1119 (ghost at 1101–1106).
  - `critic/P-grid-choose-glass-light.png`: 1295–1326 (overlap at 1300–1301).
  - Dark: `critic/P-grid-open-glass-dark.png`.
- **Likely cause:**
  - In `Field/Browser/BrowserView.swift`, the `FieldSurfaceHost` `.opacity` with `.animation(Motion.quick)` runs independently of the flight.
  - `TabGrid.showRow` has its own delays.

### P1-12 · major · A flash when a tab chosen in the grid wakes
**What's wrong:** about 1.7 s after the card lands, when the live page replaces its picture, a lighter full-width band flashes behind the bar for 1–2 frames.
- **Evidence:** `critic/P-wake-bar-glass-light.png`: 1415–1423. The flash is at 1418–1419.
- **Likely cause:** `Field/Browser/Stage.swift` `place` / `revealed`. When the cover hides, the web view's bottom obscured area (or its bottom scroll-edge effect) draws before the page's own pixels.

### P1-13 · major · Tapping the address: little visible motion until the keyboard comes, and a hitch in the dim
**What's wrong:** the first response is on L+1 (good). After that:
- For the next 6–9 frames, the only motion is the text sliding left and a 4 pt widening. The surface visibly starts "becoming the field" only when the keyboard starts, at about L+7 to L+10.
- On every run, the dimming skips a step about 5 frames after the lift, on the same frame as the focus.

This is where the "it lags" feeling lives.
- **Evidence:**
  - `critic/P-open-glass-light.png`: 1232–1263. The lift is at 1233, the text swaps at 1234, and the keyboard starts at 1240.
  - `critic/P-open-glass-light-full.png`: 1233–1240. Brightness steps are 1–1.5 per frame, then 3.8 at 1238 → 1239.
  - The same +4 to +6 frame step shows in all four looks (`an.py lifts` on each `testField-*.mp4`).
- **Likely cause:** `FieldSurface.showField`.
  - `fieldMargin` (12) against `Bar.margin` (16) makes the pre-keyboard shape change tiny.
  - `coordinator.open(field)` holds the main thread just as the scrim's fade is due.

### P1-14 · major · White flash on launch with Settings › Appearance = Dark on a light phone
**What's wrong:** the white launch screen shows, then crossfades to dark over about 0.3 s, on every launch.
- **Evidence:** `critic/P-cold-blank-solid-dark.png`: 520–541.
- **Likely cause:** `LaunchBackground` follows the phone's appearance, not the app's `look`. This only happens when the two differ, but "no white flash" is a stated rule.

### P1-15 · minor · New tab from the grid: the field fades in over the old card
**What's wrong:** the field appears mid-screen *before* the blank page has grown over the grid. The old card's text shows through around it (1866–1868), and then the field rides the keyboard up. It doesn't come from the + or from the bar.
- **Evidence:** `critic/P-new-tab-two-placeholders-dark.png`: 1864–1871. Light: `critic/P-grid-new-glass-light.png`, 1862–1872.
- **Likely cause:** `Tabs.newTabFromGrid` calls `openField` in `closeGrid(then:)`, which runs at the flight's start.

### P1-16 · minor · The grid has no top edge treatment
**What's wrong:** cards scroll under the status bar and the Dynamic Island, and the time is drawn straight over coloured cards. Safari blurs this.
- **Evidence:** `critic/P-grid-open-glass-light.png`: 1112–1119. `critic/P-card-swipe-glass-light.png`.
- **Likely cause:** `Field/Tabs/TabGrid.swift`. `scroll` has no `topEdgeEffect`.

### P1-17 · minor · Rings pop instead of moving with the motion
**What's wrong:**
- On choosing a card, the ring jumps to the chosen card one frame before its flight starts (1298).
- On opening the grid, the current card's ring pops in after landing (1113 → 1114).
- **Evidence:** `critic/P-grid-choose-glass-light.png` (1298) and `critic/P-grid-open-glass-light.png` (1113–1114).
- **Likely cause:** `TabCard.show(... current:)` is re-run by `layoutCards` before or after the flight. The `decorationHidden` animation doesn't cover the ring.

### P1-18 · minor · The first keystroke shows nothing
**What's wrong:** after typing "w" there is no inline completion and no rows, even with 2,000 places of history. Safari suggests from the first letter.
- **Evidence:** `critic/P-rows-arrive-glass-light.png` (1464–1465).
- **Likely cause:** `HistoryStore.suggestions` / FieldKit ranking has a minimum length.

### P1-19 · minor · The collapsed glass pill has no edge on white text pages
**What's wrong:** page text runs right up to both sides of the host, and the pill's outline is barely visible.
- **Evidence:** `critic/P-scroll-slow-down-glass-light.png`: 1013–1047.
- **Likely cause:** `SurfaceBackground` for glass (the same cause as P1-06).

### P1-20 · minor · Settings from the tabs menu
**What's wrong:**
- After tapping "Settings" in the menu, nothing moves for 6 frames (1142–1147).
- The menu pill then morphs back into the bar with "Settings" and "127.0.0.1" drawn over each other (1149–1150).
- The sheet only starts after that.
- **Evidence:** `critic/P-settings-open-light.png`: 1140–1163.
- **Likely cause:** the system `UIMenu` dismissal. The sheet presentation waits for it (`openSettings` → `settingsShown`).

### P1-21 · minor · Welcome: layout and the disabled button
**What's wrong:**
- Before a choice, Continue is a grey capsule with an invisible label.
- The previews float in a large empty middle, with two `Spacer(minLength: 24)` stretching.
- **Evidence:** `critic/P-welcome-choose-glass-light.png`: 1047–1055.
- **Likely cause:** `Field/Welcome/Welcome.swift`.

### P1-22 · minor · Static: typography and details off the Mac tokens
- **Card titles:** `TabCard.title` is a hard-coded 14 pt system font. Ramp.tab is 15.
- **Letter badge:** 11 semibold. Ramp.glyph is 11 regular.
- **Grid "Done":** 17 semibold, but semibold is reserved for headings. In the same row, "9 Tabs" is 14 medium muted, and "+" is a 19 pt medium symbol, so the row mixes three sizes.
- **Site badge:** it shows "1" for `127.0.0.1`, the first character of an IP address (`TabCard.show`).
- **`data:` pages:** the bar shows the blank-tab placeholder "Search or enter an address" (`Bar.host`), so a real page reads as an empty tab (`critic/P-barswipe-tab7-glass.png`).
- **Files:** `Field/Tabs/TabCard.swift`, `Field/Tabs/TabGrid.swift`, `Field/Bar/Bar.swift`.

## What is already good, so keep it

- **The tap's first frame:**
  - The address becomes the field's text, fully selected at ink 12%, on L+1 in every run.
  - Back and tabs go at once, with no fade over the text.
- **Opening, and cancelling by a tap outside:**
  - The surface rides the keyboard's top edge on the keyboard's own curve.
  - There is one object and no ghost on a simple open or close (`critic/P-cancel-glass-light.png`, 1118–1149).
  - The host slides from where the field's text was to the centre.
- **Scrolling:**
  - The bar shrinks 1:1 with the finger and grows back with a spring.
  - Flicking to the top is clean in both directions (`critic/P-scroll-slow-down-glass-light.png`, `critic/P-scroll-slow-up-glass-light.png`, `critic/P-flick-down-glass-light.png`).
- **Glass tone while scrolling:** it follows what is under the bar, not the page's background. It turns dark over the dark hero within a few frames, has no flicker at boundaries, and reads correctly over mid-grey. It is correct in both app looks (`critic/P-tone-glass-light-vs-dark.png`).
- **Grid open:** the live page shrinks into its own card as one object, and its card is hidden while it flies (`critic/P-grid-open-glass-light.png`, 1099–1112).
- **Choosing a card:** the picture grows into the page with no white flash, and the page keeps its picture until it paints (`critic/P-grid-choose-glass-light.png`).
- **Sideways on the bar:**
  - The pages track the finger 1:1, with the neighbours' pictures and a gap.
  - They rubber-band at the ends and settle with velocity.
  - This is wired and works (`critic/P-barswipe-tab7-glass.png`).
- **Swipe a card away:** it tracks the finger 1:1 and fades (`critic/P-card-swipe-glass-light.png`, 1590–1601).
- **Restoring 8 tabs:** the page's picture is on screen in the first app frame, with the bar, and there is no flash (`critic/P-restore-launch-glass-light.png`).
- **Dark mode:** the field, the suggestions and the solid bar look right (`critic/P-good-dark-field.png`).
- **Welcome:** choosing a look lifts the chosen card and settles the other, with a haptic, on the settle curve.

## Not covered

- On-device keyboard timing (the simulator's keyboard is lighter), and anything at 120 Hz.
- Reduce Motion.
- A real network page loading, beyond the loopback article.
