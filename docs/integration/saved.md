# Wiring Saved into the browser

Saved's own files are done and tested on their own. This file lists the lines to add to the frozen files, and where they go. Everything UIKit needs is already in `Field/Saved`:

- `SavedSheets.save(_:title:in:)` saves the page and puts up the Save sheet.
- `SavedSheets.showList(_:start:onOpen:)` puts up the list.
- `SavedSheets.prepareSoon(_:unless:)` builds both sheets ahead of the tap, as `SettingsSheet` does.
- `StarredShelf` is the starred grid as a child view controller for the rider.

Line numbers were taken from the files as they stood on 2026-09-29.

## 1. The store: `Field/Browser/Browser.swift`

```swift
// property, under `let history: HistoryStore`
let saved: SavedStore

// init, straight after `history = …`, in the same folder
saved = SavedStore(directory: URL.applicationSupportDirectory.appending(path: "Field", directoryHint: .isDirectory))

// init, after `tabs.openField = …`
tabs.finished = { [saved] in saved.opened($0) }

// start(), after `Task { await history.load() }`
Task { await saved.load() }

// start(), the protectedDataDidBecomeAvailable observer: capture both and retry both
) { [history, saved] _ in
    MainActor.assumeIsolated {
        if !history.isLoaded { Task { await history.load() } }
        if !saved.isLoaded { Task { await saved.load() } }
    }
}

// flush(), after `await history.flush()`
await saved.flush()
```

"Read later" is the list of saved pages that haven't been opened since they were saved. It needs every finished load, not only the ones started from Saved:

```swift
// Field/Browser/Tab.swift, beside `var committed`
/// A web page finished loading, at this address.
@ObservationIgnored var finished: (URL) -> Void = { _ in }

// Tab.swift, webView(_:didFinish:), after `history.visited(url, …)`
finished(url)

// Field/Browser/Tabs.swift, beside `var committed`
@ObservationIgnored var finished: (URL) -> Void = { _ in }

// Tabs.swift, wire(_:)
tab.finished = { [weak self] in self?.finished($0) }
```

## 2. "Save" on the bar's long press: `Field/Bar/Bar.swift` and `FieldSurface.swift`

The address becomes a `UIButton` with a menu. It isn't the primary action, so a tap still opens the field and only a long press shows the menu.

```swift
// BarContent, beside `var canReopen`
/// The address's long-press menu: whether the page is saved, and Save.
var isSaved: () -> Bool = { false }
var save: () -> Void = {}

// BarContent.init, after `address.accessibilityIdentifier = "bar.address"`
address.menu = UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] done in
    done(self?.addressMenu() ?? [])
}])

// BarContent, beside tabsMenu()
private func addressMenu() -> [UIMenuElement] {
    guard !blank else { return [] }
    let saved = isSaved()
    return [UIAction(title: saved ? "Edit Saved Page" : "Save",
                     image: UIImage(systemName: saved ? "bookmark.fill" : "bookmark")) { [weak self] _ in
        self?.save()
    }]
}
```

```swift
// FieldSurface.viewDidLoad, after `bar.canReopen = …`
bar.isSaved = { [weak self] in
    guard let self, let url = page.url else { return false }
    return browser.saved.contains(url)
}
bar.save = { [weak self] in
    guard let self, let url = page.url else { return }
    SavedSheets.save(url, title: page.title, in: browser.saved)
}
```

A page that's already saved gets the same sheet, holding what was chosen for it, so the choice can be changed or undone with Remove.

Check on video:
- The long press begins with the address's `touchDown`, which runs `press(true)` and `prepare()`. When the menu takes the touch, UIKit sends `touchCancel`, so `press(false)` puts the press state back. `prepare()` only readies the field, which the next tap uses.
- The pill (the shrunk bar) holds the same button, so the long press works there too.

## 3. Starred pages on a new tab: `Field/Bar/FieldSurface.swift`

The shelf sits in the rider, above the field. The rider stands on the keyboard, so the shelf moves with the keyboard on every frame. It shows only on a new tab's field while nothing is typed, and the suggestions take its place as soon as there are any.

```swift
// property, beside `private let rows`
private let starred: StarredShelf

// init, before `super.init`
starred = StarredShelf(store: browser.saved)

// viewDidLoad, after `rows.didMove(toParent: self)`
starred.install(in: self, rider: rider, above: Self.gap + Bar.height + 12)
starred.onOpen = { [weak self] in self?.go(to: $0) }
starred.onShowSaved = { [weak self] start in
    guard let self else { return }
    SavedSheets.showList(browser.saved, start: start) { [weak self] in self?.go(to: $0) }
}

// new, beside edited()
/// The starred shelf: a new tab's field with nothing offered yet.
private func showStarred() {
    starred.show(flow.phase == .field && page.url == nil && coordinator.omnibox.offers.isEmpty)
}
```

Call `showStarred()` in every place the rows' visibility is set, in the same animation block, so the two never both show:

| Where | Add |
|---|---|
| `showField(tapped:)`, in the `SurfaceMotion.animate(curve)` block that sets `rows.view.alpha = listed > 0 ? 1 : 0` (about line 731) | `showStarred()` |
| `restInField()`, after `rows.rootView = …` | `showStarred()` |
| `showBar(_:)`, next to `rows.view.alpha = 0` (about line 569) | `starred.show(false)`, outside the `if listed > 0` |
| `beginDragging()`, inside the scrubbed `UIView.animate`, next to `rows.view.alpha = 0` | `starred.view.alpha = 0` (the scrub moves it with the keyboard) |
| `springBack(on:)`, in its animate block | `showStarred()` |
| `edited()`, after `let offers = …` | `showStarred()` |

`StarredShelf.show` uses the quick curve from the current state, so a call arriving mid-fade is safe. Leave the shelf's `alpha` alone inside `stopDragging()`: `springBack` or `showBar` decides what happens to it.

Check on video: open the field on a new tab. The shelf should fade in as the field rises, then stay the same distance above the field while the keyboard is dragged down with a finger. It should fade out on the first keystroke that brings suggestions.

"Saved" and "N to read" at the bottom of the shelf open the list over the new tab. The keyboard goes down under the sheet. When the sheet goes, UIKit gives focus back to the field. Watch that return on video, because it's the one path where a sheet and the field's own close run together.

## 4. The list from the tab grid's row

It goes next to the gear, before +.

```swift
// Field/Tabs/GridRow.swift: a slot after Settings, and + after it
var saved: CGRect {
    CGRect(x: settings.maxX, y: top, width: Self.button, height: Self.button)
}

var new: CGRect {
    CGRect(x: saved.maxX, y: top, width: Self.button, height: Self.button)
}
```

`count` already starts after `new.maxX`. On a 402 pt wide screen it keeps 122 pt, enough for "99 Tabs".

```swift
// Field/Tabs/TabGrid.swift, properties
private let savedButton = UIButton(type: .system)
var onSaved: () -> Void = {}

// TabGrid.init, after the settings button is added to `row`
var mark = UIButton.Configuration.plain()
mark.image = UIImage(systemName: "bookmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: Ramp.row.size, weight: .medium))
mark.baseForegroundColor = Palette.UI.ink
savedButton.configuration = mark
savedButton.accessibilityLabel = "Saved"
savedButton.accessibilityIdentifier = "tabs.saved"
savedButton.addAction(UIAction { [weak self] _ in self?.onSaved() }, for: .primaryActionTriggered)
row.addSubview(savedButton)

// TabGrid.layoutSubviews, after `settings.frame = buttons.settings`
savedButton.frame = buttons.saved
```

```swift
// Field/Browser/Stage.swift: StageView, a property before `openSettings`, so the trailing closure still means Settings
var openSaved: () -> Void = {}
// StageView.makeUIView
stage.openSaved = openSaved
// Stage, beside `var openSettings`
var openSaved: () -> Void = {}
// Stage.makeGrid(), after `grid.onSettings = …`
grid.onSaved = { [weak self] in self?.openSaved() }
```

```swift
// Field/Browser/BrowserView.swift
StageView(tabs: browser.tabs, bar: browser.bar, openSaved: {
    SavedSheets.showList(browser.saved) { url in
        // Opened in the tab on screen, whose card grows into the page.
        browser.go(to: url)
        browser.hideTabs()
    }
}) {
    browser.settingsShown = true
    SettingsSheet.present { browser.settingsShown = false }
}

// BrowserView .onAppear, beside SettingsSheet.prepareSoon, with the same test for busy
SavedSheets.prepareSoon(browser.saved) {
    let scroll = browser.tab.web?.scrollView
    return browser.fieldOpen || scroll?.isTracking == true || scroll?.isDecelerating == true
}
```

`GridRowTests` needs one more test:

```swift
@Test func savedBetweenSettingsAndNewTab() {
    #expect(row.saved.minX == row.settings.maxX)
    #expect(row.new.minX == row.saved.maxX)
}
```

Also add `row.saved` to the list in `everyButtonIsAFingerWide`.

## 5. Removing the harness

- If a `SavedHarness.isOn` line was added to `Field/FieldApp.swift` for video checks, remove it. It's marked "remove at wiring".
- Delete `Field/Saved/SavedHarness.swift` and `FieldTests/SavedTourTests.swift`, which drives it.
- Delete `FieldPerfTests/SavedTour.swift` if it exists.
- Nothing else uses them. `-FieldSeedSaved N` stays: `SavedStore` reads it, and the perf tests can seed a library with it.

## 6. After wiring, on video

1. Long-press the bar, then Save. The sheet should start rising on the frame after the touch. The suggested folder should already be chosen, or slide into place while the sheet rises.
2. Open a new tab. The starred shelf should rise with the keyboard, and swiping the keyboard down should carry the shelf with it.
3. Open the tab grid, then Saved, then a page. The sheet should go down while the page's card grows into the page, in one motion.
4. Open Saved with `-FieldSeedSaved 500` and flick to the end and back.
