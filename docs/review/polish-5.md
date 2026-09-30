# Polish review 5: M3 and M4 on video

Reviewed 2026-09-30, against [`docs/motion.md`](../motion.md) and [polish-3](polish-3.md) (with its round-4 check). The build was the FieldPerf scheme (Release), made from a clean `git archive` of e94ec1e ("feat: wire clean links, ad blocking and Saved into the app (M3, M4)") plus this round's `FieldPerfTests/CriticTour.swift`. It was recorded on the iPhone 17 simulator (60 Hz, headless).

## Method

The method is the same as in polish-3:
- One test per interaction, with touch marks on, over loopback pages that carry the 2 pt heartbeat.
- Frame numbers are indices in the video resampled to 60 fps. Strips labelled with decimals (`src.py`) use the source frames' own times × 60. "L" is the last frame with the touch ring.

What's new this round:
- **New tests in CriticTour**, one per M3/M4 interaction:
  - `testAddressMenu`: long press, dismiss, Share, Copy, then a plain tap.
  - `testSaveSheet`: Save, star, folder, Done, then Edit Saved Page closed by a swipe.
  - `testStarredCold` and `testStarredNewTab`: the shelf on a cold blank tab and on + from the grid.
  - `testSavedList`: from the grid through to opening a page. It covers search, Read later, a folder, a flick, and swipes both ways.
  - `testPopupToast`, `testAppStoreToast`, `testShieldToggle` and `testLoadAnyway`.
  - `testAds`, which scrolls a real site given by `CRITIC_URL`.
  - Two loopback pages, `/popup` and `/jump`, which both have the heartbeat.
- **Coverage.** 44 recordings, all in `critic/r5/`:
  - every new interaction in glass light, and most in solid dark too;
  - the core loop in glass light and solid dark (field, cancel by tap, cancel by swipe, flick, scroll, tabs, bar swipe sideways and up, cold blank, restore), plus tone in glass dark;
  - three real sites for blocking (CNN, AccuWeather, Daily Mail), and `GuardTour.testShieldOff` on CNN.
- **Comparison.** Every core-loop video was set against its round-4 twin in `critic/r4/`, touch by touch, with `an.py lifts`.
- **Where things are.**
  - Strips: `/tmp/field-review/critic/R5-*.png`, called `critic/` below.
  - Videos: `critic/r5/<test>-<look>-<mode>.mp4`.
- **Tooling.** `src.py` now selects frames by range and reads best-effort timestamps. It was failing on long ranges.
- **The recorder** worked first time. There was no "Host recording is already in progress", so the simulator didn't need a reboot.

Caveats:
- A blank tab has no heartbeat, so the recorder idles there, and frame counts on a cold blank tab are coarse.
- Another agent's simulator was busy on the same Mac (load average about 6.7). The first solid-dark `testScroll` showed dropped frames while coasting. Two re-runs were clean (`testScroll-solid-dark-run2`, `-run3`), so it is the host, not the app.
- 120 Hz, Reduce Motion and the phone's keyboard are not covered.

## New defects, most visible first

None is a blocker or a major.

### P5-01 · minor (top of the list) · "Load anyway" shows the previous page under the blocked address
**What's wrong:** tap "Load anyway" and the Trouble message is gone on the next frame. The page that was on screen *before* the blocked one comes back, while the bar says the blocked host and spins. It stays for as long as the network takes: 75 frames (1.25 s) here. Only then is it replaced.
- The screen reads as "that took me back", not as "loading".
- The message leaves as a hard cut.

The path is rarer than the core loop, but a blocked ad-click (a sponsored result going through an ad server) lands exactly here.
- **Evidence:**
  - `R5-loadanyway-glass-light.png`: the tap at 1769–1772; the article is back at 1773 under "pagead2.goo…dication.com".
  - `R5-loadanyway-after-glass-light.png`: still the article at 1842; the loaded page at 1854.
  - `R5-blocked-go-glass-light.png`: how the block arrived. There's a cut to the message at 1547.
- **Likely cause:** in `Tab.retry()`, the blocked branch sets `failure = nil` before calling `loadAnyway`. `BrowserView` drops `Trouble` on that change, and that exposes the web view, which still holds the last committed page. `didCommit` already clears `failure`, so keep the message up until then, perhaps with its button showing that it's working. `load(_:)` also clears `failure` up front, so "Try again" probably has the same flash; that wasn't checked.

### P5-02 · minor · "Popup blocked · Open" cuts to the new tab in one frame
**What's wrong:** tapping Open replaces the whole screen with the new tab between two frames. There's no motion, and the toast vanishes in the same cut.
- In dark mode this is a full-screen flip from the white test page to the dark blank tab: 78,000 changed pixels in one frame.
- Elsewhere a new tab arrives as one motion (+ in the grid grows the page; a starred tile rides the bar down). This is the only way into a tab that has no transition.
- **Evidence:** `R5-popup-open-glass-light.png` (1044 → 1050; the lift is 1049) and `R5-popup-open-solid-dark.png` (1034 → 1042).
- **Likely cause:** `Tab.popupBlocked` → `openTab` → `Tabs.newTab(url)`, which switches tabs with no Stage flight. Use the same flight that a new tab from the grid gets, or slide the new page in from the side as the bar swipe does.

### P5-03 · minor · Toasts arrive with motion but leave with a cut
**What's wrong:** "Stopped a jump to the App Store." rises and fades in over about 10 frames (721–731), which is right. When its time is up it is gone between two recorded frames (819.7 → 822.9). The recorder was taking frames every 50 ms there, so a fade on the settle curve would have shown. It happened for both toasts in the run (823 and 999).
- **Evidence:** `R5-appstore-toast-hide-src-glass-light.png`; the arrivals are in `R5-appstore-toast1-glass-light.png` and `R5-appstore-toast2-glass-light.png`.
- **Likely cause:** unconfirmed. `Toaster.hide()` does animate `text = nil`, but the removal transition isn't running. The `if let` sits directly in `Toast.body` with `.id(text)`, inside `BrowserView`'s ZStack. Try a stable container (for example, a `VStack` that always exists, with the capsule inside it) so the `.transition` has a parent to animate in. This is probably older than M3, but M3 makes toasts more frequent.

### P5-04 · minor · The starred shelf turns up before the keyboard, and over the grid on +
The shelf rides the keyboard well once both are moving (see "already good"). Its arrival is early, in two places:
- **On a cold blank tab**, the shelf appears at the bottom of the screen about 10 to 14 frames before the keyboard starts. It sits there with the field, then rides up. motion.md asks for it to fade in *as the field rises*.
  - `R5-cold-blank-src-glass-light.png`: the shelf at 563.7, the keyboard from about 574.
  - `R5-starred-cold-launch-src-glass-light.png` and `R5-starred-cold-rise-src-glass-light.png`: the shelf at 616.4, the keyboard from about 630.
- **On + from the grid**, the shelf's tiles and "Saved / 45 to read" are drawn over the fading grid for about 4 frames. For example, "E S G" sits over the Hedgerow Ledger card at 1111–1114, before the blank page covers the grid. This is the P1-15 residue (the field over the fading grid) with more in it now.
  - `R5-starred-newtab-glass-light.png`.
- **A smaller one:** on the first keystroke, the shelf fades out while the first suggestion row grows into the same place, and for one frame both are visible (1428, `R5-starred-type-glass-light.png`).

**Likely cause:** `showStarred()` runs in `restInField()` and in the `showField` animation, which fire before the keyboard's first frame. The quick fade then finishes before the rider moves. Tie the shelf's alpha to the rider's own rise, or start it on `keyboardWillShow`. On +, hold it until the blank page covers the grid.

### P5-05 · minor · With a row's swipe actions open, tapping another row opens that page
**What's wrong:** in Saved, row 1 was swiped open to show Move and Delete. A tap on row 4, meant to close them, opened row 4's page instead. Saved closed and the page loaded. On iOS, the first tap outside open swipe actions only closes them.
- **Evidence:** `R5-saved-tap-while-swiped-glass-light.png` (the tap at 3217, Saved going at 3224, the page at 3232). The first run's video was overwritten when the test was changed and re-run.
- **Likely cause:** `PageRow` is a `Button`. SwiftUI's List lets its tap through while another row's actions are open. Track the open row and swallow the tap, or use `.onTapGesture` with a check.

### P5-06 · minor · Edit Saved Page opens with its star still filling in
**What's wrong:** on a page that's already starred, the sheet rises showing an outline star next to "Starred". The star fills about 8 frames later, while the sheet is still rising.
- **Evidence:** `R5-edit-sheet-glass-light.png` (2516–2524).
- **Likely cause:** `SaveSheet.start()` sets `starred` in `onAppear`, and `.contentTransition(.symbolEffect(.replace))` animates that first change. Seed the state in `init`, or wrap the first assignment in a transaction with animations off.

### P5-07 · nit · Star: the label changes before the icon
**What's wrong:** on tapping Star, "Star" becomes "Starred" on the lift. For one frame the new word is clipped: 1724 shows "Star" with a ghosted "red". The star's icon shrinks and fills about 12 frames later (1738).
- **Evidence:** `R5-save-star-glass-light.png` (1716–1738).
- **Likely cause:** the text change is inside `withAnimation(.quick)`, so it crossfades inside a pill that's changing width, and `.replace` runs on its own, slower timeline. Change the label without animation, or use one timeline for both.

### P5-08 · nit · The swipe action "Move" reads as disabled
**What's wrong:** `Palette.faint` makes Move a pale grey pill with its label barely visible, beside a solid black Delete.
- **Evidence:** `R5-saved-swipe-glass-light.png` (3067 onward).
- **Likely cause:** `.tint(Palette.faint)` in `SavedView.list`. `Palette.muted`, as Star uses, would read as live.

### P5-09 · nit · Saved from the grid starts at L+6
**What's wrong:** the bookmark in the grid's row shows its press, and the sheet starts rising 6 frames after the lift (1102 → 1108). Settings from the gear was accepted at L+2 to L+4.
- **Evidence:** `R5-saved-open-glass-light.png`.
- **Likely cause:** `SavedSheets.showList` builds a new `Host` and `SavedView` on each tap. `prepareSoon` warms SwiftUI but doesn't keep the host, and the list builds 60 rows. Settings keeps its host.

### P5-10 · note · The first Share after install waited 2.3 s
**What's wrong:** in the first run on a fresh install, the menu closed after Share (2012–2020) and nothing happened for 2.3 s before the share sheet came up (2139). In later runs, glass light and solid dark, the sheet started 18 to 20 frames after the lift and grew from the address.
- **Evidence:** `R5-share-open-glass-light.png` and `R5-share-late-glass-light.png` (the first run), `R5-share-open-solid-dark.png`, and `critic/r5/testAddressMenu-glass-light-run2.mp4` (the lift at 1702, the sheet from 1720).
- **Likely cause:** the system finding share extensions the first time, which is slow on the simulator. Check it once on the phone after installing build 6. If it's slow there too, build a `UIActivityViewController` out of sight after launch, as the Saved sheets are prepared.

### P5-11 · nit · In dark mode, Settings' Segmented lift is hard to see
**What's wrong:** the lift now slides under the labels, and no label is covered (the zIndex fix works). In dark mode, though, the lift is a slightly darker pill on a dark track, and for the first 5 frames after a tap nothing looks selected (1145–1150).
- **Evidence:** `R5-segmented-dark-zoom.png`. Light mode is fine (`R5-segmented-light-zoom.png`).

Not flagged, because it's the system's own behaviour:
- The address menu's Liquid Glass morph, and the address leaving the bar while the menu is up.
- The menu closing 6 frames after a tap outside it.
- On a blank tab, a half drag of the keyboard that's let go closes the field, as it did in round 4 (the P3-02 behaviour).

## Regressions

None. Every core-loop touch in glass light and solid dark matches its round-4 twin within a frame, and the motion profiles after each lift match as well:
- The tap is L+1 in both looks.
- Cancel by tap is L+1 or L+2.
- Go, cancel with rows, full swipe and flicks show the same profiles as round 4.
- Scroll and flick are 1:1. The first solid-dark run's coasting drops were host load; two re-runs match round 4 exactly.
- Grid: open, choose, card swipe, ✕ and + keep the same response counts, L+1 or L+2.
- Bar sideways: the slow drag, throw and rubber band are as before.
- Bar up: the slow drag answered on frame 2 in glass light. In solid dark it answered on frame 8, where the finger sat almost still for the first 7 frames; see `R5-barswipe-updrag-solid-dark.png`. Round 4 only had glass light. Watch it on the phone.
- Cold blank: from the field's first frame to the keyboard's first move took 58 frames, against round 4's 57, measured the same way.
- Restore and tone: unchanged.

The new long-press menu on the address doesn't delay the tap. The press state shows at L+1 (`R5-menu-press-glass-light.png`), and a plain tap after using the menu opened the field at L+1.

## Blocking works

- **CNN, the same page with the switch on and off:** with blocking off, an ad slot is back above the CNN header. With blocking on, the header sits at the top of the page (`R5-cnn-shield-on-vs-off.png`). The switch's reload applied the change both ways (`critic/r5/testShieldOff-glass-light.mp4`).
- **Daily Mail and AccuWeather:** scrolled for about 40 s each, with no display ads and no empty ad boxes on screen (`R5-ads-dailymail-contact.png`, `R5-ads-accuweather-contact.png`, `R5-ads-cnn-contact.png`).
- **Caveat:** all three sites were showing their cookie consent. Sites serve fewer ads before consent, so the on/off difference on CNN is one slot, not a page full.
- **Cookie banners stay.** EasyList doesn't hide cookie banners, and Safari doesn't either, so that's not a defect.

## What is good, so keep it

Everything on polish-3's list still holds, and the new work adds these:

- **Address long press:** the address dims at L+1. The system's glass menu grows from the bar, with Save nearest the finger (`R5-menu-open-src-glass-light.png`). The menu goes back into the bar on a tap outside it or on a choice (`R5-menu-dismiss-src-glass-light.png`), and a tap still opens the field.
- **Save sheet:** it starts rising 2 frames after the menu starts to close (`R5-save-open-glass-light.png`) and sits at the height of its rows. Done slides it away (`R5-save-done-glass-light.png`), a swipe follows the finger down (`R5-edit-swipe-glass-light.png`), and the menu then reads "Edit Saved Page".
- **Starred shelf in the field:**
  - It rides the keyboard up (`R5-starred-cold-rise-src-glass-light.png`).
  - It follows the keyboard down under a finger, fading with the dim (`R5-starred-drag-glass-light.png`), and goes with the keyboard on release.
  - A tile answers at L+1: the field says "en.wikipedia.org" and rides down as the bar (`R5-starred-tile-open-glass-light.png`).
  - It looks right in both modes (`R5-starred-rest-glass-light.png`, `R5-starred-rest-solid-dark.png`).
- **Saved list:**
  - Search filters as you type (`R5-saved-search-glass-light.png`), and Clear brings the folders back (`R5-saved-clear-glass-light.png`).
  - Filters cut the list and slide the chip (`R5-saved-later-glass-light.png`).
  - Rows track the finger on a swipe (`R5-saved-swipe-glass-light.png`, `R5-saved-star-swipe-glass-light.png`).
  - Opening a page is one motion: the sheet goes down while the card grows into the page (`R5-saved-open-page-glass-light.png`).
  - The flick coasts continuously, and the list is clean in dark mode (`R5-saved-rest-solid-dark.png`).
- **Toasts:** "Popup blocked · Open" rises over the bar and sits clear of it in both looks (`R5-popup-toast-glass-light.png`, `R5-popup-toast-zoom-*.png`). Both App Store jumps were stopped, the toast came up each time, and Field stayed in front.
- **The shield switch:** "Turn Off Blocking on …" and "Turn On Blocking on …" reload the page, with nothing moving but the page's own reload (`R5-shield-off-src-glass-light.png`, `R5-shield-on-src-glass-light.png`).
- **A blocked page** says "Field's blocker stopped this page." with "Load anyway" (`R5-blocked-go-glass-light.png`).
- **Settings:** Segmented's lift slides under the labels and never covers one (`R5-segmented-light-zoom.png`). Appearance flips at L+1.

## Verdict

**Ship build 6 to TestFlight now.** There are no blockers, no majors and no regressions. The core loop the user will use a hundred times a day is frame for frame what round 4 approved, in both looks. The long-press menu leaves the tap alone. Saved, the shelf, the toasts and the shield all work on video, and blocking visibly removes ads on real sites.

What's left is eleven minors and nits, mostly at the edges of the new features:
- the stale page behind "Load anyway" (P5-01);
- the cut into a popup's tab (P5-02);
- toasts that blink out (P5-03);
- the shelf turning up early (P5-04).

They are all small and local. Take P5-01 to P5-04 in the next short round. The first three are one-place fixes, and P5-04 is the one the user will see on every new tab. On the phone, ask the user to watch two things: the first Share after installing (P5-10), and whether the new-tab shelf "pops" before the keyboard.
