# Notices

Field's own code is under the [Mozilla Public License 2.0](https://mozilla.org/MPL/2.0/),
in LICENSE. Its [source code](https://github.com/cwklurks/field-ios) is available
in this repository. The work below is other people's and keeps its own
licence. The full texts of the GPL, the Apache License and CC BY-SA 3.0
are in this repository's LICENSES/ directory, and with the MPL in the app
under Settings › About.

Field includes code adapted from **Search** by Office Commun
(https://github.com/driceroland/Search), under the MIT License below. Files adapted
from it say so in their first lines.

    MIT License
    
    Copyright (c) 2026 Office Commun
    
    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:
    
    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.
    
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

## Navigation guard rule tables

The navigation guard (FieldKit/Sources/FieldKit/Guard/Rules) ships snapshots of
these lists, unmodified apart from a `_meta` header with the source, the date
fetched and the licence. `scripts/guard/update.sh` fetches them.

- **Brave query filter and debounce lists** (`brave-query-filter.json`,
  `brave-debounce.json`), by Brave Software, Inc., from
  https://github.com/brave/adblock-lists (brave-lists/). Mozilla Public
  License 2.0, https://mozilla.org/MPL/2.0/. The source of these files is
  the repository above and the copies in this one.
- **DuckDuckGo tracking parameters** (`ddg-tracking-parameters.json`),
  Copyright 2010 Duck Duck Go, Inc., from
  https://github.com/duckduckgo/privacy-configuration (features/). Apache
  License 2.0, https://www.apache.org/licenses/LICENSE-2.0, and in
  LICENSES/Apache-2.0.txt. The file's own `_meta` was replaced by ours;
  nothing else was changed.
- **Public Suffix List** (`public-suffix-list.json`), from
  https://publicsuffix.org/list/public_suffix_list.dat, split into plain,
  wildcard and exception rules with punycode forms added. Mozilla Public
  License 2.0, https://mozilla.org/MPL/2.0/. The source of this file is the
  list above and the copy in this repository.

`amp.json` and `shims.json` in the same folder are Field's own tables,
under the Mozilla Public License 2.0 like the rest of its code. They are
written in the format of Brave's debounce list.

## Block lists

Field ships its block lists (Field/Resources/Lists) as WebKit content
rule list JSON, converted from Adblock Plus syntax and gzipped. Each is
under one licence, below. `scripts/lists/build.sh` makes them only from the
exact upstream copies in `scripts/lists/sources`, which
`scripts/lists/fetch.sh` fetches. `sources.json` there records each copy's
source, revision or version, sha256, date and licence;
`blocking-manifest.json`, beside the lists, records each list's licence,
sources and sha256. So the source of the lists in any version of Field is
in this repository at that version.

- **EasyList** (`easylist.json.gz`) and **EasyPrivacy**
  (`easyprivacy.json.gz`), by the EasyList authors, https://easylist.to/,
  from https://easylist.to/easylist/easylist.txt and
  https://easylist.to/easylist/easyprivacy.txt. Dual licensed under the GNU
  General Public License, version 3 or later,
  https://www.gnu.org/licenses/gpl-3.0.html, and Creative Commons
  Attribution-ShareAlike 3.0 Unported or later,
  https://creativecommons.org/licenses/by-sa/3.0/; Field uses them under
  CC BY-SA 3.0. See https://easylist.to/pages/licence.html. The converted
  files are under CC BY-SA 3.0 too. Their source is
  `scripts/lists/sources/easylist.txt.gz` and `easyprivacy.txt.gz`, with
  Field's allowlist (`scripts/lists/allowlist.txt`) appended before
  conversion.
- **Domain lists** (`domains-*.json.gz`), from **HaGeZi's DNS
  Blocklists**: Multi PRO
  (`adblock/pro.txt`) and the native tracker lists for Apple, Amazon,
  Huawei, Samsung, TikTok, Xiaomi, Oppo/Realme, Vivo, LG webOS and Roku
  (`adblock/native.*.txt`), by HaGeZi, from
  https://github.com/hagezi/dns-blocklists. GNU General Public License,
  version 3, https://www.gnu.org/licenses/gpl-3.0.html, and in
  LICENSES/GPL-3.0.txt, which HaGeZi asks to go with every copy. Their
  source is `scripts/lists/sources/hagezi-*.txt.gz`, merged, trimmed and
  converted by `scripts/lists/domains.py` and `build.sh`: domains EasyList
  or EasyPrivacy already block are left out, a list's own domain blocks as
  a third party only, a few shared sites (protected.txt) are never blocked
  whole, and the result is split into chunks of at most 60,000 input rules
  before conversion. The converter can emit additional WebKit rules. The
  chunks also hold the EasyList and EasyPrivacy exceptions for the domains
  they block, since WebKit applies a list's exceptions only to its own
  rules. Those come from the EasyList and EasyPrivacy sources above and are
  used here under EasyList's GPL option, so each domain list is under the
  GNU General Public License, version 3, as a whole.

  HaGeZi, as author and copyright holder of these lists, has given Field
  written permission (8 October 2026) to distribute them, in original or
  converted form, as part of the Field app through Apple's App Store and
  TestFlight. This covers Multi PRO and the native tracker lists above,
  their future versions and future versions of Field. It is an additional
  permission under section 7 of the GPLv3, for that distribution only,
  and covers HaGeZi's own rights, not those of upstream sources the lists
  draw on. The rest of the licence is unchanged.

Field's own rules (`allowlist.txt`, `extra.txt` and `protected.txt` in
scripts/lists) are under the Mozilla Public License 2.0 like the rest of
its code. Where they are copied into a list (the allowlist into every list,
extra.txt into `domains-1.json.gz`), Field also offers them under that
list's licence.

The conversion is done at build time by **SafariConverterLib**
(`ConverterTool` 4.3.0), Copyright AdGuard Software Ltd.,
https://github.com/AdguardTeam/SafariConverterLib, under the GNU General
Public License, version 3. It is not part of the app and is not
distributed with it, or with this repository: `build.sh` downloads it and
checks its sha256. Its build-time resource bundle comes from **swift-psl**,
https://github.com/ameshkov/swift-psl, at a fixed revision, also checked.
That library's code is under the MIT License, Copyright 2025 Andrey
Meshkov; the Public Suffix List data it processes is under the Mozilla
Public License 2.0, as described above. The manifest records both.

## Name and icon

The names "Field" and "Field Browser" and the app icon are not licensed
with the code. See TRADEMARKS.md.
