# Bar polish: open, close, and the bar on a page

Reviewed 2026-10-03, against [`docs/motion.md`](../motion.md) and the method of [polish-5](polish-5.md) and [polish-6](polish-6.md). The ask was to make the bar cleaner in three places: when the field opens, when it closes, and while the bar sits on a page. The build is the FieldPerf scheme (Release), from the `polish/bar-motion` branch off 8e2a91b (build 29). Everything was recorded on the iPhone 17 simulator (60 Hz, headless).

## Method

- **New recordings in `FieldPerfTests/BarTour.swift`**, one per bar interaction, with touch marks on, over loopback pages that carry the heartbeat:
  - `testOpenClose`: tap, then a tap outside; tap, then a slow swipe down the keyboard; tap, type an address and Go. The address is `/slow/page/3`, a new CriticServer route that answers 1.5 s late, so the ring shows.
  - `testOnPage`: a slow drag down the page and back, flicks each way, then a tap on the pill.
  - `testPillSwipe`: the pill, shrunk, swiped sideways to the next tab and back.
  - `testReopenMidClose`: a tap outside, then the address tapped again as soon as XCUITest can (see the caveats).
  - `CriticTour.testTone` was reused for the glass over a dark photo, white and grey.
- **Looks.** The baseline was glass light and solid dark. The after was glass light and solid dark again, plus glass tone.
- **Measuring.** `scripts/motion/frames.py` counts touch to response ("L" is the last frame with the touch ring). For the rest I cut frame strips and read them frame by frame, zoomed on the bar.
- **Where things are**, all in the worktree's `build/bar-polish/` (gitignored):
  - `before/`: the baseline videos and strips.
  - `after/`: the press, swipe and ring fixes.
  - `after2/`: the keyboard ride, plus solid dark and tone.
  - `after4/`: the reopen.
  - `after5/`: the glass tone fix.
  - `compare/B0*.png`: before and after, stacked.
  - `tools/`: scratch tools. `rec.sh` records one UI test, `s` and `strip.py` cut labelled strips, `stack.py` stacks them, and `unit.sh` runs the unit tests and stops xcodebuild once Swift Testing has printed its summary, since it hangs after.

Caveats:
- **XCUITest is slow to interrupt.** Each synthesized event costs about 14 frames, longer than the first part of the new close. So the reopen could only be caught near the end of a close; see B-03.
- **A shared record didn't work.** One event record holding two taps delivered only the first, so the helper was dropped.
- **Not covered:** 120 Hz, the phone's keyboard, Reduce Motion and VoiceOver.

## Verdict

**Better, and ready for the next build.** Two bugs are fixed that showed on every use: the dimmed address after a tap on the pill, and the stale host after a tab swipe. The close by tap and Go now rides the keyboard down, as the field rides it up. The glass no longer cuts to grey when it changes tone. The ring fades instead of blinking.

Open, swipe-down, scroll and the pill tap are unchanged where they were already right, in both looks. Every touch still answers at L+1 or L+2, and the FieldPerf budgets are green.

## Findings, most visible first

### B-01 · major · Fixed · After a tap on the pill, the address stays dimmed
**What was wrong:** scroll down so the bar shrinks to the host, then tap the pill. The bar grows back, but the address stays at half alpha, grey like a placeholder, until the field next opens. It happens on every tap of the pill.
- **Evidence:** `before/pilltap-late.png`. The address is grey at 2560, 2620 and 2680, after the tap at 2542. Fixed in `after/pilltap-late.png` and `after2/pilltap-sd.png`, and side by side in `compare/B01-pill-tap.png`.
- **Cause:** the press dimmed the address on touch down. It came back only on touch up outside, cancel or drag exit, on the theory that a tap always hides it by opening the field. A tap on the pill doesn't open the field: it brings back the whole bar (`FieldFlow`'s `.tap(collapsed: true)`).
- **Fix:** the press now lives on `BarContent`, which owns the button. Touch down dims it, and every way the finger leaves brings it back, a tap included. A tap that opens the field still hides the address in the same turn, so no frame shows it whole. The open is unchanged at L+2.
  - Test: `BarPressTests`.

### B-02 · major · Fixed · A tab swipe on the bar keeps the old host, then grows in a second step
**What was wrong:** swipe the pill or bar sideways. The page slides and lands, but the bar keeps saying the old tab's host for about 24 frames (0.4 s) after the page has landed. Then, in one frame, the text changes, and only then does the pill grow back to the whole bar. That breaks motion.md principle 5 (no stepwise sequences), on every tab swipe.
- **Evidence:** `before/pillswipe-gl.png`. The swipe is at 1331, the page is in place by about 1342, and the pill says "127.0.0.1" until 1364. At 1366 it says "data:" and grows.
- **Cause:** the tab only becomes current in Stage's `landed`, the completion of the carousel's spring, which waits out the whole tail. `place(tab)` then expands the bar.
- **Fix:** when Stage's `settle` sets off toward a neighbour, `Tabs.heading(by:)` sets `arriving`, which the bar already reads for popups (P6-07), and the bar expands in the same glide.
  - A finger catching the spring puts `arriving` back to the tab on screen.
  - A neighbour with no URL yet (a popup still on its way) leaves `arriving` as it was.
  - After: the swipe is at 1302, the pill says "data:" at 1304 and grows alongside the page (`after/pillswipe-gl.png`, `after2/pillswipe-sd.png`, `compare/B02-tab-swipe.png`).
  - Test: `TabsTests.aSwipeSaysWhereItsGoingUntilItLands`.

### B-03 · minor (seen on every close) · Fixed · On a tap outside or Go, the keyboard pulls away from the bar, which lands after it has gone
**What was wrong:** the field closes into the bar while the keyboard goes down, but the two separate. The gap under the bar grows from the field's 8 pt to about 15 to 20 pt on the strips, and the keyboard is gone well before the bar arrives. The bar then sinks the last few points for about 8 more frames, landing about L+22 after a tap outside. motion.md asks for the bar to stay "attached to its top edge, and land in the bar's place as the keyboard finishes".
- **Evidence:** `before/cancel-gl.png` (tap outside, lift 1351, still sinking at 1373) and `before/go-close.png` (Go at 2181, still sinking at 2199).
- **Cause:** the rider stands on the keyboard layout guide, which stops at the home indicator. A probe showed what UIKit gives the rider on a close by tap: an additive `CASpringAnimation` with mass 1, stiffness 555, damping 47.1 (critically damped), lasting 0.383 s and covering 267 pt. The keyboard's top travels 301 pt, to the screen's bottom, on the same spring. So the keyboard outruns the rider by 34x pt at progress x, which comes to about 30 pt as the keyboard passes the bar's place, at x ≈ 0.89, about frame 9. The rider then has 14 frames of tail left.
- **Fix:** `KeyboardRide` reads the rider's spring and works out what keeps the bar's foot the field's own 8 pt gap above the keyboard's top, until it reaches its place. That is `min((rest - gap)·x, travel·(1 - x))`, never negative.
  - On the keyboard's will-hide notice for a close already under way, `FieldSurface` adds it to the surface as an additive keyframe animation, timed as the rider's own ride. It runs in the render server like the rest.
  - It's zero at both ends, so the bar lands exactly where it did.
  - A tap that reopens the field mid-close lets it go on the quick curve, from where it had the bar (`letKeepGo`).
  - Swipes keep their own path (`trailKeyboard`) and are untouched: the probe found no spring on the rider for a swipe, and a swipe's notice comes during `.field`, not `.closing`.
  - After: the bar holds an 8 to 10 pt gap above the keyboard all the way down, and lands at L+13 after a tap outside and after Go, with no drift after that (`after2/cancel-gl.png`, `after2/go-gl.png`, `compare/B03-cancel.png`, `compare/B03-go.png`). Solid dark is the same (`after2/cancel-sd.png`).
  - Tests: `KeyboardRideTests`, including the critically damped and underdamped spring against the closed form.

### B-04 · minor · Fixed, with a residue · The glass cuts from dark to grey when the page under it turns light
**What was wrong:** scrolling a dark photo out from under the pill, the dark glass went to mid-grey in one frame. Then the light glass materialized over the next 8 frames. That reads as a flash, every time the tone flips, which on real sites with photos is often.
- **Evidence:** the top row of `compare/B04-glass-tone.png` (`after2/tone-out-zoom.png`: 1454 dark, 1455 grey).
- **Cause:** P6-01's fix replaces the glass with a new view in the new tone, and removed the old one in the same frame.
- **Fix:** inside an animation, the old glass dematerializes (`effect = nil`) as the new one comes in, and is removed once the animation is over. Outside an animation it's replaced at once as before, which keeps P6-01: Private's field is painted dark without animation from its first frame.
  - After: dark, then darker grey, then light, over about 9 frames, with no cut (bottom row of `compare/B04-glass-tone.png`).
  - Test: `SurfaceBackgroundTests`.
- **Residue:** the ink still turns on the first frame of the change, so for about 3 frames (1575 to 1578) the address is dark on dark glass.
  - Fading the ink too would mean a cross-dissolve on the bar. When the tone changes during a morph (the field closing over a dark page), that would ghost a moving address.
  - So it's left, and it's worth a look on the phone at 120 Hz, where it's half as long.

### B-05 · nit · Fixed · The ring blinks on and off
**What was wrong:** the loading ring was shown and hidden with `isHidden`, a cut beside an address that is often moving (Go starts the load as the field turns into the bar). A load that stops and starts again at once, a redirect, would blink it twice.
- **Evidence:** `compare/B05-ring.png`.
- **Fix:** `RingView.loading` fades it in and out on the quick curve, and hides it once it's out, so it stops turning (P6-12 was a ring that never stopped).
  - Test: `RingTests`.

### Not fixed: notes for the phone, or by design
- **B-06 · The field waits for the simulator's keyboard.** At a tap, the field widens, rises its 24 pt `ahead`, then hovers for about 8 frames until the keyboard starts (1195 to 1204 in `before/open-gl.png`). That's the simulator's keyboard latency, not the app: the open is still L+1 or L+2. Check it on the phone, where the keyboard is warm.
- **B-07 · Back and tabs on the wide shape.** On the first frame of a close, back and the tab count fade in at the field's full width, so the count's box shows faintly at the far right of the wide shape, then travels in with the shrink. It's faint and in motion, and I didn't change it.
- **B-08 · Open: the text grows to the right.** The bar's host becomes the field's full address on the frame after the tap, anchored at the text's start, so the text grows to the right rather than about its centre. That's one object (principle 2) and the start doesn't move, so it's by design.
- **B-09 · The tone follows the page a little late.** Light to dark follows within about 2 frames, but dark to light about 6 to 8 frames after the dark band has left the bar: that's the sampler's 150 ms tick plus a snapshot. It's not a flash. Shortening the tick costs main-thread work on scroll, so it's left.
- **B-10 · The address finishes its glide after the bar lands.** On a close, the address's slide back to centre finishes a few points after the bar has landed: the tail of the keyboard curve on the address's transform. It's barely visible.
- **B-11 · The page shows through the edges of light glass.** Over body text, light glass shows the text through its edges. That's Liquid Glass with the 60% ground tint. Solid is the look for anyone who minds.

## Regressions

None found. These were compared touch by touch with the baseline, in glass light and solid dark (`frames.py` reports in each recording folder):

| | Before | After |
|---|---|---|
| Tap the address (open) | L+2 (glass), L+1 (solid) | L+1 to L+2 in both. Field text at L+2 with no frame of the whole address (`after/open-gl-zoom.png`) |
| Cancel by tap | L+2 / L+1 | L+1 / L+1, landing at L+13 instead of about L+22 |
| Swipe down the keyboard | Bar and keyboard follow the finger | Frame for frame the same (`after2/swipe-gl.png` against `before/swipe-gl.png`) |
| Go | Ring with the host, from the first frame | The same, with the ring fading in. Landing at L+13 |
| Scroll shrink and grow, flicks | 1:1, back and tabs gone by half-way | Unchanged |
| Pill tap | L+1, address left dimmed | L+1, address whole |
| Bar swipe sideways | L+1, host 24 frames late | L+1, host from L+2 |

`testReopenMidClose`: the reopen landed 17 and 20 frames into a close, with the keep still running a couple of points. The hand-off has no jump and the field opens at L+1 (`after4/reopen1.png`).

## Tests

- **Unit tests:** `build/bar-polish/tools/unit.sh <log>` runs `xcodebuild test -project Field.xcodeproj -scheme Field -destination "id=<iPhone 17>" -derivedDataPath build/unit`. Result: **347 tests in 59 suites, all passed**. New: `BarPressTests` (2), `RingTests` (1), `TabsTests.aSwipeSaysWhereItsGoingUntilItLands` (1), `KeyboardRideTests` (6) and `SurfaceBackgroundTests` (2). Each fix's tests failed first, except `RingTests`, written alongside its fix; it failed to compile without it.
- **FieldPerf**, Release, iPhone 17 simulator: `InputTests` (3), `ScrollTests` (2) and `TabsTests` (4) all passed, **9 of 9**. After the glass fix, `ScrollTests` (2) and `InputTests.testOpenField` were run again and passed, 3 of 3 (`build/bar-polish/perf2.log`).

## For the phone

- **The close by tap and Go** (B-03): does the bar sit on the keyboard all the way down, with no dip behind its top edge?
  - The fix reads the keyboard's spring off the rider, and assumes the keyboard itself, drawn by another process, runs the same spring from the same start.
  - If the phone's keyboard started a frame late, the gap would close by about 10 pt near where the bar lands. The 8 pt gap is there to absorb that.
- **A tap on the address in the first 9 frames of a close** (B-03's `letKeepGo`). The simulator couldn't reach that window.
- **The glass's dark-to-light change at 120 Hz** (B-04's residue).
- **The open's hover before the keyboard** (B-06) with the phone's warm keyboard.
- **VoiceOver on the pill:** back and tabs are at alpha 0 there, which VoiceOver should skip, and the address is the one button.
