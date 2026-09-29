# Motion and polish spec

Frame-drop budgets (PLAN.md, "Smooth") are necessary but not enough. On 2026-09-27 the M1 build passed them and still felt laggy on the user's iPhone. Every UI change is checked against this file, on video.

## Principles

1. **Respond on the next frame.** A touch changes something on screen within one frame: a press state, the start of a move. Never wait for the system (the keyboard, a web view, a notification) before showing a response. Hide system latency behind motion that has already started.
2. **One object, one continuous motion.** When something turns into something else (the bar into the field, a tab into the grid), it is *the same view* changing shape and position. Never crossfade two copies: no frame may show two addresses, two bars or ghosted text.
3. **Move with the keyboard, not after it.** Anything attached to the keyboard follows its frame on every frame, opening, closing and during an interactive swipe down, with the keyboard's own curve. Nothing waits for the keyboard to finish and then catches up.
4. **Everything is interruptible and follows the finger.** A gesture mid-animation takes over from where things are. On release the spring starts with the finger's velocity. Swipe-to-dismiss tracks the finger 1:1.
5. **No stepwise sequences.** A transition is one timeline, not "A finishes, then B starts".
6. **Colour follows what's under it.** Glass samples the content directly under the bar, not the page's background colour.
7. **Only the three curves** (glide, settle, quick), or the keyboard's own curve when attached to the keyboard. Reduce Motion becomes the 0.14 s fade.

## The core interactions

| Interaction | Must look like |
|---|---|
| **Tap the address** | The next frame shows the bar reacting: it starts widening into the field shape. As the keyboard rises, the same surface rides its top edge and finishes becoming the field. The address is fully selected. Suggestions grow out of the same surface. |
| **Cancel** (tap outside, or swipe down) | The field shrinks back into the bar *while* the keyboard goes down, attached to its top edge, and lands in the bar's place as the keyboard finishes. Swipe down is interactive: bar and keyboard follow the finger together. |
| **Go** | The field becomes the bar showing the new host in the same motion, and the page's loading starts at once. |
| **Scroll** | The bar shrinks and grows with the scroll, 1:1, and settles with the finger's velocity. (Already passes: 0 hitches on device.) |
| **Tabs (M2)** | The tab grid opens by shrinking the live page into its own card (same object), and closes by growing the chosen card into the page. Swiping the bar sideways moves the pages with the finger. |

## How to check it: the video loop

Tests pass or fail frames; video shows choreography. After any UI change:

1. Boot the simulator headless. Start `xcrun simctl io <device> recordVideo --codec h264 <file>.mp4`, drive the interaction with a UI test or a small XCUITest script, then stop the recording with SIGINT.
2. Pull frames with ffmpeg (`-vf fps=30,crop=…,scale=…,tile=8x3`) and look at them.
   - Reject any frame showing two copies of something, a pause after a touch, or a sequence where the motion should be continuous.
   - Count frames from the touch to the first visible change: it must be 1.
3. Keep the FieldPerf tests green: frame-drop budgets still apply.
4. Save before-and-after strips in the scratchpad and cite them in the report.

The simulator runs at 60 Hz and its keyboard is lighter than the phone's, so the phone gets a final check after a batch of work, not after each change.
