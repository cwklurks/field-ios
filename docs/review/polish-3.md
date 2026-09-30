# Polish review 3: Field on video

Reviewed 2026-09-29, evening, against [`docs/motion.md`](../motion.md), [polish-1](polish-1.md) and [polish-2](polish-2.md). The build was the FieldPerf scheme (Release), made from the tree at e48ddef ("fix: polish round 3 from video review"), which was clean. It was recorded on the iPhone 17 simulator (60 Hz, headless). Everything was recorded from scratch with `FieldPerfTests/CriticTour.swift`.

## Method

The method is the same as in polish-1 and polish-2:
- The driver runs one test per interaction, with touch marks on, over its own loopback pages that carry a 2 pt heartbeat.
- Frame numbers are indices in the video resampled to 60 fps, counted from the start of the named video. Where a strip is labelled with decimals (`src.py`), those are the source frames' own times × 60.
- "L" is the last frame with the touch ring; L+1 is the first frame after the lift.

What changed from polish-2:
- **New tests in CriticTour.**
  - `testBarSwipeUp`: a quick swipe up on the bar, Done, then a slower drag up, then Done.
  - `testReferenceMessages`: the same half drag and release as `testCancelSwipe`, done in Messages. It is not a Field test. It gives the system's own keyboard behaviour on that gesture, for P1-02.
  - `testCancelSwipeBack` (added in e48ddef) was recorded for the first time.
- **Coverage.** 33 recordings, all in `critic/r3/`: field, cancel by tap, and cancel by swipe in both looks, light and dark; swipe-back; scroll; grid (glass light, solid light, glass dark); bar sideways and up; cold blank; restore; Welcome; fresh-install Welcome; Settings; tone.
- **Where things are.**
  - Strips: `/tmp/field-review/critic/R3-*.png`, called `critic/` below.
  - Videos: `critic/r3/<test>-<look>-<mode>.mp4`.
- **A tooling correction.** `critic/gaps.sh` lists frames by `pts_time`, which these recordings leave out for many frames. So it reports "recorder gaps" that aren't there: a 2.6 s gap in `testBarSwipeUp-glass-light` had frames every 50 ms, and a 330 ms gap in the Messages release had frames every 17 ms. Use `best_effort_timestamp_time`, sorted. Some of polish-2's "recorder gap" remarks may have the same problem. `an.py`, which decodes, was unaffected.

Caveats:
- The simulator's keyboard is lighter than the phone's.
- 120 Hz and Reduce Motion are not covered.
- The Welcome screen has no heartbeat, so the recorder idles between taps there, and response counts on its look buttons aren't reliable.

## Polish-1 and polish-2 items

| ID | Status | Evidence |
|---|---|---|
| P1-02 half-drag release | **partly** | Fixed: the bar now glides down from where the finger left it, and the dim fades with it. See `R3-swipe-partial-release-glass-light.png` (lift 1623, glide 1626–1642), `…-solid-light.png` and `…-glass-dark.png`. <br>Not fixed: the **keyboard still vanishes in one frame**, so the bar floats with nothing under it and then falls alone. Glass light 1625 → 1626, solid 1934 → 1935, glass dark 1911 → 1912. The recorder had frames every few ms there, so this is not a dropped frame. <br>**This is not UIKit's choice.** The same drag in Messages animates the keyboard down over about 7 frames with the input bar riding it (`R3-ref-messages-release.png`, 830–836). See P3-02. |
| P1-02 drag back up | **partly** | The keyboard and the field come back with the finger, and the dim returns. But: <br>• while the finger is still down, with the keyboard fully back (about 13 frames), the field shows the bar's "127.0.0.1" with no magnifier; <br>• on the lift it swaps to the selected "127.0.0.1/article" and the magnifier in one frame (1219.7 → 1220.0). <br>See `R3-swipe-back-glass-light.png` and `R3-swipe-back-lift-glass-light.png`, and P3-05. |
| P1-04 Go / cancel with rows | **fixed** | The rows and the extra height fold on L+1, and the one-row surface rides the keyboard down. There's no empty slab. <br>• Go: `R3-go-glass-light.png` (1757.8 → 1759.3) and `R3-go-solid-dark.png` (1449 → 1450). <br>• Cancel: `R3-cancel-rows-glass-light.png` (1538 → 1539). |
| P1-05 card close | **not fixed** | The motion is new (slide along a row, "hop" between rows), but it still overlaps and now also ghosts. See P3-01. |
| P1-07 blank-tab launch | **fixed** | The field is there on the first app frame, waits about 7 frames, and then rides the keyboard up. <br>• Glass light: 570 → 592. <br>• Solid dark: 574 → 596. <br>See `R3-cold-blank-src-glass-light.png` and `R3-cold-blank-src-solid-dark.png`. Round 2 had about 0.9 s. The simulator's keyboard may have been warm from earlier runs; the accepted residue stands either way. |
| P1-11 bar ghost over the grid on open | **fixed** | The bar is gone on L+1, in the same frame the shrink starts, with nothing drawn over the cards. See `R3-grid-open2-glass-light.png` (1442) and `R3-grid-open-first-restore-solid-dark.png`. |
| P1-13 little motion before the keyboard | **fixed** | On L+1 the bar has become the field's shape with the address selected. It then rises on an ease-out ahead of the keyboard, and the dim comes with it. See `R3-open-zoom-glass-light.png` (1313 → 1314 → 1319) and `R3-open-solid-dark.png` (1009 → 1010). This held in all four look/mode runs. |
| P1-15 new tab: field before the page | **partly, unchanged** | On the frame after +, the field is drawn over the article card. The card labels "The Hedgerow Ledger" and "New tab" still show under it for 3 frames, and the blank page grows in behind afterwards. See `R3-grid-new-zoom-glass-light.png` (1847–1849) and `R3-grid-new-glass-light.png`. |
| P1-21 Welcome disabled button | **fixed** | Before a choice, Continue is a pale pill with a faint label, which reads as a standard disabled button. See `R3-welcome-fresh-before-after-choice.png`. |
| P2-01 Welcome: no keyboard | **fixed** | On a true fresh install, the welcome fades and the field comes in riding the keyboard, and it stays (`R3-welcome-fresh-continue.png`, 1051–1073; `R3-welcome-fresh-after.png`). The same holds with `-welcomed NO` (`R3-welcome-continue-glass-light.png`). |
| P2-02 bar vanishes after launch | **fixed** | There's no bar motion in the bar band between launch and the first touch in any recording checked: `testBarSwipe` (600–894), `testScroll` both looks, and `testField`. On the article, the page fades in under a still bar (`R3-launch-article-glass-light.png`, 636–641). |
| P2-03 Settings pops in | **fixed** | The gear press shows on L+1. The sheet slides up from the bottom from about L+4, which is within the accepted L+2/L+3 plus recorder jitter (`R3-settings-open.png`, 1050 → 1073). Done and swipe-down both slide it away (`R3-settings-done.png`, `R3-settings-dismiss.png`). |
| P2-04 restore: bar before page | **fixed** | The page's picture and the bar arrive together inside the system's launch crossfade. <br>• Solid dark: 518–533. <br>• Glass light: 526–533. <br>No frame shows the bar alone (`R3-restore-after-solid-dark.png`, `R3-restore-after-glass-light.png`). |
| P2-05 first grid open late | **fixed** | L+1 hides the bar, and the shrink's first step is the normal size. It was smooth in five first opens across four runs: `R3-grid-open-first-restore-glass-light.png`, `…-solid-dark.png`, `R3-grid-open-first-glass-light.png` (1084/1085), and the `testTabs-solid-light` and `…-glass-dark` first opens at L+1. |
| P2-06 Welcome: two labels | **partly** | The pressed state is now 2 frames, not 14. But the field's placeholder and cursor are still drawn over the fading "Continue" for about 2 frames (`R3-welcome-handover-glass-light.png`, 1097.3–1097.7). It is faint, and minor. |
| P2-07 `data:` in the bar | **accepted** | Intended. Not re-flagged. |

## New defects, most visible first

### P3-01 · major · Closing a card in the grid ghosts and overlaps (swipe and ✕, light and dark)
**What's wrong:** the new close has cards on the same row slide along it, and a card that changes rows fades and shrinks where it was while a second copy grows in at its new slot. On video that gives:
- **Two copies of one card:** at 1587, a fading Tab 7 is at the bottom left and a growing Tab 7 is at the top right.
- **Sliding cards over faded ones:** Tab 8 slides left *over* the fading Tab 7 (1582–1586). Tab 6 and Tab 8, still sliding out of their slots, overlap the translucent Tab 7 and article card growing into them (1589–1591).
- **A washed-out grid:** with the ✕, three cards are fading or growing at once. At 1720–1721 almost every card on screen is pale, and in dark mode they dim toward black (1608–1615).
- **All of this over a scroll:** the scroll offset moves in the same spring.

Closing tabs in the grid is an everyday action, and this is exactly the ghosting the user rejected before (motion.md principle 2: no frame may show two copies).
- **Evidence:**
  - Swipe: `R3-card-swipe-zoom-glass-light.png` (1581–1592) and `R3-card-swipe-glass-light.png` (1578–1601).
  - ✕: `R3-card-x-glass-light.png` (1713–1736) and `R3-card-x-glass-dark.png` (1604–1615).
- **Likely cause:** `TabGrid.layoutCards(was:)`.
  - `.hop` calls `fadeAway(copyOf:)`: a snapshot that fades out over 0.14 s at the old slot, while the card itself grows in at the new one after only 0.08 s. It is under its neighbours, but they are still sliding through that slot (a spring of about 0.3 s).
  - The fix is choreography, not tuning. The simplest honest version is Safari's: every card moves as one object to its new slot on one spring, the row-changer going over the others (raised, not sent to the back), and no copies. If the hop stays, the grow-in has to wait until the slot is clear, with no copy left behind.

### P3-02 · major · On a half-drag release, Field's keyboard leaves in one frame, where the system's takes 7
**What's wrong:** see the P1-02 row. The bar's glide is now continuous, but the keyboard under it disappears between two frames, every time, in both looks. So what the user sees is:
1. the keyboard blinks out;
2. the bar hangs in mid-air;
3. the bar falls about 450 pt on its own over about 16 frames.

In Messages, the same gesture animates the keyboard down with the input bar riding it. The decision "UIKit decides" was taken on the belief that the snap was UIKit's; it isn't.
- **Evidence:**
  - Field: `R3-swipe-partial-release-glass-light.png` (1625 → 1626), `R3-swipe-partial-release-solid-light.png` (1934 → 1935), `R3-swipe-partial-release-glass-dark.png` (1911 → 1912). Real frame times: 1623.9, 1624.1, 1624.9, 1625.0 … 1626.6.
  - Messages: `R3-ref-messages-release.png` (826–837), with real frames at 827.0, 827.6 … 836.3.
- **Likely cause:** something on Field's release path ends the keyboard's own dismissal animation. Candidates, in `FieldSurface`:
  - `keyboardHiding` → `handle(.keyboardHiding)` → `release()`/`pin()`, which re-pins off `keyboardLayoutGuide` and lays out inside the keyboard's animation;
  - `.overrideInherited*` in `SurfaceMotion.animate`;
  - a resign in the same turn;
  - the scrim scroll view's own handling.

  Log the `keyboardWillHide` duration and curve in Field versus a bare `UITextView` + `.interactive` scroll view, then bisect.

### P3-03 · major (needs a hand repro) · Done sometimes does nothing after a swipe-up opened the grid
**What's wrong:** in `testBarSwipeUp` glass light, the first Done tap after a swipe-up open did nothing. The grid stayed up, and not even the touch ring was drawn. It happened in both runs, on different opens:
- run 1: after the quick swipe;
- run 2: after the slow drag.

Every other Done in the session worked, including both in solid dark. XCUITest logged "Synthesize event" each time. The ring is drawn by a window-level recognizer that never claims touches, so a missing ring means the touch never reached the window, or that recognizer was stuck from the swipe.
- **Evidence:**
  - Run 1: `R3-barswipe-up-done-glass-light.png` (1000–1138, the grid unchanged and no ring). Video `critic/r3/testBarSwipeUp-glass-light-run1.mp4`.
  - Run 2: `R3-barswipe-updrag-run2-glass-light.png` (1382–1448, the grid unchanged to the end). Video `critic/r3/testBarSwipeUp-glass-light.mp4`, whose log shows the Done synthesized at 18.35 s.
- **Likely cause:** unconfirmed. Suspect the bar's pan in `FieldSurface.swiped`: `.up, .began` calls `showTabs()` and the bar is hidden while the pan is still live, which can leave the gesture system waiting on touches that never end. It could also be an XCUITest artefact. **Try it by hand** on the simulator (swipe up, then Done, ten times) before fixing anything.

### P3-04 · minor · Swipe up on the bar is a trigger, not a gesture
**What's wrong:**
- The grid opens on the pan's `.began` and animates to the end on its own. On a slow drag, the card flies to its slot (1302–1311) while the finger is still travelling up until 1352, so the grid doesn't follow the finger (motion.md principle 4).
- The slow drag's first response came about 9 frames after touch-down.

In Safari, swiping up from the bar is interactive.
- **Evidence:** `R3-barswipe-updrag-solid-dark.png` (1290–1359) and `R3-barswipe-up-solid-dark.png` (the quick swipe, which is fine).
- **Likely cause:** `FieldSurface.swiped`, `case (.up, .began): browser.showTabs()`. A scrubbed open would need Stage's flight driven by the pan's translation, released with its velocity.

### P3-05 · minor · Dragging the keyboard back up: a half-state while held, then a swap
**What's wrong:** see the P1-02 row. The field shows the bar's host, with no magnifier and no selection, for as long as the finger stays down after the keyboard is back. On the lift, the text becomes the full URL and the magnifier appears in one frame.
- **Evidence:** `R3-swipe-back-lift-glass-light.png` (1212.8–1224.8).
- **Likely cause:** `springBack` runs only on `keyboardWillShow`, which UIKit sends at the lift. While the finger holds, the scrubbed `dragging` animator sits at 0 with the bar's address showing. Showing the field's own row once the scrub is back to 0 would remove both.

### P3-06 · minor · The grid's bottom row disappears under Settings and pops back after it
**What's wrong:** the grid's bottom row (gear, +, count, Done) is gone as the sheet starts up. It comes back in one frame, after the sheet has fully left:
- Done: 1677 → 1679;
- swipe-down: 2122 → 2125.
- **Evidence:** `R3-settings-open.png` (1054.2 → 1055.2), `R3-settings-done.png` and `R3-settings-dismiss.png`.
- **Likely cause:** the row is hidden while `settingsShown`, and shown in `onDismiss` (`viewDidDisappear`) with no animation. Leave it in place under the sheet, or fade it on the sheet's own transition coordinator.

### P3-07 · minor · Dark glass shows the page's text almost unblurred behind the address
**What's wrong:** over body text in dark mode, "than the chu… it frames. Its" is readable through the bar, around "127.0.0.1". In light mode the same spot is milky. Not a regression: round 1 looked the same (`R1-bar-glass-dark-zoom.png`).
- **Evidence:** `R3-bar-glass-dark-zoom.png` against `R3-bar-glass-light-zoom.png`.
- **Likely cause:** `SurfaceBackground`'s dark glass tint or blur is weaker than the light one. Worth a look on the phone, where the user will judge it.

## What is good, so keep it

- **The tap:** L+1 in every look and mode. The bar becomes the field's shape with the address selected, rises on an ease-out ahead of the keyboard, and then rides it. The dim comes in steps, with no hitch.
- **Suggestions:** the first key completes inline, and the rows grow up out of the one surface.
- **Go and cancel, with or without rows:** the rows fold on the first frame, the text glides from the field's place to the bar's centre, and the bar rides the keyboard down and lands. There's no slab and no second address.
- **A full swipe down the keyboard:** the field shrinks into the bar with the keyboard, and the dim follows (`R3-swipe-full-glass-light.png`, `R3-swipe-full-glass-dark.png`).
- **Scrolling:** 1:1 shrink and grow, and clean flicks (`R3-scroll-flick-glass-light.png`, `R3-scroll-flickback-glass-light.png`). A tap on the collapsed pill grows it back into the bar from L+1 (`R3-tone-tap-glass-light.png`).
- **Glass tone:** it follows white, the dark hero and grey under the bar, in both looks and in dark mode, with no late flips (`R3-tone-*.png`). On white it has a rim (`R3-blank-cancel-glass-light.png`).
- **Grid:**
  - Opening is one object from L+1, including the first open after launch, with no bar ghost.
  - Choosing a card grows it into the page with no chrome overlap (`R3-grid-choose-glass-light.png`).
- **Sideways on the bar:** the pages track the finger, rubber-band at the ends, and settle with the throw (`R3-barswipe-slow-glass-light.png`, `R3-barswipe-throw-glass-light.png`).
- **Launches:**
  - Cold blank: the field is on the first frame and the keyboard comes in about 7 frames.
  - Restore: the page and the bar arrive together.
  - The bar no longer moves by itself after launch.
- **Welcome:** the previews show the difference between the looks. Continue fades into the field, riding the keyboard, on a fresh install too.
- **Settings:** it slides up from the gear and slides away on Done or a swipe. Appearance flips the whole screen on L+3.

**Regressions against the polish-2 "already good" list:** none found.

## Verdict

Almost, but not yet. This round fixed every blocker from polish-2 (the Welcome keyboard, the self-moving bar) and every regression (restore, Settings, first grid open). The core loop the user will use a hundred times a day is now clean on video: tap, type, Go, cancel, scroll, switch tabs. If that were the whole app, I'd send it today. But two things they will meet on day one are exactly the kind of flaw they rejected the last build for:
- **Closing tabs in the grid (P3-01)** shows ghost copies, cards sliding over half-faded cards, and a washed-out grid, every time, for about a quarter of a second.
- **Letting go of a half-dragged keyboard (P3-02)** makes the keyboard blink out and leaves the bar hanging, then falling. Messages shows it isn't the system's doing.

Add a possibly dead Done after a swipe-up (P3-03, which needs a hand repro), and I'd hold the phone build for one more short round on those three. Then send it, with P3-04 to P3-07 left for later.
