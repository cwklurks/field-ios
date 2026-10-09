# Contributing

Thanks for wanting to help. Field is small on purpose, so a change that adds something should say what it's for. For anything bigger than a fix, open an issue first.

## Building and testing

Set-up is in the README, under "Building it". To run on a phone you need your own team: set `DEVELOPMENT_TEAM` in `project.yml` to yours, and leave that change out of your pull request.

- `swift test` inside `FieldKit/` runs the logic's tests on the Mac in seconds.
- `xcodebuild test -scheme Field -destination 'platform=iOS Simulator,name=iPhone 17'` runs the app's tests and FieldKit's. Use any iOS 26 simulator you have.

Both should pass before you open a pull request.

## How the code is written

- **Commit messages** are `<type>: <description>`, with a body if it needs one. The types are feat, fix, refactor, docs, test, chore, perf and ci.
- **Tests first for logic.** A fix or a feature starts with a failing test, then the change that makes it pass. Logic goes in FieldKit where it can, so it's tested with `swift test`.
- **UI follows [docs/motion.md](docs/motion.md).** Every UI change is checked against it, on video: one object in one continuous motion, the next frame responds, only the three curves.
- **One file per concern.** A new piece gets its own file in the folder it belongs to, not a few lines in a bigger one.
- Match the code around you: its naming, its comments, its plain sentences.

## No tracking, ever

Field has no analytics or telemetry. Browsing requests and enabled search suggestions are described in [docs/privacy.md](docs/privacy.md); suggestions are on by default. A pull request that adds analytics, telemetry, crash reporting, an advertising identifier, a third-party SDK that phones home, or an undisclosed background request will not be merged. If a change makes the app send something new, say so in the pull request, and update the privacy policy and the README's privacy table to match.

## Licence

Field is under the Mozilla Public License 2.0 ([LICENSE](LICENSE)). By opening a pull request you agree that your contribution is under the same licence. There is no contributor agreement to sign.

Please put the MPL notice at the top of new source files:

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
```

Third-party code or data needs its licence in [NOTICE.md](NOTICE.md), and a licence that fits next to the MPL and the App Store. Ask first if you're not sure.

The name "Field" and the icon aren't covered by the licence; see [TRADEMARKS.md](TRADEMARKS.md).
