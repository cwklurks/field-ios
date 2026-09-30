# Notices

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
  `brave-debounce.json`), Copyright Brave Software, Inc., from
  https://github.com/brave/adblock-lists (brave-lists/). Mozilla Public
  License 2.0, https://mozilla.org/MPL/2.0/. The source of these files is
  the repository above and the copies in this one.
- **DuckDuckGo tracking parameters** (`ddg-tracking-parameters.json`),
  Copyright DuckDuckGo, Inc., from
  https://github.com/duckduckgo/privacy-configuration (features/). Apache
  License 2.0, https://www.apache.org/licenses/LICENSE-2.0. The file's own
  `_meta` was replaced by ours; nothing else was changed.
- **Public Suffix List** (`public-suffix-list.json`), from
  https://publicsuffix.org/list/public_suffix_list.dat, split into plain,
  wildcard and exception rules with punycode forms added. Mozilla Public
  License 2.0, https://mozilla.org/MPL/2.0/.

## Block lists

Field ships EasyList and EasyPrivacy (Field/Resources/Lists), converted from
Adblock Plus syntax to WebKit content rule list JSON and gzipped. Nothing else
was changed. `scripts/lists/build.sh` fetches and converts them, and
`blocking-manifest.json` records each list's source, version and sha256.

- **EasyList** (`easylist.json.gz`) and **EasyPrivacy**
  (`easyprivacy.json.gz`), by the EasyList authors, https://easylist.to/,
  from https://easylist.to/easylist/easylist.txt and
  https://easylist.to/easylist/easyprivacy.txt. Dual licensed under the GNU
  General Public License, version 3 or later,
  https://www.gnu.org/licenses/gpl-3.0.html, and Creative Commons
  Attribution-ShareAlike 3.0 Unported,
  https://creativecommons.org/licenses/by-sa/3.0/; Field uses them under
  CC BY-SA 3.0. See https://easylist.to/pages/licence.html. The converted
  files are under the same licence.
- The conversion is done at build time by **SafariConverterLib**
  (`ConverterTool` 4.3.0), Copyright AdGuard Software Ltd.,
  https://github.com/AdguardTeam/SafariConverterLib, under the GNU General
  Public License, version 3. It is not part of the app and is not
  distributed with it.
