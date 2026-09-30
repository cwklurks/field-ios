# Wiring Tidy into the browser (M6)

Tidy's own files are done and tested on their own. This file lists what to add to the frozen files (Field/Browser, Field/Tabs, Field/Bar), and where. Line numbers aren't given: `Stage.swift` and `TabGrid.swift` were changing while this was written (2026-09-30).

What's already there:

- **FieldKit**
  - `Session.Entry.group` / `.viewed`, `Session.Group`, `Session.Shape.groups`. These are additive: old files read as before (`SessionGroupTests`).
  - `Session.Grouping` (`applying`, `adding`, `sections`), `Shape.grouping` and `Shape.regrouped(_:)`.
  - `Stale.find` / `Stale.line`.
  - `Tidy.validate`, `merge`, `batches`, `render` and `similar`.
- **Field/Tidy**
  - `TidyEngine.shared`, whose `stream`, `suggest`, `similar` and `prewarm` all run off the main thread.
  - `TidySheets.show` / `showSimilar` / `showStale` / `prepareSoon`.
  - `TidyFlow` (Apply, then Undo), `StaleTabs`, `StaleBanner.hosted`, `TidyButton`.

## 1. The session: `Tab.swift`, `Tabs.swift`

Each tab keeps its group and when it was last on screen. `Tabs` keeps the group list.

```swift
// Tab.swift, beside `private(set) var title`
var group: UUID?
/// When it was last on screen (Session.Entry.viewed); nil until Field first shows it.
@ObservationIgnored var viewed: Date?

// Tab.init, inside `if let entry`
group = entry.group
viewed = entry.viewed

// Tab.entry
return Session.Entry(id: id, url: url?.absoluteString ?? "", title: title, interactionState: state,
                     group: group, viewed: viewed)

// Tab.show() (or wherever `seen = .now` is set): the stale rule's clock
viewed = .now
```

```swift
// Tabs.swift, beside `all`
private(set) var groups: [Session.Group] = []

// Tabs.init, after `all = list`
groups = shape.groups

// Tabs.shape
Session.Shape(tabs: all.map(\.entry), active: index, groups: groups)

// Tabs, new: what Tidy reads and sets
var grouping: Session.Grouping { shape.grouping }

func regroup(_ grouping: Session.Grouping) {
    for tab in all { tab.group = grouping.membership[tab.id] }
    groups = shape.regrouped(grouping).groups   // drops groups with no tabs
    stage?.regrouped()                          // see 2
    changed()
}
```

`close(_:)` needs no change. A closed tab keeps its `group` in the entry it pushes, and `reopen` puts it back in the group if that group still exists. The `Shape` initialiser drops a dangling group id, so a reopened tab is loose if its group has gone.

## 2. Grid sections: `GridLayout.swift`, `TabGrid.swift`

Groups show as sections: each group's name, then its cards in two columns, in `groups` order. The loose tabs come last, with no header, because that's where a new tab lands. With no groups the grid looks exactly as it does today.

- Order: `tabs.grouping.sections(tabs.all, id: \.id)` gives `[Section<Tab>]`, each with `group: Session.Group?` and `items: [Tab]`.
- `GridLayout` takes a list of section sizes in place of `count`, plus a `header: CGFloat = 34` above each named section (`Ramp.label`, `Palette.ink`, 4 pt inset like a card's title). `picture(i)` and `card(i)` keep a flat index across sections, so the Stage's open and close transitions still find card `i`.
- A header's long press opens a menu:
  - **Rename**: an alert with a text field. Set `groups[i].name`, then `changed()`.
  - **Add similar tabs**: see 4.
  - **Ungroup**: `tabs.regroup(grouping)` with that group's members removed from `membership`.
- **Regrouping** (Apply, Undo, Ungroup): each card glides to its new frame as the same view (`Motion.glide`). Headers fade in and out with `Motion.quick`. Nothing is rebuilt and nothing crossfades, per motion.md principle 2.

## 3. The Tidy button: `GridRow.swift`, `TabGrid.swift`, `BrowserView.swift`

```swift
// GridRow: just before Done
var tidy: CGRect {
    CGRect(x: done.minX - Self.button, y: top, width: Self.button, height: Self.button)
}
// GridRow.count: keep the middle clear of it
let inset = max(new.maxX, width - tidy.minX)

// TabGrid: a property, made in init and added to `row`
private lazy var tidyButton = TidyButton.make { [weak self] in self?.onTidy() }
var onTidy: () -> Void = {}

// TabGrid.layoutSubviews
tidyButton.frame = buttons.tidy
tidyButton.isHidden = !TidyButton.shows(tabs: tabs.all.count) || /* private */ tabs.store.file == nil
```

Use the private space's own check if it has one (`tabs.space != nil` after private.md step 1). **The button never shows over private tabs, so private tabs are never passed to Tidy.** As a second guard, the engine only sends http(s) pages.

The Stage (or wherever `onSaved` is wired):

```swift
grid.onTidy = { [tabs] in
    let infos = tabs.all.compactMap { tab in
        tab.url.map { TabInfo(id: tab.id, title: tab.title, url: $0) }
    }
    TidySheets.show(infos, flow: TidyFlow(
        grouping: { tabs.grouping },
        regroup: { tabs.regroup($0) },
        toast: { tabs.offer($0, $1) }       // "Grouped 18 tabs · Undo"
    ))
}
```

Prewarm when the grid starts to open, so the tap waits for nothing:

```swift
// Stage.openGrid(), first line
TidyEngine.shared.prewarm()
```

Build the sheet ahead of time, as Settings and Saved are (`BrowserView`, beside `SavedSheets.prepareSoon`):

```swift
TidySheets.prepareSoon { browser.busy }   // the same `busy` closure the others use
```

On the simulator the sheet starts moving on **frame 2** after the tap (`FrameWatch` in the harness).

## 4. "Add similar tabs"

From a group header's menu:

```swift
let members = section.items.compactMap(info)                       // info(tab) -> TabInfo?
let loose = tabs.all.filter { $0.group == nil }.compactMap(info)
TidySheets.showSimilar(to: group, members: members, among: loose, flow: sameFlowAsAbove)
```

The sheet lists the tabs it found, all checked. **Add** joins the checked ones to the group, and the toast reads "Added 3 tabs to Lisbon trip · Undo".

## 5. The stale banner: `TabGrid.swift`

When the grid opens, and not while it scrolls:

```swift
let found = StaleTabs.find(tabs.all.map(\.entry), current: tabs.current.id)
if let line = StaleTabs.line(found) {
    banner = StaleBanner.hosted(line: line, onReview: review, onClose: { close(found.all) })
}
```

- **Placement**: the banner sits at the top of the scroll content, above the first section, 16 pt margins. The layout's `top` grows by its height plus 12. It scrolls with the cards.
- **Review**: `TidySheets.showStale(infos(for: found.all), line: line) { ids in close(ids) }`.
- **Close**: close each tab with `tabs.close(_:)`, which pushes it onto Recently Closed. Then `tabs.offer("Closed \(n) tabs", .init(title: "Undo") { for _ in 0..<n { tabs.reopen() } })`.
- **`RecentlyClosed` holds 20.** Closing more than 20 stale tabs at once drops the oldest from it. Raise the cap in `Tabs` to 100, or close at most 20 at a time.
- The banner disappears as soon as nothing is stale. Nothing is ever closed without a tap.

## 6. Settings

`UserDefaults "staleDays"`: 7, 14 (the default) or 30. A row in Settings, "Tabs untouched for", with those three choices. `StaleTabs.days` reads it.

## The fallback

With no model (an iPhone 11 to 15, Apple Intelligence off, an unsupported language, or the simulator), FieldKit's rules run: same site first, then clustering at the existing 0.5 cut. What the rules compare changed. Whole-title sentence vectors are replaced by the **nouns of the title with the site's suffix cut, as averaged word vectors** (`TidyVectors`). The table shows the share of grouped pairs that were right, on two sets of realistic tabs:

| | set 1 (21 tabs) | set 2 (18 tabs) |
|---|---|---|
| sentence vectors of "title — host" (before) | 19% | 45% |
| nouns as word vectors (now) | 88% | 77% |

**Known limit:** the same-site pass uses `GuardRules.site(of:)`, the registrable domain. So Gmail joins Google Flights as "Google", and r/thinkpad joins r/Breadit as "Reddit". Passing the host in place of the site would split both. Worth trying on the phone.

## Checking it

- **The flow:** `-FieldTidyHarness YES [-FieldTidyEngine model|rules|script]` runs the flow over a stand-in grid (Field/Tidy/TidyHarness.swift). It reports the model's state and prints the groups.
- **The model:** Foundation Models doesn't run in the iOS 27 simulator on this Mac. It reports `available` but `contextSize` is 0, and every request fails with `ModelManagerError 1026`. The engine falls back to the rules and says so. Check on the phone.
