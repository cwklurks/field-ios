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
