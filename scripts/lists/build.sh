#!/bin/bash
# Converts EasyList, EasyPrivacy and HaGeZi's domain lists to WebKit content
# rule lists with AdGuard's SafariConverterLib, and writes the gzipped JSON
# the app compiles on first launch, plus a manifest. See Field/Blocking and
# docs/research/blocking-and-redirects.md.
#
#   scripts/lists/build.sh
#
# The lists come from the copies in scripts/lists/sources, which fetch.sh
# fetches and records (sources.json), so the same commit always builds the
# same files. Each copy is checked against its recorded sha256 first. The
# manifest records, for each file it ships, its licence and the sources it
# was made from, along with every source and the tools.
#
# EasyList and EasyPrivacy convert as they are. HaGeZi's domains go through
# domains.py first (what it keeps, and why, is at its top), then split into
# lists small enough to parse in one short hold of the main thread. Field's
# own rules are in this folder: protected.txt, allowlist.txt, extra.txt.
#
# The converter is GPL-3 and only runs here, at build time: it's fetched
# into build/tools and never linked into the app. The network is used only
# for the converter and its resource bundle.
set -euo pipefail
cd "$(dirname "$0")/../.."

converter_version=4.3.0
converter_sha256=6687be9f1a77abd5299299086c5fbffd0d1b5baec755eb4808aa2f53e275d3c0
# The swift-psl revision SafariConverterLib 4.3.0 resolves to; the release
# binary crashes without this bundle next to it.
psl_revision=7ccee9d576d4ca45219440e346f61117f44c816f
# The bundle's four files, concatenated in the order they're fetched.
psl_sha256=2149891298bc325fda28717bf7731d629dfb1ddb1f9feb90b41127f5aace01e3
# The compiled WebKit format this output targets (Field's deployment target).
safari_version=26.0
# WebKit refuses a list over this many rules (ContentExtensionParser.cpp).
max_rules=150000
# Rules per domain list: WebKit parses a list on the main thread before it
# compiles it, about 40 ms for 60,000 of these on an M-series simulator.
domain_list_rules=60000

tools=build/tools/safari-converter-$converter_version
work=build/lists
out=Field/Resources/Lists
sources=scripts/lists/sources
psl_files=(common.bin negated.bin asterisk.bin version.txt)
fetch() { perl -e 'alarm 300; exec @ARGV' curl -fsSL --retry 2 -o "$1" "$2"; }

mkdir -p "$tools" "$work" "$out"

if ! echo "$converter_sha256  $tools/ConverterTool" | shasum -a 256 -c --status 2>/dev/null; then
    echo "Fetching ConverterTool $converter_version"
    fetch "$tools/ConverterTool" \
        "https://github.com/AdguardTeam/SafariConverterLib/releases/download/v$converter_version/ConverterTool"
    echo "$converter_sha256  $tools/ConverterTool" | shasum -a 256 -c --status || {
        echo "ConverterTool's checksum doesn't match; not running it." >&2
        rm -f "$tools/ConverterTool"
        exit 1
    }
    chmod +x "$tools/ConverterTool"
fi
bundle=$tools/swift-psl_PublicSuffixList.bundle
psl_url=https://raw.githubusercontent.com/ameshkov/swift-psl/$psl_revision/Sources/PublicSuffixList/Resources
if ! (cd "$bundle" 2>/dev/null && cat "${psl_files[@]}" 2>/dev/null) | shasum -a 256 | grep -q "^$psl_sha256 "; then
    echo "Fetching swift-psl $psl_revision"
    rm -rf "$bundle"
    mkdir -p "$bundle"
    for file in "${psl_files[@]}"; do
        fetch "$bundle/$file" "$psl_url/$file"
    done
    (cd "$bundle" && cat "${psl_files[@]}") | shasum -a 256 | grep -q "^$psl_sha256 " || {
        echo "swift-psl's checksum doesn't match; not using it." >&2
        rm -rf "$bundle"
        exit 1
    }
fi

# Each source, unzipped under the name domains.py and the loop below read:
# easylist.txt, easyprivacy.txt, and domains-<list>.src.txt for HaGeZi's.
rm -f "$work"/*.txt
while read -r name file sha256; do
    case $name in
    hagezi-*) input=$work/domains-${name#hagezi-}.src.txt ;;
    *) input=$work/$name.txt ;;
    esac
    gunzip -c "$sources/$file" >"$input"
    echo "$sha256  $input" | shasum -a 256 -c --status || {
        echo "$sources/$file doesn't match the sha256 in sources.json." >&2
        exit 1
    }
done < <(jq -r '.[] | "\(.name) \(.file) \(.sha256)"' "$sources/sources.json")
hagezi_sources=$(jq -c '[.[].name | select(startswith("hagezi-"))]' "$sources/sources.json")

# Each list: its name, its licence, and the sources it's made from.
lists=(
    "easylist CC-BY-SA-3.0 [\"easylist\"]"
    "easyprivacy CC-BY-SA-3.0 [\"easyprivacy\"]"
)
echo "Sorting domains"
uv run --quiet --script scripts/lists/domains.py "$work" "$work/domains" "$domain_list_rules"
domains_version=$(grep -m1 -i '^! Version:' "$work/domains-pro.src.txt" | sed 's/^! Version: *//')
domains_expires=$(grep -m1 -i '^! Expires:' "$work/domains-pro.src.txt" | sed 's/^! Expires: *//')
# HaGeZi's domains, less what EasyList and EasyPrivacy block, with their
# exceptions for those domains: GPL-3.0 as a whole (domains.py says why).
for file in "$work"/domains-[0-9]*.txt; do
    lists+=("$(basename "$file" .txt) GPL-3.0-only $(jq -c '. + ["easylist", "easyprivacy"]' <<<"$hagezi_sources")")
done

rm -f "$out"/*.json.gz
entries=()
for list in "${lists[@]}"; do
    read -r name licence list_sources <<<"$list"
    echo "Converting $name"
    input=$work/$name.txt
    case $name in
    domains-*)
        list_version=$domains_version
        expires=$domains_expires
        ;;
    *)
        # EasyList and EasyPrivacy get the allowlist too.
        input=$work/$name.field.txt
        cat "$work/$name.txt" scripts/lists/allowlist.txt >"$input"
        expires=$(grep -m1 -i '^! Expires:' "$work/$name.txt" | sed 's/^! Expires: *//' || true)
        list_version=$(grep -m1 -i '^! Version:' "$work/$name.txt" | sed 's/^! Version: *//' || true)
        ;;
    esac
    # Without a fixed hash seed the converter writes some rules in a
    # different order each run, so the same list would give a new file.
    SWIFT_DETERMINISTIC_HASHING=1 "$tools/ConverterTool" convert -s "$safari_version" -a false \
        --input-path "$input" \
        --safari-rules-json-path "$work/$name.json" \
        --advanced-blocking-rules-path "$work/$name.advanced.txt" >"$work/$name.log" 2>&1 || {
        cat "$work/$name.log" >&2
        exit 1
    }
    if [[ $name == domains-* ]]; then
        # A domain list never stops the page itself: a link or an address
        # typed to one of these still opens, and only what pages load from
        # them is blocked. WebKit keeps a list's exceptions to its own rules,
        # so this leaves EasyList's alone.
        jq -c '. + [{trigger: {"url-filter": ".*", "resource-type": ["document"], "load-context": ["top-frame"]},
            action: {type: "ignore-previous-rules"}}]' "$work/$name.json" >"$work/$name.json.tmp"
        mv "$work/$name.json.tmp" "$work/$name.json"
    fi
    rules=$(jq length "$work/$name.json")
    if [ "$rules" -ge "$max_rules" ]; then
        echo "$name has $rules rules; WebKit takes fewer than $max_rules." >&2
        exit 1
    fi
    # -n leaves the name and time out, so the same list gives the same file.
    gzip -9 -n -c "$work/$name.json" >"$out/$name.json.gz"
    sha=$(shasum -a 256 "$work/$name.json" | cut -d' ' -f1)
    echo "  $rules rules, $(wc -c <"$out/$name.json.gz" | tr -d ' ') bytes gzipped"
    entries+=("$(jq -n --arg name "$name" --arg file "$name.json.gz" --arg licence "$licence" \
        --argjson sources "$list_sources" --argjson rules "$rules" --arg sha256 "$sha" \
        --arg listVersion "$list_version" --arg expires "$expires" \
        '{name: $name, file: $file, licence: $licence, sources: $sources, rules: $rules, sha256: $sha256,
          listVersion: $listVersion, expires: $expires}')")
done

# The app keys each compiled list by the sha256 of its JSON, so a list that
# changed compiles again and one that didn't is left alone.
printf '%s\n' "${entries[@]}" | jq -s \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg converter "SafariConverterLib $converter_version" \
    --arg safari "$safari_version" \
    --argjson tools "$(jq -n --arg version "$converter_version" --arg sha256 "$converter_sha256" \
        --arg revision "$psl_revision" --arg pslSha256 "$psl_sha256" \
        '[{name: "ConverterTool", version: $version, sha256: $sha256,
           url: "https://github.com/AdguardTeam/SafariConverterLib/releases/download/v\($version)/ConverterTool"},
          {name: "swift-psl", revision: $revision, sha256: $pslSha256,
           url: "https://github.com/ameshkov/swift-psl/tree/\($revision)/Sources/PublicSuffixList/Resources"}]')" \
    --slurpfile sources "$sources/sources.json" \
    '{date: $date, converter: $converter, safariVersion: $safari, tools: $tools, sources: $sources[0], lists: .}' \
    >"$out/blocking-manifest.json"
echo "Wrote $out"
