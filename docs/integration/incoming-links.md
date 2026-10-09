# Links from other apps

A link tapped in Mail, Messages or Notes, once Field is the default browser (docs/release.md, "Default browser"). Until Apple grants the entitlement iOS sends web links to Safari, but everything below already runs: the UI tests hand Field links directly.

## The way in

`.onOpenURL` on the window's root view in `Field/FieldApp.swift` hands every link to `Arrivals` (`Field/Browser/Arrivals.swift`). Under the SwiftUI `App` lifecycle that one modifier also gets the link a cold launch was started for: SwiftUI reads the scene's URL contexts when it connects and calls `onOpenURL` with them, so there is no scene delegate. `IncomingLinksTests.testCold…` show it: `XCUIApplication.open(_:)` ends the running app and launches it with the link, and the link opens in the new process.

`http` and `https` are declared under `CFBundleURLTypes` in `Field/Info.plist`, as Apple asks of a browser. Debug builds also declare `field-test` for the UI tests (docs/m1-contracts.md).

## Checked at the door

FieldKit's `IncomingLink.accept` (`FieldKit/Sources/FieldKit/Incoming/IncomingLink.swift`):

- only `http` and `https`, with a host;
- no name or password before the host;
- ports must be in 0...65535, with no encoded NUL bytes or escaped delimiters, whitespace or controls in the host;
- known redirects are unwrapped and each hidden destination is checked, including non-web schemes and credentials. Chains beyond the guard's four unwraps are refused;
- the destination site's shield decides tracking clean-up. With its shield off, the unwrapped destination keeps its parameters, so the redirector's shield cannot clean them again when WebKit loads it.

A link that fails says so in a toast and opens nothing: "Field opens only web links.", "Didn't open a link with a password in it." or "That link has no address to open."

## When

FieldKit's `LinkInbox` holds links until the browser has started (the session restored) and the first-run welcome is done, then lets them go in the order they came. `Arrivals` waits for the guard's rules on the first one (a few milliseconds at launch) and opens them one at a time.

## Where

FieldKit's `LinkRoute`, carried out by `Browser.open(incoming:)`:

| On screen when it comes | What happens |
|---|---|
| Your tabs | A new tab with the link, shown. A blank tab on screen takes the link instead, since it has nothing to lose. The grid, if it's up, gives way to it as when a card is chosen. |
| Private, open | Back to your tabs with the switch's own slide, then as above. Private's tabs stay as they were. |
| Private under its shade (locked, the switcher's cover, a recording) | Your tabs are put in place under the shade, which then fades. Private stays locked, and nothing private is shown. |
| A sheet (Settings, Saved) | It goes, then as above. |

A link never opens in Private, and never unlocks it.

**An open field with a draft** closes as Cancel closes it: what was typed is dropped, and the page under it keeps its place. You left Field to tap the link somewhere else, so the link is what you're asking for now. Keeping the draft would mean either loading the link behind an open field or reopening the field over it.

## Motion

Leaving an open Private uses the strip's slide (`PrivateStrip.slide`). Under the shade the strip cuts instead (`PrivateStrip.cut`), and the shade fades on the frame after (`Browser.leavePrivate(underShade:)`), so the fade is the only motion and it never uncovers a private page. Coming from the background, that fade runs inside the system's zoom from the icon.

## Tests

- `swift test --disable-keychain` in `FieldKit`: `IncomingLinkTests` (the table of what's accepted, rejected and cleaned) and `LinkInboxTests` (when, and where).
- `FieldTests/IncomingTests`: the browser's side, with no UI.
- `FieldPerfTests/IncomingLinksTests`, with `-configuration Debug` for the warm cases (in Release they skip):

  ```sh
  xcodebuild test -project Field.xcodeproj -scheme FieldPerf -configuration Debug \
      -destination 'platform=iOS Simulator,name=iPhone 17' -packageAuthorizationProvider netrc \
      -collect-test-diagnostics never -only-testing FieldPerfTests/IncomingLinksTests
  ```
