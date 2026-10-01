# Polish review 6: the Release 1 candidate

Reviewed 2026-09-30, against [`docs/motion.md`](../motion.md), [polish-5](polish-5.md) and the "What to Test" list in [`docs/testflight.md`](../testflight.md). The build was the FieldPerf scheme (Release), made from a clean `git worktree` of 9cc1b2e ("feat: Tidy wired into the grid (M6)") plus this round's `FieldPerfTests/CriticTour.swift`. It was recorded on the iPhone 17 simulator (60 Hz, headless). fb4b57e (stale duplicates) landed on main during the review and is not in this build.

## Method

The method is the same as polish-5: one test per interaction, touch marks on, loopback pages with the heartbeat, `an.py lifts` for touch responses, and frame strips.

New this round:
- **New tests in CriticTour** (round 6):
  - `testFirstRun`: a fresh install, the welcome, then a real site typed.
  - `testCleanLinks`: a Google result, a Facebook link, a Reddit link and an AMP link, tapped on a loopback page.
  - `testTabsByHand`: eight tabs opened from +, one swiped away, then home, force-quit and relaunch, with no seed arguments.
  - `testSaveFolder`: Save, a new folder, the star, then Saved on Read later and on the folder.
  - `testSettingsNew`: "Tabs untouched for", Private's two rows, and "What Private can't do" from Settings.
  - `testPrivateLoop`: Private's own core loop in the dark.
  - `testGroupMenu`: Add Similar Tabs, Ungroup, then the stale banner's Close and Undo.
- **Reused drivers:** `PrivateTour` (enter and leave, drag, switcher, wipe, capture, first page blocked) and `TidyTour` (Tidy, stale, sections).
- **Face ID** is enrolled on the simulator (`notifyutil … BiometricKit.enrollmentChanged`), and a match is sent when the test prints `FACE ID NOW` (`critic/rec6.sh`). The first batch ran before enrolment stuck, so its unlocks went to the passcode sheet. `testEnterLeave-glass-light-faceid` is the run with Face ID.
- **Coverage:** 50 recordings in `critic/r6/`:
  - every TestFlight item that the simulator can do;
  - every new feature;
  - the core loop in glass light and solid dark, each compared touch by touch with its round-5 twin;
  - CNN, with blocking and with the shield off.
- **Where things are:** strips are at `/tmp/field-review/critic/R6-*.png` (`critic/` below), and videos at `critic/r6/<test>-<look>-<mode>.mp4`.

Caveats:
- **Unreliable timestamps.** The recorder's timestamps went non-monotonic in several videos this round:
  - pts and dts disagree when it idles;
  - ffmpeg's best-effort time switches between them;
  - in `testCancelSwipe-glass-light` it jumps backwards by 170 frames.

  Where that happened, I read the frames in decode order with a new tool, `critic/idx.py` (strips labelled `#index time`). The response counts from `an.py` are trustworthy only in videos whose timestamps run forward; I checked each suspicious one in decode order.
- **Two runs stalled on the host.** `testTabs-solid-dark` sat in event synthesis for 21 s with the recorder stopped. `testRestore-solid-dark` waited 4 × 60 s for "App animations complete" on a static screen. I re-ran both (`-run2`), and both were clean. See P6-12.
- **Not covered:** 120 Hz, Reduce Motion, the phone's keyboard, the system screenshot's Full Page (the simulator can't trigger it headless), and "sign in to something" in Private.

## Verdict

**Not yet. Fix two majors first, then send.** Both are in Private's look, small, and in one place each.

- **P6-01:** the field rises light, then cuts to dark, on every entry into Private.
- **P6-02:** the clock is dark on dark on Private's grid and new-tab page.

Everything else is ready for friends:
- Every item on the TestFlight list works on video.
- The core loop is frame for frame what rounds 4 and 5 approved, in both looks.
- Six of round 5's minors and nits are fixed (P5-01, -02, -03, -04, -06, -07).
- Tidy, the stale banner, Capture, the lock, the cover, the wipe and Face ID all behave.

The minors below can ride along to a later build. P6-03 and P6-04 are worth taking with the two majors, since they sit on the same Private screen.

## Defects, most visible first

### P6-01 · major · Entering Private: the field rises light, then cuts to dark
**What's wrong:** from the everyday look in light mode, the switch starts the slide, and the field opens from the bar on the same frame, as designed. But the field is the *light* glass pill, while the keyboard under it is already dark.
- For about 8 frames the light field rides up over the sliding grids, with the everyday grid row's "3 Tabs" and "Done" visible under it.
- Then the field cuts to Private's dark in one frame, as the slide lands.

Two things are wrong. Private is supposed to be dark from its first frame, and the change happens in one frame (motion.md principles 2 and 6). Every new session shows it, and so does every session after a wipe. "Enter Private" is on the friends' list.
- **Evidence:**
  - `R6-private-field-flip.png` (testWipe, 2228–2237: light from 2228.6, dark at 2236.7);
  - `R6-private-enter-field-src.png` (testEnterLeave, 1232–1242);
  - `R6-private-enter-tap2.png` (testPrivateLoop, #400–#409);
  - all 3 of 3 entries recorded.
- **Likely cause (unconfirmed):** `FieldSurface.updateProperties()` does set `view.overrideUserInterfaceStyle = .dark` "so it never rises light". But the field's glass is visibly still light until the slide ends, so either:
  - the override reaches the field's surface only on a later trait pass; or
  - the glass keeps the tint it took from the white everyday grid until the next `paintTone()`.

  Check that `enterPrivate()`'s `openField()` runs after the style has been applied to the field surface itself, not only to `view`. Or paint the surface dark before the field opens.

### P6-02 · major · Private's clock is dark on dark
**What's wrong:** the status bar stays in the light app's style over Private's dark screens.
- On a new private tab, the time, Wi-Fi and battery are near-black on #1c1c1c.
- On the private grid the time is dark grey, while Wi-Fi and battery are light.

In both places the clock is close to unreadable. It's at rest, not a passing frame, so it shows in every screenshot a friend sends. Over a private *page* and on the lock screen it's correct (light).
- **Evidence:** `R6-private-blank-rest.png`, `R6-private-grid-rest.png`, `R6-private-statusbar.png` (light on the lock screen and pages; dark on the grid).
- **Likely cause:** nothing sets the status bar for Private. It follows the app's light `preferredColorScheme`, which private.md rightly leaves alone so that the everyday grid doesn't darken mid-slide. Give the root controller `preferredStatusBarStyle = .lightContent` while `browser.privately`, updated in the strip's animation.

### P6-03 · minor · The private bar says "Search o…r an address"
**What's wrong:** on a new private tab with the field closed, the bar shows the eye.slash mark, then a middle-truncated placeholder. Every private new tab shows this.
- **Evidence:** `R6-private-blank-rest.png`.
- **Likely cause:** `BarContent.say` prepends the mark and two spaces to the placeholder. The label is sized for the bare placeholder and truncates in the middle. Truncate the tail, size the label for the attachment, or use a shorter placeholder in Private.

### P6-04 · minor · "What Private can't do" takes two taps on a new private tab
**What's wrong:** a new session opens with the field up, and the welcome is dimmed under the field's scrim, so the link reads as disabled. The first tap on it only closes the field; a second tap opens the list. The TestFlight notes tell friends to read this screen.
- **Evidence:**
  - `R6-privloop2-ov.png`: the field closes at 1411, and the list opens at 1590 after the second tap;
  - `critic/r6/testPrivateLoop-glass-light.log`: the taps are at 17.34 s and 20.23 s;
  - `R6-private-welcome-zoom.png`: the dimmed welcome;
  - `R6-privloop-ov.png`: the first run, which failed on exactly this (one tap, then no list). Its video was overwritten by the re-run.
- **Likely cause:** the field's scrim takes the tap to cancel. Let a tap on the welcome's button close the field *and* present the list, or keep the welcome out of the dim.

### P6-05 · minor · The first Capture Page after launch waits 2 s with nothing on screen
**What's wrong:** after choosing PDF, the menu closes and the page sits still for about 124 frames (2 s) before the share sheet starts. No "Capturing the page…" toast shows. Later captures in the same run start the sheet 14 to 23 frames after the lift (Image at 2396 → 2419; private PDF at 4002 → 4016).
- **Evidence:** `R6-capture-pdf-src.png` (lift 1447, sheet from 1571), `R6-capture-wait.png`, `R6-capture-image-src.png`, `R6-capture-private-pdf-src.png`.
- **Likely cause:** the same first-share cost as P5-10. The capture itself is fast, so the 300 ms toast never fires. Keep the toast up until the sheet's presentation starts, or build a `UIActivityViewController` out of sight after launch. Check on the phone.

### P6-06 · minor · Tidy's result, and the stale banner, are off-screen where the grid opens
**What's wrong:** the grid opens at the current tab, which is loose and so sits at the bottom. On Apply:
- the sheet slides away while the cards glide (good);
- but the groups form above the viewport, so what's left on screen is the loose tabs and "Grouped 8 tabs · Undo";
- the sections are only seen by scrolling up.

The stale banner sits at the top of the grid for the same reason, and with 13 tabs it isn't on screen when the grid opens.
- **Evidence:** `R6-tidy-apply-src.png` (1272–1303), `R6-tidy-ov.png`, `R6-stale-idx.png` (#389, banner off-screen); `R6-sections-ov.png` shows the sections when the grid is scrolled to the top first.
- **Likely cause:** layout order, which is by design: groups first, loose tabs last. Scroll to the first new section in the same glide as Apply. The banner could ride the same rule, or sit where the grid opens.

### P6-07 · minor · "Popup blocked · Open": the bar keeps the old host for 0.5 s
**What's wrong:** P5-02 is fixed: the page slides out and the new tab slides in. But the bar over the new, still blank tab says "127.0.0.1" for about 30 frames (1044–1072) before "example.org". It's the old tab's address over the new one.
- **Evidence:** `R6-popup-open-glass-light.png`.
- **Likely cause:** `bar.show(url: goingTo ?? page.url, …)`. The popup's tab has no `url` until it commits, and nothing sets `goingTo` for it. Give the new tab its pending URL, as Go does.

### P6-08 · nit · "Add similar tabs" with nothing found is a full sheet
**What's wrong:** the sheet rises to full height to say "No other tabs look like these.", with a disabled Add. Its title is in sentence case, while the menu item reads "Add Similar Tabs".
- **Evidence:** `R6-groupmenu-ov.png` (2130 onward).
- **Suggestion:** a toast with the same words, and one case for both.

### P6-09 · nit · Rename Group doesn't select the name
**What's wrong:** the alert opens with "Loaf Sourdough" and the cursor at the end, so typing appends: the group became "Loaf SourdoughTrip".
- **Evidence:** `R6-sections-ov.png` (2340–2520).
- **Suggestion:** select all when the alert appears.

### P6-10 · nit · Settings jumps to the top after "What Private can't do"
**What's wrong:** Settings was scrolled down to Private when the list opened. When the list is dismissed, Settings is back at its top.
- **Evidence:** `R6-settings-light-idx.png` (#771, scrolled) and `R6-settings-limits-close.png` (#894 onward, at the top).
- **Likely cause:** unconfirmed. The `.sheet` inside the ScrollView may rebuild its content.

### Notes, not defects yet
- **P6-11, the first entry into Private once paused.** In `testEnterLeave` (glass light) nothing changed for about 12 frames after the switch's lift (1219.7 → 1232.1, `R6-private-enter-src.png`). Three other first entries started on L+2 or L+3 (`R6-private-enter-tap-drag.png`, `R6-private-enter-tap2.png`, testSwitcher at 1205.8 → 1207.6). The grid has no heartbeat, so the recorder may simply have idled. Watch the first entry after launch on the phone.
- **P6-12, an invisible animation once ran for minutes.** In `testRestore-solid-dark`, XCTest waited 4 × 60 s for "App animations complete" while the screen didn't change. The bar's spinner had stopped (`R6-restore-dark-spinner.png`). Two re-runs were clean. A never-ending animation costs battery, so give Energy a look in Instruments on the phone.
- **P6-13, launch time on the simulator.**
  - From the icon to the welcome's first frame takes about 140 frames (2.3 s) on a repeat launch, and about 166 frames (2.8 s) on a fresh install. Then the welcome fades in over 7 frames. See `R6-welcome-launch.png` and `R6-firstrun-welcome-src.png`.
  - `LaunchTests` on the phone is what counts; it was unchanged at 8b0bc24.
- **The passcode sheet is light over Private.** With no Face ID enrolled, Unlock falls back to the system's passcode sheet, which is light. That's the system's.

## Round-5 items

| | Now |
|---|---|
| P5-01 the old page under "Load anyway" | **Fixed.** The message stays up with "Load anyway" dimmed while the bar spins (`R6-loadanyway.png`). |
| P5-02 the cut into a popup's tab | **Fixed.** The page slides out and the new tab slides in (`R6-popup-open-glass-light.png`). See P6-07 for the bar. |
| P5-03 toasts that blink out | **Fixed.** The App Store toast fades over about 10 frames (`R6-appstore-toast-hide.png`, 1019–1029). |
| P5-04 the shelf before the keyboard | **Fixed in both places.** On a cold blank tab the shelf fades in as the keyboard rises (`R6-starred-cold-idx.png`, #174–#186). On + it no longer draws over the grid (`R6-starred-newtab.png`, 1344–1350). |
| P5-06 Edit sheet's star filling in | **Fixed.** The star is filled from the sheet's first frame (`R6-edit-sheet.png`). |
| P5-07 the label before the star | **Fixed.** The word and the star change on the same frame (`R6-save-star.png`, 1714). |
| P5-05, P5-08, P5-09, P5-11 | Not re-checked this round (`testSavedList` wasn't run). |
| P5-10 first Share slow | Still there as the first share-sheet cost; see P6-05. |

## Regressions

None.
- **Every core-loop touch matches its round-5 twin within a frame** in glass light and solid dark: field, cancel by tap, cancel by swipe, flicks, scroll, tabs, bar sideways, bar up and restore. Details:
  - The tap is L+1, apart from two L+2 readings in testField. Those are recorder jitter: cancel-by-tap's two address taps are L+1 in the same build.
  - Cancel is L+1.
  - Flicks and swipes are L+1 with the same hold profiles.
  - The grid is L+1 to L+2.
  - Scroll answers the finger after 2 to 3 frames, with the same coast.
- **The apparent cancel-swipe break was the timestamps.** `testCancelSwipe-glass-light` at first looked as if the field vanished when the finger reached the keyboard. In decode order (`R6-cancelswipe-idx.png`), bar and keyboard follow the finger down together, as before.
- **Unchanged:** the cold blank tab's field-then-keyboard wait (about 57 frames) and the restore fade-in.

## The TestFlight list, walked as a friend

1. **Ads and the shield.**
   - CNN scrolled with no display ads; its consent banner stays, as in Safari (`R6-ads-cnn-contact.png`).
   - "Turn Off Blocking" and "Turn On Blocking" each reload the page (`R6-shieldoff-contact.png`).
   - On a fresh install, typing "theverge.com" opened the site with no ads in view (`R6-firstrun-ov.png`).
2. **Clean links.** All four land on the real address, shown in full in the field (`R6-cleanlinks-fields.png`):
   - Google's result opens `en.wikipedia.org/wiki/Swift_(programming…`, with no `utm_source`;
   - Facebook's opens `example.org`, with no `fbclid`;
   - Reddit's opens `github.com/swiftlang/swift`, with no `utm_source`;
   - the AMP link opens `theguardian.com/world/2026/sep/28/…`. The 404 is from my made-up path.
3. **App Store and popups.**
   - Both App Store jumps were stopped with "Stopped a jump to the App Store.", and Field stayed in front.
   - "Popup blocked · Open" opens the popup in a new tab that slides in.
4. **Eight tabs, the grid, a swipe, then force-quit.**
   - Eight tabs were opened by hand from +, and one was swiped away.
   - Then home and a force-quit. On relaunch the tab last viewed fades in over the launch screen, and the grid has 7 cards. The same holds in both looks (`R6-relaunch-idx.png`, `R6-tabsbyhand-dark-grid.png`; `CARDS AFTER RESTORE: 7`).
5. **Star, a folder, Read later.**
   - The keyboard rides the sheet up for the new folder, and "Recipes" becomes the chosen chip.
   - The star changes as one.
   - Saved shows "Read later 1" and the folder (`R6-savefolder-ov.png`).
6. **Capture Page.**
   - PDF and Image each come out as "127.0.0.1 – The Hedgerow Ledger", PDF document and PNG image, in the share sheet, in both everyday and Private (`R6-capture-ov.png`).
   - Full Page in the screenshot editor needs the phone.
7. **Private.** See the next section.

## New features on video

**Private:**
- **Enter.** The slide is one motion: the everyday grid goes left, dims, and the dark side comes in from the right, with the switch's lift riding the same spring (`R6-private-enter-src.png`). The exception is P6-01's field.
- **Drag.** Both grids follow the finger 1:1 and land on release (`R6-private-drag-src.png`).
- **Lock.** Leaving and coming back shows "Private is locked." with Unlock and "Your tabs". Face ID's glyph shows, then the shade fades over about 6 frames onto the grid as it was left (`R6-faceid-unlock.png`).
- **App switcher.** The card is the cover, with no keyboard and no page (`R6-private-switcher-ov.png`, 2130–2370), and it shrinks home as the cover (1800).
- **Wipe.** "When you leave: Wipe" brings back an empty session with the welcome and the field (`R6-private-wipe-reenter-src.png`).
- **The limits list.** It is dark and readable, from Settings and from the welcome (`R6-settings-light-idx.png`, #780 onward).
- **A restored tab's first page is blocked** (`testFirstPageBlocked` passed).

**Tidy:**
- The button opens the sheet, which streams ("Reading 13 tabs") and then lists the groups: Loaf Sourdough, Gmail, Google Travel and r/thinkpad (`R6-sections-ov.png`).
- Apply slides the sheet down while every card glides to its section, in one motion, and Undo glides them back (`R6-tidy-apply-src.png`).
- Ungroup glides the group's cards to the loose section while the header fades and the next section moves up (`R6-ungroup-src.png`).
- The header menu reads Rename, Add Similar Tabs, Ungroup.

**The stale banner:**
- It reads "3 tabs untouched for 2 weeks, 1 duplicate", with Review and Close.
- Review's sheet lists the 4 tabs with "Close 4 tabs".
- Close takes them away with "Closed 4 tabs · Undo", and Undo brings all 13 back with the banner (`R6-stale-idx.png`, `R6-stale-undo-banner.png`, `R6-groupmenu2-end.png`).

**Settings:**
- "Tabs untouched for" (1 week, 2 weeks, 1 month) sits above Private.
- Private has "When you leave" (Lock or Wipe, with a line that changes with it), "Wipe when away for", and "What Private can't do".
- Both looks are clean (`R6-settings-private-light.png`, `R6-settings-dark-idx.png`).

**First run:**
- After the launch screen, the welcome fades in.
- Continue stays disabled until a look is chosen, and then the field and keyboard are up on a blank page.
- A typed site loads with the spinner in the bar (`R6-firstrun-launch.png`, `R6-firstrun-welcome-src.png`, `R6-firstrun-ov.png`).

## What is good, so keep it

Everything on polish-5's list still holds, and this round adds:
- **The Private slide:** one spring, no crossfade, no second step; dragging tracks the finger. Leaving is the same motion reversed.
- **The lock and cover:** they are up before the switcher's snapshot and come down with a short fade after Face ID. Nothing private shows in the switcher.
- **Tidy's motion:** Apply, Undo and Ungroup move each card as the same object (motion.md principle 2), and the sheet leaves in the same timeline.
- **Bulk close:** stale Close with one Undo for all; the banner comes back with them.
- **Clean links:** every wrapper on the friends' list is unwrapped, and its tracking parameters are gone.
- **Restore after a force-quit:** the right tab, under the right picture, then the live page.
- **Round 5's fixes all landed cleanly:** Load anyway, the popup's slide, toasts that fade, and the shelf that rides in with the keyboard.

## For the phone, after P6-01 and P6-02

- The first Capture Page after launch (P6-05) and the first Share (P5-10).
- The first entry into Private after launch: does it start at once (P6-11)?
- Side + volume up on a long page: Full Page in the screenshot editor. In Private it should be missing (capture.md, "Checks on the phone").
- The Tidy model on a phone with Apple Intelligence; the simulator only runs the rules.
