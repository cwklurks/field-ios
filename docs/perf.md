# Measuring smoothness

"Smooth" in [PLAN.md](PLAN.md) is a set of budgets, not a feeling. This page covers what the `FieldPerf` tests measure, how to run them, and how to read the results. Only an iPhone 17 running a Release build counts against the budgets. Simulator numbers only show that the harness works and flag big regressions.

## Budgets

| Interaction | Budget | Test (`FieldPerfTests/…`) | Metric |
|---|---|---|---|
| Cold launch, first frame | 400 ms | `LaunchTests/testColdLaunch` | `XCTApplicationLaunchMetric` |
| Cold launch, field accepts typing | 500 ms | `LaunchTests/testColdLaunch` | `XCTApplicationLaunchMetric(waitUntilResponsive: true)`, a stand-in (below) |
| Scrolling a long page while the bar shrinks and grows, glass and solid | under 2 ms/s of hitch time | `ScrollTests/testScrollGlass`, `testScrollSolid` | `XCTHitchMetric`; also `bar.collapse`, `bar.expand` and UIKit's scroll signposts |
| Opening the field | under 2 ms/s of hitch time | `InputTests/testOpenField` | `XCTHitchMetric`; also the `field.open` signpost |
| A keystroke (suggestions on screen) | 8.3 ms, one frame at 120 Hz, for the slowest key | `InputTests/testKeystroke` | the `field.keystroke` signpost |
| Typing a word | under 2 ms/s of hitch time | `InputTests/testTypingHitches` | `XCTHitchMetric` |
| The welcome choice | under 2 ms/s of hitch time | `WelcomeTests/testChoose` | `XCTHitchMetric`; also the `welcome.choose` signpost |

Hitch time is the time frames arrive late, divided by the length of the interaction. Apple rates under 5 ms/s as good, 5–10 as a warning and over 10 as critical; our budget is stricter.

The rows without a budget (the signpost durations) are there to explain a missed budget, not to pass or fail.

On a device, XCTest also reports frame rate and hitches inside each animation interval (`bar.collapse`, `bar.expand`, `field.open`, `welcome.choose` and UIKit's `Scroll_DraggingAndDeceleration`), because the app begins them with `beginAnimationInterval`. Those catch hitches that `XCTHitchMetric` misses: on the iPhone 17, `field.open` had a 16.7 ms hitch in two of five iterations while `XCTHitchMetric` reported 0. So each interaction is held to 2 ms/s on both, as separate "hitch time, <interval>" rows.

## Running

You need Xcode 27, `xcodegen`, `jq` and `uv`.

**All the tests, with a table of results:**

```sh
scripts/perf/run.sh "iPhone 17e"                 # a simulator, by name
scripts/perf/run.sh <device-udid>                # the iPhone (xcrun devicectl list devices)
scripts/perf/run.sh <device-udid> ScrollTests    # some tests only
```

It builds the `FieldPerf` scheme (Release) into `build/perf` and runs it. It then prints each interaction's measurement next to its budget, with the date, device and build above the table. It also keeps the `.xcresult`, the log and the table as TSV in `build/perf/results/`. On a device, a missed budget makes the script exit 1. A failed test does that on any destination.

The Result column also shows:

- **skipped: …**: the app doesn't have what the test needs yet, such as an accessibility identifier or `-FieldOpen`. The reason names it.
- **not reported**: the test ran, but the app never emitted that signpost, or never ended the interval.
- **n/a on simulator**: hitch metrics need a device.

**The ground truth for scrolling, on a device:**

```sh
scripts/perf/hitches.sh <device-udid>            # glass bar
scripts/perf/hitches.sh <device-udid> solid
```

This records an Instruments trace with the Animation Hitches template while `ScrollTests` runs. It then adds up the hitches that begin inside the test's own `scroll` signposts, which mark exactly the measured flings, and prints the hitch time per second. The trace stays in `build/perf/traces/`. When this and `XCTHitchMetric` disagree, trust this.

**Where the time goes, on a device:**

```sh
scripts/perf/profile.sh <device-udid>                          # InputTests/testKeystroke
scripts/perf/profile.sh <device-udid> InputTests/testOpenField
```

This records a Time Profiler trace, with the app's signposts alongside, while one test runs. The trace stays in `build/perf/traces/`. In Instruments, select a `field.keystroke` interval, set it as the inspection range, and read Field's main thread in the call tree.

**Before a device run:**

- Developer Mode is on.
- The phone is unlocked and plugged in, with Auto-Lock set to Never (Settings › Display & Brightness). A phone that locks mid-run stalls xcodebuild; the scripts refuse to start on a locked phone.
- Low Power Mode is off.
- The phone isn't warm.

Close other apps. Run twice, and use the second run if the first included a fresh install.

## How the tests work

- **The fixture.** The scroll test needs a long, realistic page and no internet. So the test runner serves one itself: `Fixture.swift` is a small `NWListener` HTTP server bound to 127.0.0.1, serving `Article.swift`, about 12,500 words laid out like a news site with a sticky blurred header and 16 SVG figures. The app opens it with `-FieldOpen http://127.0.0.1:<port>/article`. Loopback works because on the simulator the runner and the app are both Mac processes, and on a device both are iPhone processes. Loopback is exempt from local network privacy, so no prompt appears. If the server can't start or doesn't answer its own request, the test passes the same page as a `data:` URL. Its figures don't load then, but they keep their size.
- **One interaction per iteration.** `XCTOSSignpostMetric` reports only the *first* matching interval in each iteration. (Calibrated: intervals of 40, 10 and 20 ms were reported as 41–50 ms.) So the keystroke test types one letter per iteration, and `run.sh` holds the slowest letter to the budget. XCTest runs each block once more than `iterationCount` and discards the first run.
- **Missing signposts don't fail.** If the app never emits a signpost, the metric is silently absent from the result bundle. `run.sh` marks it "not reported".
- **Launch.** XCTest terminates the app between launches, so each one starts a new process, with the system's caches warm (Apple calls it a warm launch; only a reboot makes a truly cold one). The responsive variant ends once the main thread takes input, which stands in for "the field accepts typing". For the exact time to the `launch.fieldReady` signpost, record with Instruments' App Launch template. On a simulator the XCTest launch numbers are inflated about fourfold by the test runner's launch machinery, so don't read them against the budget at all.
- **The welcome.** Choosing a look leaves the welcome up (Continue dismisses it), so each iteration relaunches with `-welcomed NO` and times a first choice, ending when the card reports itself selected.
- **Signposts.** `Field/Perf/Signpost.swift` names them. They use subsystem `com.connork.field`, category `PointsOfInterest`. The runner's own `scroll` signposts use subsystem `com.connork.field.perftests`.

## Reading an Animation Hitches trace

Open the trace from `build/perf/traces/` in Instruments (`open <file>.trace`).

1. **Find the interaction.** The os_signpost track shows the runner's `scroll` intervals and the app's intervals (`bar.collapse`, `field.open` and so on). Select a `scroll` interval and choose *Set Inspection Range* (or drag across the timeline) so every detail pane covers only that stretch.
2. **Hitches track.** Each hitch is a bar whose length is how late the frame was. The detail pane lists every hitch with its **Hitch Duration**, **Hitch Type** and a description. The summary gives the total and the hitch time ratio for the range.
3. **What kind of hitch:**
   - **Commit** (the app's main thread was late handing over the frame): layout, drawing, text or image decoding, or our own work. Expand the process's main thread, or add the Time Profiler, to see what ran.
   - **Render** (the render server was late): expensive effects, such as blurs, masks, shadows without a path and offscreen passes. Liquid Glass lives here, so compare glass with solid.
   - **GPU**: too much to draw; usually large or many layers.
4. **Frame lifetimes.** Expanding a hitch shows its frame's path: input, commit, render, GPU and display. The widest stage is the one to fix.
5. **Compare.** The same trace for glass and solid, or before and after a change, shows whether a fix moved the ratio.

## Results

Simulator rows only show the harness working; they don't count against the budgets. "Not built yet" means the test skipped because the app doesn't have that interaction yet.

<!-- results -->

**2026-09-26 14:06, iPhone 17 (iOS 27.0), Release, uncommitted tree. The second of two runs; the first failed to launch the test runner after installing it.** Result bundle `build/perf/results/2026-09-26-140015-device.xcresult`.

| Interaction | Measured | Budget | Result |
|---|---|---|---|
| Cold launch, first frame | 409 ms (392–418) | 400 ms | FAIL |
| Cold launch, ready for input | 606 ms (581–646) | 500 ms | FAIL |
| Scroll, glass bar, hitch time (`XCTHitchMetric`; scrolling; `bar.collapse`; `bar.expand`) | 0; 0; 0; 0 ms/s | 2 ms/s | pass |
| Scroll, solid bar, hitch time (same four) | 0; 0; 0; 0 ms/s | 2 ms/s | pass |
| Scroll, `bar.collapse` and `bar.expand` | glass 104 and 106 ms, solid 108 and 103 ms | none | |
| Scroll, frame rate while scrolling | glass 85.3 fps, solid 85.7 fps | none | ProMotion picks the rate. No frame missed its deadline. |
| Open the field, `field.open` | 465 ms | none | |
| Open the field, hitch time (`XCTHitchMetric`) | 0 ms/s | 2 ms/s | pass |
| Open the field, hitch time in `field.open` | 14.7 ms/s: one 16.7 ms hitch in iterations 1 and 2 (36.7 ms/s each), none in 3–5 | 2 ms/s | FAIL |
| Keystroke, `field.keystroke` | slowest 18.8 ms (the first letter); the others 9.5, 10, 10, 11, 9 ms | 8.3 ms | FAIL |
| Type a word, hitch time | 0 ms/s | 2 ms/s | pass |
| Welcome choice, `welcome.choose` | 455 ms | none | |
| Welcome choice, hitch time (`XCTHitchMetric`; in `welcome.choose`) | 0; 0 ms/s | 2 ms/s | pass |

**2026-09-26, iPhone 17e simulator (iOS 27.0), Release, uncommitted tree. SIMULATOR: does not count against the budgets.** The simulator runs at 60 Hz and reports no hitch data.

| Interaction | Measured | Budget | Note |
|---|---|---|---|
| Cold launch, first frame | 2433 ms (XCTest) | 400 ms | Inflated by XCTest on the simulator. Launched with `simctl`, `launch.firstFrame` came about 670 ms after the request. |
| Cold launch, ready for input | 3565 ms (XCTest) | 500 ms | Measured before `launch.fieldReady` moved to first responder, when it fired about 490 ms after the first frame, at `keyboardDidShow`. Not re-measured since. |
| Open the field, `field.open` | 461 ms | none | Ends once the keyboard is up (`keyboardDidShow`), so it's mostly the keyboard animation. |
| Open the field, hitch time | n/a on simulator | 2 ms/s | |
| Keystroke, `field.keystroke` | slowest 22.8 ms, avg 9.0 | 8.3 ms | Rerun at 13:14 after the omnibox fixes. Letters after the first: 10.0, 22.8, 5.1, 5.1, 5.9 and 4.8 ms. The two slow ones happen once per process: the first list appearing, then the first key over an inline completion. `scripts/perf/profile.sh` records where the time goes on the phone. |
| Type a word, hitch time | n/a on simulator | 2 ms/s | |
| Welcome choice, `welcome.choose` | 451 ms | none | The length of the selection spring. |
| Welcome choice, hitch time | n/a on simulator | 2 ms/s | |
| Scroll, glass bar, hitch time | n/a on simulator | 2 ms/s | |
| Scroll, glass bar, `bar.collapse` | 130 ms | none | |
| Scroll, glass bar, `bar.expand` | 0.03 ms | none | Too short to be the animation: the first `bar.expand` in each iteration begins and ends at once. |
| Scroll, solid bar, hitch time | n/a on simulator | 2 ms/s | |
| Scroll, solid bar, `bar.collapse` | 130 ms | none | |
| Scroll, solid bar, `bar.expand` | 0.03 ms | none | As for glass. |
| Scrolling and deceleration, both looks | 2563 ms | none | UIKit's signpost, for the first fling in each iteration. |
