#!/bin/bash
# Snapshots the navigation guard's rule tables from their upstream sources
# into FieldKit/Sources/FieldKit/Guard/Rules, with the source URL, the date
# fetched and the licence in each file's "_meta". This is the only part of the
# guard that touches the network, and it runs here, never in the app.
#
#     scripts/guard/update.sh
#
# shims.json and amp.json are Field's own tables and aren't touched.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/FieldKit/Sources/FieldKit/Guard/Rules"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fetch() { curl -sSfL --retry 2 --max-time 60 -o "$work/$1" "$2"; }

brave=https://raw.githubusercontent.com/brave/adblock-lists/master/brave-lists
ddg=https://raw.githubusercontent.com/duckduckgo/privacy-configuration/main/features
psl=https://publicsuffix.org/list/public_suffix_list.dat

fetch query-filter.json "$brave/query-filter.json"
fetch debounce.json "$brave/debounce.json"
fetch tracking-parameters.json "$ddg/tracking-parameters.json"
fetch public_suffix_list.dat "$psl"

python3 - "$work" "$out" "$brave" "$ddg" "$psl" <<'PY'
import datetime, json, sys, pathlib

work, out, brave, ddg, psl = sys.argv[1:]
work, out = pathlib.Path(work), pathlib.Path(out)
today = datetime.date.today().isoformat()
MPL = "MPL-2.0 (https://mozilla.org/MPL/2.0/)"

def meta(source, licence, note):
    return {"source": source, "fetched": today, "licence": licence, "note": note}

def write(name, body):
    (out / name).write_text(json.dumps(body, indent=1, ensure_ascii=False) + "\n")

def load(name):
    return json.loads((work / name).read_text())

write("brave-query-filter.json", {
    "_meta": meta(f"{brave}/query-filter.json", MPL,
                  "Brave's query string filter, as published. Unmodified."),
    "rules": load("query-filter.json"),
})

write("brave-debounce.json", {
    "_meta": meta(f"{brave}/debounce.json", MPL,
                  "Brave's debounce (link unwrapping) rules, as published. Unmodified."),
    "rules": load("debounce.json"),
})

tracking = load("tracking-parameters.json")
tracking.pop("_meta", None)
write("ddg-tracking-parameters.json", {
    "_meta": meta(f"{ddg}/tracking-parameters.json",
                  "Apache-2.0 (https://www.apache.org/licenses/LICENSE-2.0)",
                  "DuckDuckGo's tracking parameter feature, as published, less its own _meta."),
    **tracking,
})

# The public suffix list, split into plain, wildcard and exception rules.
# Hosts reach the guard in their ASCII (punycode) form, so internationalised
# rules are kept both ways.
def ascii_form(rule):
    try:
        return ".".join(l if l == "*" else l.encode("idna").decode("ascii") for l in rule.split("."))
    except UnicodeError:
        return None

rules, wildcards, exceptions = set(), set(), set()
for line in (work / "public_suffix_list.dat").read_text().splitlines():
    line = line.strip()
    if not line or line.startswith("//"):
        continue
    rule = line.split()[0].lower()
    body = rule.lstrip("!")
    for form in {body, ascii_form(body)} - {None}:
        if rule.startswith("!"):
            exceptions.add(form)
        elif form.startswith("*."):
            wildcards.add(form[2:])
        else:
            rules.add(form)

write("public-suffix-list.json", {
    "_meta": meta(psl, MPL,
                  "The Public Suffix List (ICANN and private sections), split into rules, "
                  "wildcard rules (without the leading *.) and exception rules (without the "
                  "leading !), with punycode forms added."),
    "rules": sorted(rules),
    "wildcards": sorted(wildcards),
    "exceptions": sorted(exceptions),
})
print(f"query filter: {len(load('query-filter.json'))} rules; debounce: {len(load('debounce.json'))} rules; "
      f"ddg: {len(tracking['settings']['parameters'])} parameters; "
      f"psl: {len(rules)} rules, {len(wildcards)} wildcards, {len(exceptions)} exceptions")
PY
