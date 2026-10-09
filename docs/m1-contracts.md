# M1 working contract

Four agents build M1 ("One good tab", see PLAN.md) at the same time. This file is how they avoid colliding. The orchestrator owns it; if something here is wrong, message `main` rather than working around it.

## Who owns what

Only edit files you own. If another agent's file doesn't compile, it is mid-edit: wait a minute and retry. If it's still broken after about 10 minutes, message `main`.

| Agent | Owns |
|---|---|
| **app** | `Field/` except the folders below, `FieldTests/` except `HistoryStoreTests.swift`, `project.yml`, `Field/Info.plist` |
| **omnibox** | `Field/Omnibox/`, `FieldTests/OmniboxTests.swift` (or more files named `Omnibox*Tests.swift`) |
| **kit** | `FieldKit/`, `Field/Model/`, `FieldTests/HistoryStoreTests.swift` |
| **perf** | `FieldPerfTests/`, `scripts/perf/`, `docs/perf.md` |
| orchestrator | `Field/Perf/Signpost.swift`, `docs/PLAN.md`, this file |

If you need a change in a file you don't own, message `main` with the exact change.

**Build isolation.** Each agent builds with its own `-derivedDataPath build/<agent>` and its own simulator:

| Agent | Simulator |
|---|---|
| app | iPhone 17 |
| omnibox | iPhone 18 Pro |
| kit | iPhone Air |
| perf | iPhone 17e |

Only `perf` uses the physical iPhone, and only after `main` says so. Wrap every long command in `perl -e 'alarm N; exec @ARGV'`. Never commit.

## Interfaces

Write the declaration with the final signature first, stub bodies are fine, so the others can compile against it. Then fill it in.

**kit → `Field/Model/HistoryStore.swift`**
```swift
@MainActor @Observable final class HistoryStore {
    init(directory: URL)                         // Application Support/Field; history.json inside
    private(set) var isLoaded: Bool              // false until a load succeeds; saves are refused until then
    func load() async                            // file read and JSON decode off the main thread
    func suggestions(for text: String, limit: Int = 5) -> [Suggestion]   // synchronous; under 2 ms at 2,000 entries
    func completion(for text: String, among: [Suggestion]) -> (ending: String, suggestion: Suggestion)?
    func visited(_ url: URL, title: String)      // applies the results-page rule, then a debounced save
    func retitled(_ url: URL, _ title: String)
    func flush() async                           // called when the app goes to the background
}
```
Saves go through one serial actor, so an older snapshot never lands last. The results-page rule checks every `Engine` preset plus the custom template (UserDefaults `engine.custom`). A results page counts only as a visit to the engine's front page.

**kit → FieldKit `Destination`**
```swift
public enum Destination {
    /// What the field goes to: an address if the text is one, otherwise a search.
    public static func url(for text: String, engine: Engine, custom: String) -> URL?
}
```

**omnibox → `Field/Omnibox/OmniboxView.swift`**
```swift
struct OmniboxView: View {
    init(initial: URL?,                          // the page's address, shown selected; nil on a blank tab
         history: HistoryStore,
         onGo: @escaping (URL) -> Void,
         onCancel: @escaping () -> Void)
}
```
It fills the screen above the page, over a ground scrim at 74%. The field sits at the bottom, just above the keyboard, where the bar was, and suggestions stack above it. **app** presents it when the address is tapped and removes it on `onGo` or `onCancel`; it owns the transition from the bar into the field.

**app** owns `Field/Design/`, including the new `BarLook`:
```swift
enum BarLook: String, CaseIterable { case glass, solid }   // stored in UserDefaults "bar.look"
```

## Settings keys (UserDefaults)

These work as launch arguments too, e.g. `-welcomed YES`.

| Key | Meaning |
|---|---|
| `welcomed` | Bool; the welcome screen has been answered |
| `bar.look` | `glass` or `solid` |
| `engine` | `Engine.rawValue` |
| `engine.custom` | custom search template containing `%s` |
| `look` | existing Look (system, light, dark) |

Launch arguments, which work in Release too, since FieldPerf runs Release:
- `-FieldOpen <url>` (**app**) opens that URL in the tab at launch. The perf tests pass an `http://127.0.0.1:<port>/article` fixture served by the test runner, or a `data:` URL.
- `-FieldIncoming <url>` (**app**) hands that URL to `Arrivals` at launch, as a link from another app would come, for what no app can send (a `javascript:` link). Real links are opened with `XCUIApplication.open(_:)`.
- `-FieldSeedHistory <N>` (**kit**) fills HistoryStore with N synthetic places in memory. That process never reads or writes history.json.
- `-welcomed NO` lands in the argument domain and hides the app's own write. So the welcome hides from state the tap sets, not from re-reading the default.

Animation intervals (`bar.collapse`, `bar.expand`, `field.open`, `welcome.choose`) begin with `beginAnimationInterval`, so XCTest and Instruments attach hitch data to them. Every interval must end: XCTOSSignpostMetric reports only the first matching interval per iteration.

## Accessibility identifiers

These are the contract with FieldPerfTests; **app** and **omnibox** set them.

- **app:** `page`, `bar`, `bar.back`, `bar.address`, `bar.tabs`, `welcome.glass`, `welcome.solid`, `settings`
- **omnibox:** `field`, `suggestions`, `suggestion.0` … `suggestion.n`, `field.cancel` (the scrim, which calls `onCancel`)

## Signposts

`Field/Perf/Signpost.swift` defines the names. Emit them at exactly these points:

- `launch.firstFrame` (**app**): the first frame is on screen.
- `launch.fieldReady` (**omnibox**): the first time in the process that the field becomes first responder. At launch on a blank tab, **app** presents `OmniboxView(initial: nil, …)` with no animation.
- `page.firstPaint` (**app**): the page has painted.
- `field.open`: **app** calls `FieldOpening.begin()` at the tap on the address. **omnibox** calls `FieldOpening.end()` once the field is focused and the keyboard is up (`Field/Bar/FieldOpening.swift`).

## Bar and field surface

`Field/Bar/Surface.swift` (**app**) provides `.barSurface(shape)`. It draws glass or solid according to `bar.look`, and carries the morph IDs (`glassEffectID` or `matchedGeometryEffect`) inside the browser's `barMorph` namespace. **omnibox** puts it on the field's surface and draws no fill of its own. **app** wraps the bar and `OmniboxView` in the one `GlassEffectContainer`.
- `field.keystroke` (**omnibox**): from a text change until the suggestions are on screen.
- `bar.collapse` and `bar.expand` (**app**).
- `welcome.choose` (**app**).
