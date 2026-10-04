# Field

A small, fast, quiet web browser for the iPhone, by Connor Klann. Adapted from [Search](https://github.com/driceroland/Search), the Mac browser by Office Commun, under the MIT licence in [NOTICE.md](NOTICE.md).

## What it is

Field is a browser with nothing in the way. One bar at the bottom — back, the address, the tab count — and the page. There is no start page, no sidebar of suggestions, no account to sign into. You type an address or a few words and you are on the page.

It uses **WebKit**, the engine already inside every iPhone, so there is no second browser to download and keep updated. Pages run in WebKit's own content process, as in Safari.

It carries over the Mac app's taste: no accent colour, three motion curves, continuous corners, toasts instead of alerts, and one file per concern.

## What it does

- **One field.** Type an address and you go there; type words and you search. It finishes addresses and your past searches from your own history. With **Search suggestions** on (Settings, under Search engine), what you type is sent to your search engine as you type, so it can suggest searches; never in Private, and never an address or anything that looks like a password. Turn it off and nothing you type is sent until you press Return.
- **One bar that stays out of the way.** Long-press back for forward and history, swipe the pill sideways to change tabs, swipe up for the tab grid. Scrolling shrinks the pill to the host name. Edge swipes go back and forward; pull down to reload.
- **Tabs.** A grid of cards, two across; swipe a card away to close it. A tab you are not using sleeps and costs nothing until you return to it. Your tabs come back after a quit, and Recently Closed brings one back.
- **Blocking, before the page.** Ads and trackers are stopped at the network level inside WebKit, so there is nothing to render. The lists are EasyList, EasyPrivacy and HaGeZi's domain lists, compiled once and enforced before a request is made. Each site has an off switch; popups get a small chip, and a page the blocker stops offers "Load anyway."
- **Clean links.** Links arrive without the wrappers: Google, Facebook, Reddit and YouTube redirects are unwrapped, tracking parameters are stripped, AMP pages return to the original, and a cross-site jump or App Store hijack you did not tap is cancelled.
- **Saved.** Save a page from the address's long-press menu and it lands in one list with optional folders. Starred pages sit on the new-tab page; "Read later" is the saved pages you have not opened since.
- **Capture the whole page.** Capture Page on the address's long-press saves a PDF or one tall image to share. The system screenshot's Full Page tab does the same, and opens where you were looking.
- **Private.** A separate, always-dark space you deliberately enter. Its tabs keep nothing on disk, it locks when you leave, shows a cover in the app switcher, and is wiped when you close it. It says plainly what it cannot do.
- **Help that stays on the phone.** Saved can suggest a folder for a page with Apple's on-device language tools.

## What it doesn't do

On purpose:

- No account, no sync, no cloud. Tabs, history and saved pages are on your phone and nowhere else.
- No analytics, no tracking, no crash reports sent anywhere. The only things that leave the phone are the pages you open and what they load, and, with Search suggestions on, what you type, to your search engine.
- No sign-in wall, no start page, no suggested articles. The blank new tab is blank until you type.
- No Tor. It is planned for a later release, not this one.
- Tidy, the tab-grouping helper, is optional and still in progress.

## Privacy, concretely

| What | Where it is | Who can read it |
|---|---|---|
| History, past searches, tabs, session, saved pages | Small JSON files in the app's Application Support folder | You. |
| Settings | The app's own defaults | You. |
| Cookies and site data | WebKit's own store for the app | The sites that set them, as in any browser. |
| Pictures of tabs | The app's cache, in memory for private tabs | You. |
| What you type, with Search suggestions on | Sent to your search engine as you type, without cookies; never in Private, never an address or a secret | Your search engine. |
| Anything else | Nowhere. There is no server. | — |

A **private tab** keeps its tabs, pictures and history in memory, in its own data store, and leaves nothing behind when Private closes. The full policy is in [docs/privacy.md](docs/privacy.md).

## Building it

- iOS 26 or later, Xcode 27, Swift 6, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- `xcodegen generate` writes `Field.xcodeproj` from [project.yml](project.yml). The project file is not committed.
- Open `Field.xcodeproj` and run the **Field** scheme on a device or the simulator.
- The framework logic is a local Swift package. `swift test` inside `FieldKit/` runs its tests on the Mac in seconds.
- `xcodebuild test -scheme Field` runs the app's tests and FieldKit's. The **FieldPerf** scheme measures the smoothness budgets in [docs/PLAN.md](docs/PLAN.md).
- `scripts/release/archive.sh` archives a Release build and exports a signed `.ipa` for App Store Connect; add `--upload` to send it to TestFlight. See [docs/release.md](docs/release.md).

## How it's put together

- **SwiftUI** for everything drawn and **WKWebView** for pages, wrapped in one `UIViewRepresentable` that swaps each tab's web view in and out, so SwiftUI never rebuilds them.
- **FieldKit**, a local Swift package with no UIKit and no WebKit where possible: address parsing, search engines and their suggestions, history ranking, the session format, the Saved model, registrable domains, the navigation guard and Tidy. It is tested fast on the Mac with `swift test`.
- **XcodeGen** builds the project from `project.yml`; there is no checked-in `.xcodeproj`.
- `Field/` is one file per concern: the bar, the browser, tabs, blocking, the guard, Saved, Private and capture each live in a folder of their own, and `FieldKit/` holds the logic underneath.

## Licence and credits

Field includes code adapted from **Search** by Office Commun, under the MIT License. It ships third-party block lists and rule tables, each with its own licence. All of it is set out in [NOTICE.md](NOTICE.md), which the app shows in full under Settings › About.
