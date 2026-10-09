# Block list sources

The exact upstream lists Field's block lists (Field/Resources/Lists) are
built from, gzipped and otherwise unchanged. `fetch.sh` fetches them and
writes `sources.json`: for each file, where it came from, the upstream
revision and version, its sha256 unzipped, when it was fetched and its
licence. `build.sh` builds only from these copies, so the lists the app
ships at any commit can be rebuilt from that commit.

- `easylist.txt.gz` and `easyprivacy.txt.gz`: EasyList and EasyPrivacy, by
  the EasyList authors, https://easylist.to/. Dual licensed under the GNU
  General Public License, version 3 or later, and Creative Commons
  Attribution-ShareAlike 3.0 Unported or later; see
  https://easylist.to/pages/licence.html.
- `hagezi-*.txt.gz`: HaGeZi's DNS Blocklists, by HaGeZi,
  https://github.com/hagezi/dns-blocklists. GNU General Public License,
  version 3, in LICENSES/GPL-3.0.txt.

Each file keeps its own header, with its licence, version and, for
EasyList and EasyPrivacy, the easylist/easylist commit it was built from.

## Refreshing the lists

From the repository root, with `curl`, `jq`, `uv`, Swift and XcodeGen installed:

1. Run `scripts/lists/fetch.sh <hagezi-sha>`, using the full 40-character
   commit SHA from HaGeZi's repository. This refreshes all 13 input copies
   and their record; EasyList and EasyPrivacy come from their current URLs.
2. Run `scripts/lists/build.sh`. It checks the committed copies' hashes,
   converts them and writes the shipped lists and `blocking-manifest.json`.
   The first build downloads the pinned converter and its resource bundle.
3. Run `cd FieldKit && swift test --disable-keychain`, then, from the root,
   `xcodegen generate` and the full Field tests:

   ```sh
   xcodebuild test -project Field.xcodeproj -scheme Field \
       -destination 'platform=iOS Simulator,name=iPhone 17' \
       -derivedDataPath build/list-refresh-derived-data \
       -packageAuthorizationProvider netrc
   ```

The Field suite includes `BlockingSourcesTests`, which checks the bundled
output hashes, the source records and the exact input copies. Review the
changes, then commit the sources, `sources.json`, rebuilt lists and manifest
together. A rebuild without a refresh uses the copies already in this checkout.
