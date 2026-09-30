# Wiring Capture into the browser

Capture's own files are done and tested (`Field/Capture/`, `FieldTests/Capture*Tests.swift`). This file lists the lines to add to the frozen files. Line numbers are from the files as they stood on 2026-09-30.

What `Field/Capture` gives you:

- `Capture(page:announce:)` is the one object. It must be kept alive, because the scene's screenshot service holds its delegate weakly.
- `capture.menu(presenter:source:)` returns "Capture Page" with **PDF** and **Image** under it. It returns nil when there's nothing to capture (a blank tab, an unpainted page or a failed load).
- `capture.attach(to:)` makes the scene's system screenshot offer **Full Page**.
- `capture.isPrivate` is the private flag (see 4).

## 1. The object: `Field/Browser/Browser.swift`

```swift
// property, under `let toaster = Toaster()` (line 13)
/// The whole page, as a file to share or the screenshot's Full Page (Field/Capture).
let capture: Capture

// init (line 33), first line; `toaster` is initialised inline, so it's there
capture = Capture(page: { nil }, announce: { [toaster] in toaster.show($0) })

// init, after `tabs.finished = …` (line 45), once `self` is whole
capture.page = { [weak self] in self?.tab }
```

## 2. "Capture Page" on the address's long press: `Field/Bar/FieldSurface.swift`

In `addressMenu()` (line 325), in the same inline group as Copy and Share…:

```swift
let passing = UIMenu(options: .displayInline, children: [
    UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in Guarded.copy(url) },
    UIAction(title: "Share…", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.share(url) },
] + [browser.capture.menu(presenter: self, source: surface.bar.address)].compactMap { $0 })
```

The menu is already `UIDeferredMenuElement.uncached`, so the item appears and disappears with the page and picks up the private subtitle each time it opens.

## 3. The system screenshot's "Full Page": `FieldSurface.swift`

In `viewDidAppear(_:)` (line 237), after `warmSoon()`:

```swift
if let scene = view.window?.windowScene { browser.capture.attach(to: scene) }
```

## 4. The private flag, for the private track

```swift
browser.capture.isPrivate = { [weak browser] in browser?.<the private space is on screen> ?? false }
```

When it returns true:

- The screenshot editor gets no Full Page. The ordinary screenshot of the screen still happens; iOS offers no way to stop it (PLAN.md, "What Field tells people it can't do").
- "Capture Page" still works, because it's the person's own choice. The menu shows the subtitle "A shared copy leaves Private." The file is written under `tmp/Capture/<uuid>/` and deleted when the share sheet closes. Anything left over (for example, the app was killed while the sheet was up) goes with the next capture, and Private's wipe purges temporary files anyway.

## What it does, in short

- **PDF (default):** `WKWebView.pdf()`, the whole document from what's already loaded, with no network. WebKit splits it into 14,400 pt pages, the PDF page limit.
- **Image:** drawn from that PDF off the main thread, at 2 px per point. It's capped at 16,384 px on the long side and 16.8 MP in all (64 MB as a bitmap), and a longer page is scaled down, never cut.
- **Names:** `<host> – <title>.pdf/.png`, where the host drops `www.` as the bar does, and the title is one line with no `/` or `:`, cut at 80 characters.
- **Progress:** past 300 ms it shows the toast "Capturing the page…". The toast stays up while the capture runs, then the share sheet comes up.
- **Known limits:**
  - Images a page lazy-loads that were never scrolled into view stay as placeholders, because nothing is fetched.
  - WebKit's PDF output fills CSS `mask-image` icons (Wikipedia's toolbar icons, for example) as solid squares. It's a WebKit limit of the PDF path, not something Field can fix.
- **Debug harness:** `-FieldCaptureHarness YES -FieldOpen <url>` (Debug builds only; add `-FieldCaptureCompare YES` for the tiling comparison). See `Field/Capture/CaptureHarness.swift`.

## Checks on the phone

The simulator can't trigger the system screenshot headless: `simctl io screenshot` doesn't go through `UIScreenshotService`. So check this on the phone once it's wired:

1. On a long page, scroll halfway and press side + volume up, then tap the thumbnail. **Full Page** appears, and it opens at the part that was on screen.
2. In Private, do the same. There's no Full Page tab.
3. Long-press the address and choose Capture Page › Image, then Save Image. It lands in Photos in one piece.
