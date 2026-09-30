# Parallel tracks: M3, M4 and Release 1 prep

These tracks are built at the same time as the user tests M2 on their phone. The **interface files are frozen**: Field/Bar, Field/Omnibox, Field/Tabs, Field/Browser/{Stage,Tabs,BrowserView}.swift and FieldApp.swift. Only the orchestrator, or a polish agent it names, edits them.

Each track builds its part as **self-contained modules with a small integration API**. The orchestrator wires them into the frozen files afterwards, in one reviewed step. If you think the wiring needs more than the lines you'd hand over, message `main`.

## Tracks and ownership

| Track | Agent | Owns | Simulator | derivedDataPath |
|---|---|---|---|---|
| M3a: navigation guard | `guard` | FieldKit `Guard/`, its tests, `Field/Resources/Guard/` (rule tables), NOTICE additions | none (`swift test`) | FieldKit's `.build` |
| M3b: content blocking | `blocker` | `Field/Blocking/`, `scripts/lists/`, `Field/Resources/Lists/`, `FieldTests/Blocking*Tests.swift` | iPhone 18 Pro | `build/blocker` |
| M4: Saved | `saved` | FieldKit `Saved/`, `Field/Saved/`, `Field/Model/SavedStore.swift`, `FieldTests/Saved*Tests.swift` | iPhone Air | `build/saved` |
| Release 1 prep | `release` | `scripts/release/`, `Field/Settings/About*.swift`, `ExportOptions.plist`, `docs/release.md`, project.yml **version and archive settings only** | iPhone 17e | `build/release` |

Shared files:
- `project.yml`: ask `main` before adding targets, resources or settings. Resource folders under `Field/` are picked up by the synced folder automatically.
- `NOTICE.md`: append only.

## Rules for every track
- **Performance comes first**, per docs/PLAN.md "Smooth": nothing new on the main thread during launch, scrolling or typing. Measure it.
- **Privacy defaults**, per docs/PLAN.md: no network calls except those listed in your brief.
- Test-first for all logic.
- Headless simulators, by name; never `shutdown all`.
- Keep files compiling, since the session can end without warning.
- Never commit; the orchestrator commits per track after review.
- Wrap long commands in `perl -e 'alarm N; exec @ARGV'`. No xctrace.
