# Polish review 2: Field on video

Reviewed 2026-09-28, late evening, against [`docs/motion.md`](../motion.md) and [polish-1](polish-1.md). The build was made from the current tree at about 22:55 (FieldPerf scheme, Release) and recorded on the iPhone 17 simulator (60 Hz, headless). Everything was recorded from scratch with `FieldPerfTests/CriticTour.swift`.

## Method

The method is the same as in polish-1:
- The driver runs one test per interaction, with touch marks on. It serves its own loopback pages, each with a 2 pt heartbeat at the left edge.
- Recordings are resampled to 60 fps.
- Frame numbers are indices in that resampled timeline, counted from the start of the named video.
- "L" is the last frame with the touch ring; L+1 is the first frame after the lift.

What changed from polish-1:
- **Settings test.** `testSettings` now opens Settings from the grid's gear, `tabs.settings`.
- **Fresh-install test.** I added `testWelcomeFresh`. It runs with the app uninstalled first and no `-welcomed` argument, so Continue runs exactly as on a first launch.
- **Where things are.**
  - Strips: in a local scratch folder, no longer kept, called `critic/` below. Round-2 strips are `R2-*.png`.
  - Videos: `critic/<test>-<look>-<mode>.mp4`.
  - Round-1 material: `critic/round1/`.

Caveats:
- The simulator recorder jitters by a few ms and drops frames when idle or busy. So a single held frame is not reported as a stall, and a response on L+2 counts as a real L+2 only when it repeats across runs.
- The Settings test's "Done" tap was resolved by XCUITest to the grid's Done button under the sheet. It landed on the DuckDuckGo row instead, so the sheet's own Done wasn't exercised. The sheet was closed by swiping it down.
- Not covered: restoring the keyboard by moving the finger back up during a swipe-down (my drag never reverses), Reduce Motion, 120 Hz, and device keyboard timing.

## Polish-1 items

| ID | Status | Evidence |
|---|---|---|
| P1-01 swipe-down: field waits, then snaps | **fixed** | During the drag, the field shrinks into the bar with the keyboard, and the dim follows. See `R2-swipe-full-glass-light.png` (1160–1238) and `R2-swipe-full-solid-light.png` (1250–1328). Left over: the text swaps from `127.0.0.1/article` to `127.0.0.1` and the magnifier drops in one frame (glass 1180 → 1182), which is minor. |
| P1-02 half-drag release | **not fixed**, judged by the new rule | On release, the keyboard disappears in **one frame** instead of continuing down from where the drag left it. <br>• Solid (`R2-swipe-lift-solid-light.png`): the finger lifts at 670 pt, and 1314 → 1315 the keyboard vanishes, the bar drops about 110 pt, and the dim goes, all in one frame. <br>• Glass partial drag (`R2-swipe-partial-release-glass-light.png`): lift at 1602, held for 2 frames, then 1604 → 1605 the keyboard is gone in one frame and the dim fades over 1605–1609. <br>• The "restore when the finger moves back up" path wasn't tested. |
| P1-03 rows over the field's text | **fixed** | The rows grow upward out of the surface, clipped, with no second address (`R2-type-glass-light.png`, 1380–1391). |
| P1-04 Go / cancel with rows | **partly** | Fixed: there's no longer a double address, because the rows go in one frame. Still there: the surface stays tall as an **empty white slab** for about 5 frames while it rides down. <br>• Go: `R2-go-glass-light.png`, 1662–1667. <br>• Cancel: `R2-cancel-rows-glass-light.png`, 1464–1468. |
| P1-05 card close: scroll jump and pile-up | **partly** | Fixed: the scroll offset no longer jumps. Still there: the cards travel diagonally through and *under* one another for about 10 frames, and Tab 6 disappears behind Tab 4 and Tab 7. <br>• Swipe: `R2-card-swipe-glass-light.png`, 1599–1610. <br>• ✕: `R2-card-x-glass-light.png`, 1737–1747 (Tab 6 is hidden at 1740). |
| P1-06 glass white on white | **fixed** | A thin rim and lift make the field and bar read on white (`R2-blank-field-glass-light.png`, `R2-blank-cancel-glass-light.png`). |
| P1-07 blank-tab launch in steps | **partly** | Fixed: the "bar first" beat is gone, and the field appears directly. Still there: it sits at the bottom with no keyboard for about 0.9 s before the keyboard lifts it. <br>• Glass: `R2-cold-blank-glass-light.png`, 784–838. <br>• Solid dark: `R2-cold-blank-solid-dark.png`, 672–720. <br>Part of this wait is the simulator's keyboard loading. |
| P1-08 tone flips late after a switch | **fixed** | The tone stays stable through three bar swipes, with no change while nothing moves (bar-luma trace over `testBarSwipe-glass-light.mp4`). |
| P1-09 Welcome previews look the same | **fixed** | The previews now run a photo page under the bar: glass shows it through and solid covers it (`R2-welcome-fresh-continue-src.png`, first tiles). |
| P1-10 Appearance › Dark not live | **fixed** | The sheet turns dark within 2 frames of the tap, and light again the same way (`R2-settings-dark-flip.png`, 1424–1431; `R2-settings-sequence.png`). |
| P1-11 bar ghost over the grid | **partly** | Fixed: choosing a card no longer overlaps the grid row and the bar (`R2-grid-choose-glass-light.png`, 1289–1312). Still there on **open**: <br>• the bar stays fully drawn over the flying card for 3 frames and fades across the cards (1457–1461); <br>• at 1462 "data:" and the "9" are faintly drawn over the gear, + and Done. <br>See `R2-grid-open2-bar.png`, 1455–1470. |
| P1-12 flash when a tab wakes | **fixed** | No band behind the bar when the live page replaces its picture (`R2-wake-bar-glass-light.png`). |
| P1-13 little motion before the keyboard | **partly** | Good now: the address dims on touch-down, the field's text is on L+1 in 7 of 9 taps (L+2 in the other two, within recorder jitter), and the text glides from the host's place to its own (`R2-open-glass-light.png`, `R2-tap-src-glass-dark.png`). Still there: the surface's own shape change before the keyboard arrives (L+8 to L+9) is small. I didn't re-measure the dim hitch. |
| P1-14 launch-screen flash in Dark | **accepted** | System limit, not re-flagged. |
| P1-15 new tab: the field before the page | **partly** | Fixed: the field now appears in the bar's place, not mid-screen. Still there: it appears on the frame after the + (1865), over the still-visible grid and its labels, and the blank page grows in behind it afterwards (1866–1872). See `R2-grid-new-glass-light.png`. |
| P1-16 no top edge on the grid | **fixed** | The cards soften under the status bar (`R2-grid-settled-light.png`, `R2-grid-settled-dark.png`). |
| P1-17 rings pop | **fixed** | The ring rides with the flight both ways (`R2-grid-open-glass-light.png` 1101–1103, `R2-grid-choose-glass-light.png` 1291). |
| P1-18 first key shows nothing | **fixed** | Typing "w" completes inline at once, and the rows follow on the next frame (`R2-type-glass-light.png`, 1381–1382). |
| P1-19 collapsed pill has no edge | **fixed** | A faint rim is visible over text (`R2-scroll-down-glass-light.png`). |
| P1-20 Settings via the tabs menu | **superseded** | The menu is replaced by the gear. The new opening has its own defect: P2-03. |
| P1-21 Welcome layout, disabled button | **partly** | The previews are fixed. I couldn't re-verify the disabled Continue up close this round (a tool outage). In the overview it is still a pale pill with a faint label before a choice. |
| P1-22 static tokens | **fixed** | Checked in code: card titles use Ramp.tab, the letter is Ramp.glyph regular and appears only for a letter (no "1" for 127.0.0.1), and the grid row is Ramp.row with Done in medium. |

## New defects, most visible first

### P2-01 · blocker · Welcome › Continue lands on a field that never gets its keyboard (a regression)
**What's wrong:** after Continue, the welcome fades and the field appears at the very bottom. Then nothing happens for at least 3.3–4.3 s, until the test ended, and the recorder captured no further change. In round 1 the keyboard rose about 18 frames after Continue.
- **Evidence:** it happened on all three runs, including a true fresh install with no `-welcomed` argument.
  - `R2-welcome-fresh-continue-src.png`: the field is parked from about frame 912 to 1189.
  - `testWelcome-glass-light.mp4` and `testWelcome-glass-dark.mp4`: the same, with recorder gaps 1119–1321 and 1245–1444.
- **Likely cause:** `FieldApp.finishWelcome()` now calls `browser.start()` from the cover's fade completion (via `NextFrame.run`). `start()` sets `fieldOpen`, but the field doesn't take focus. Possibly `FieldSurface.sync()` → `showField` runs while the snapshot cover is still in the window, or before the surface is in a window.

### P2-02 · blocker · The bar vanishes and springs back from below, by itself, about 1.5–2 s after launch
**What's wrong:** with nothing touched, the whole bar disappears for 4–8 frames, then rises from below the screen and settles.
- **Evidence:**
  - `R2-bar-vanish-barswipe.png`: gone at 792–798, rising at 800–808.
  - `R2-bar-vanish-tabs.png`: 786–802.
  - `R2-bar-vanish-field.png`: gone at 934–936 and back at 938–942. This one coincides with the page's first paint.
  - It is also in `testScroll-solid-light.mp4` (about 797–800).
  - It was already in round 1 (`round1/testBarSwipe-glass-light.mp4`, frame 767) and I missed it then.
- **Likely cause:**
  - `Keyboard.warm`, via `FieldSurface.warmSoon`, fires 1.5 s after the surface appears. The rider is pinned to `view.keyboardLayoutGuide`, so the hidden field's focus and resign move the guide.
  - `keyboardWillShow` and `keyboardWillHide` are ignored while `warming`, but the guide's layout isn't.

### P2-03 · major · The Settings sheet pops in after a pause
**What's wrong:** after the gear tap, nothing moves for 8 frames. Then the sheet is fully up in a single frame, with no slide from the bottom.
- **Evidence:** `R2-settings-open.png`. The lift is at 1333; 1334–1341 are unchanged; the sheet is complete at 1342.
- **Likely cause:** `TabGrid.onSettings` → `settingsShown`. The sheet is presented from `BrowserView` while the grid, which is UIKit, sits above the SwiftUI tree. Presentation seems to wait a turn, and the transition animation is lost, perhaps presented inside a transaction with animations disabled.
- **Note:** swipe-to-dismiss is fine. The sheet follows the finger and settles (`R2-settings-dismiss.png`).

### P2-04 · major · Restoring 8 tabs: the bar comes before the page (a regression)
**What's wrong:** the sequence is:
1. After the launch screen, the bar fades in over a blank white page for about 8 frames.
2. The page's picture appears, still fading in, pale.

In round 1 the first app frame had the picture and the bar together.
- **Evidence:** `R2-restore2-glass-light.png` shows the bar-only frame at 680 and the page at 692. `R2-restore-first-src.png` shows the same thing frame by frame.
- **Likely cause:** in `Stage.place` / the cover, the snapshot now loads asynchronously (`snapshots.load`) instead of being in memory for the first frame. The surface also appears on its own fade.

### P2-05 · major · The first grid open after launch is late and skips
**What's wrong:** on the first open, the response is on L+2 in both runs, and the first moving frame is already about a third of the way to the card, so the start of the shrink is skipped. The second open in the same run is L+1 and smooth.
- **Evidence:**
  - First opens: `R2-grid-open-first-jump.png` (lift 1091, unchanged 1092, jump 1093) and `R2-grid-open-first-dark.png` (lift 1206, unchanged 1207, first motion 1208).
  - Second open: `R2-grid-open2-src.png`.
- **Likely cause:** the grid is still being built on the tap. `prewarmGrid` waits 1.5 s after the first paint, and it seems not to have run, or not to have covered the cards' pictures. The first open then pays for `makeGrid`, `layoutCards` and the snapshot decode inside the tap's frame.

### P2-06 · minor · Welcome › Continue: pressed for 14 frames, then two labels
**What's wrong:**
- The button stays in its pressed grey for about 14 frames while the browser builds under the cover.
- The field's placeholder "Search or enter an address" is then drawn *over* the word "Continue" for about 4 frames as the cover fades.
- **Evidence:** `R2-welcome-fresh-continue-src.png`, first two rows.
- **Likely cause:** `FieldApp.finishWelcome`. The field sits exactly where the Continue button is, and the cover is a snapshot crossfade.

### P2-07 · minor · A `data:` page shows "data:" in the bar
**What's wrong:** a page whose address has no host now says "data:". It should be a readable name or the page's title.
- **Evidence:** `R2-grid-open2-bar.png` and `R2-barswipe-throw-glass.png`.
- **Note:** this only matters for pages with no host (`data:`, `about:`, `file:`).

## What is good, so keep it

- **The tap:** the address dims on touch-down, which is new and good. The field's text is on L+1, fully selected, and glides from the host's place to its own. There's no second address.
- **Suggestions:** the first keystroke completes inline and shows rows. The rows grow upward out of the one surface, with no overlap.
- **Swiping the keyboard down:** the field shrinks into the bar with the keyboard, and the dim follows.
- **Scrolling:** 1:1 shrink and grow, springs with velocity, and flicks are clean (`R2-scroll-down-glass-light.png`, `R2-scroll-up-glass-light.png`).
- **Glass tone:**
  - While scrolling it follows the content under the bar, with no flicker, in both app looks. The white → dark hero → white → grey sequence is identical to round 1.
  - It no longer changes by itself after a tab switch.
- **Glass on white:** it has a visible rim.
- **Grid:**
  - Choosing a card: the card grows into the page as one object, with no chrome overlap, and the ring moves with it.
  - Waking a tab no longer flashes.
  - The grid's top edge softens under the status bar.
  - Its bottom row and typography are on the ramp.
- **Sideways on the bar:** the pages track the finger 1:1, rubber-band at the ends, and settle with velocity (`R2-barswipe-slow-glass.png`, `R2-barswipe-throw-glass.png`).
- **Settings:** changing the appearance is live under the sheet, and swipe-to-dismiss follows the finger.
- **Welcome:** the two previews now show the difference between the looks.

**Regressions against the polish-1 "already good" list:**
- **Restoring 8 tabs:** it no longer shows the page in the first frame (P2-04).
- **The blank-tab field after Welcome:** it no longer gets its keyboard (P2-01).

Everything else on that list still holds.
