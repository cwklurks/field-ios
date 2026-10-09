# Bar motion review

Reviewed `main...HEAD` on `polish/bar-motion`. Fixes are in **13fa058**, `fix: harden bar motion interruptions`. No push or merge.

## Findings

All line references below are at the fix commit.

1. **P2, fixed: opening during a tab glide edited the outgoing tab.** `Field/Bar/FieldSurface.swift:509`, `Field/Browser/Stage.swift:389`. `heading(by:)` advertised the destination before `current` changed. A tap in that interval drafted `first.example` despite the bar saying `second.example`. The integration test failed on both the selected tab and draft. Opening now finishes the pending switch and redrafts. Touch-down alone still leaves the glide available for a finger to catch; only activation commits it. Fixed in **13fa058**.

2. **P2, fixed: the keyboard correction accepted animation contracts it could not reproduce.** `Field/Bar/KeyboardRide.swift:70`, `Field/Bar/FieldSurface.swift:781`. Different endpoints, horizontal movement, playback speed/time offset, repetition, autoreversal, a nonlinear time function, or an unsettled short duration were accepted, while the correction assumed a zero-ended vertical spring on an ordinary clock. Eight constructed variants failed the fallback test. The correction now rejects unsupported contracts and value types, validates finite parameters, ends at exactly zero, and converts the rider's start time into the surface's clock. Missing/unrecognized animations leave the original layout-guide behavior. A new close clears a previous release correction instead of adding the two together. Resignation, safe-area changes and rotation discard corrections; Reduce Motion skips the optional correction and its release translation. Fixed in **13fa058**.

3. **P2, fixed: an immediate Private tone change could leave earlier light glass behind.** `Field/Bar/SurfaceBackground.swift:100`. A tone fade retained outgoing glass until its delayed removal. Replacing the current glass without animation did not remove those earlier layers. Reasserting an already-dark target was worse: the equality guard did nothing, leaving the fade in progress. Both cases failed regression tests. An explicit nonanimated assignment now finishes an existing same-tone fade and removes all outgoing material. The delayed cleanup captures its view weakly. Fixed in **13fa058**.

4. **P3, fixed: outgoing glass kept the pill's corners during a field morph.** `Field/Bar/SurfaceBackground.swift:84`. While its frame resized with the surface, its corner configuration stayed at the old radius for the rest of the fade. The failing test changed the radius during a tone transition. All outgoing glass now follows the current surface radius. Fixed in **13fa058**.

5. **P3, left: brief low-contrast ink during the glass tone fade.** `Field/Bar/SurfaceView.swift:129`, `Field/Bar/SurfaceBackground.swift:125`. In the original B04 comparison, dark text precedes the lighter glass by about three frames. This is the implementer's acknowledged visual tradeoff, not a new state or lifetime failure. Left as requested rather than redesigning the tone choreography or crossfading foreground text.

## Checks and limits

- **Early reopen:** an integration test installs the known rider spring 80 ms into its close, inside the previously untested nine-frame window. Reopening produces a finite 0.14 s release from the current correction; closing again removes that release before applying another correction. Safe-area invalidation removes the correction. The recorded XCUITest also reopens smoothly, but its synthesized taps still do not establish physical-touch behavior in that early window.
- **P6-12 / ring lifetime:** the stop/start regression test checks that a restarted load survives the previous completion, the finished fade hides the ring and removes its infinite `turn` animation, and detaching it removes that animation. All pass without changing the ring implementation. The new fade adds at most its short visibility tail, not a new indefinite animation. This does not identify the historical P6-12 root cause or replace an on-device energy profile.
- **Other animation lifetime:** the new correction and release are finite, additive and removed on completion; neither changes the model-layer transform. The correction's stored closure holds the layer weakly. Outgoing glass cleanup is bounded and now weakly captured. No permanent animation/retain cycle was found in these changes.
- **Main actor:** the changed UIKit paths compile under the project's Swift 6 main-actor default. No new isolation errors were found. Existing unrelated build warnings remain.
- **Reduce Motion:** source audit confirms ring/glass use the existing quick 0.14 s path, bar expansion uses the existing reduced-motion helper, and the optional keyboard correction/release is disabled. A Reduce Motion-enabled video was not recorded; this is not a certification of every pre-existing motion path.
- **Accessibility:** eventless UIControl activation now has an integration regression test: the collapsed pill expands, then a second activation opens the field. Hidden end buttons retain the existing alpha-zero behavior. A full VoiceOver speech/focus session was not performed.
- **Remaining keyboard assumption:** even a recognized rider spring is not proof that the keyboard in the other process follows exactly the same trajectory and start time on a phone. Simulator recordings show no dip behind it. Unknown rider contracts now fall back safely, but the physical-device timing assumption remains a device check before release.

## Tests and evidence

Only **iPhone 17**, UDID `E0281095-1DCA-4D40-A8F4-E114854A2A58`, was used. Its installed runtime is **iOS 27.0**. All Xcode runs used `build/bar-review/DerivedData` inside this worktree, with parallel testing disabled. The requested minimum deployment target remains iOS 26.

- Full **Field scheme:** **356 Field tests in 60 suites**, then **233 FieldKit tests in 23 suites**, all passed. `unit-verified.log` and `unit-verified.xcresult` include normal xcodebuild completion with exit 0. Baseline was also checked: 347 + 233, both passed normally.
- Standalone **`cd FieldKit && swift test`: 233 tests in 23 suites**, passed with exit 0 (`fieldkit.log`).
- **FieldPerf Release:** InputTests **3/3**, ScrollTests **2/2**, TabsTests **4/4**, BarTour **4/4**, PrivateTour/testEnterLeave **1/1**. Run serially, with each BarTour method and PrivateTour recorded separately. All 14 requested tests passed, none skipped. Input/Scroll were also rerun on the final build after the last refinements; see the final logs below.
- The four substantive reproductions are in `regressions-red.log`, `glide-red.log`, `lifecycle-red.log`, and `interruptions.log`. Some deliberately failing focused xcodebuild processes stayed alive after their complete Swift Testing failure summary and were terminated. Successful full runs were allowed to finish, including the package tests.

Logs, result bundles, recordings and strips are under **`build/bar-review/`** (gitignored):

- `InputTests-final.log`, `ScrollTests-final.log`, `TabsTests.log`; matching result bundles.
- `BarTour-testOpenClose.mp4`, `BarTour-testOnPage.mp4`, `BarTour-testPillSwipe.mp4`, `BarTour-testReopenMidClose.mp4`.
- `PrivateTour-testEnterLeave.mp4`: Face ID enrollment state was 1; a match was sent at `FACE ID NOW`. The unlock and return to the page are visible.
- `strips/private-entry-final.png`: frame **1130** precedes the field; **1131** is its first visible frame, already dark glass with light ink. It stays dark through the rise. No light pill or later light-to-dark cut. The existing grid-row show-through during the initial rise remains.
- `strips/cancel-final.png` (1282–1305) and `strips/go-final.png` (2110–2133): one surface, above the simulator keyboard through dismissal, without a duplicated address.
- `strips/page-overview.png`, `strips/pill-swipe-overview.png`, `strips/reopen-final.png`: the pill returns to full-opacity text, the host changes with the tab glide, and the reopen remains continuous.

All six original `build/bar-polish/compare/B01..B05*.png` strips were inspected. They support the reported press, tab-host, close, glass and ring improvements. The visual tour tests mostly exercise interactions; their passing status alone is not visual proof, which is why the strips were inspected separately. No new device hitch/energy claim is made from the XCTest pass counts.

## Merge context and verdict

**Ready to merge with 13fa058 included.** No demonstrated correctness blocker remains in the reviewed branch. The phone-keyboard timing check is still required before treating B03 as device-validated.

The actual diffs of both neighboring local branches were inspected from this worktree:

- `polish/p6-nits` changes `Stage.flow(for:)`'s `announce` wiring. That is separate from this branch's carousel changes; no semantic conflict found.
- `feat/search-suggestions` adds `privately:` to both `Omnibox` constructors in `FieldSurface`. Preserve **both** closures. The tap-glide fix deliberately completes selection before creating the draft, so the suggestion coordinator receives the correct tab's address. This branch does not edit `AddressField.swift` or `BrowserView.swift`. After integration, check early reopen with a late suggestion response; that combined behavior cannot be certified from either branch alone.
- `FieldSurface` remains large. No broad extraction was attempted during a correctness review.
