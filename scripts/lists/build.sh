#!/bin/bash
# Fetches EasyList and EasyPrivacy, converts them to WebKit content rule
# lists with AdGuard's SafariConverterLib, and writes the gzipped JSON the
# app compiles on first launch, plus a manifest. See Field/Blocking and
# docs/research/blocking-and-redirects.md.
#
#   scripts/lists/build.sh
#
# The converter is GPL-3 and only runs here, at build time: it's fetched
# into build/tools and never linked into the app. The network is used only
# for the converter, its resource bundle and the two lists.
set -euo pipefail
cd "$(dirname "$0")/../.."

converter_version=4.3.0
converter_sha256=6687be9f1a77abd5299299086c5fbffd0d1b5baec755eb4808aa2f53e275d3c0
# The swift-psl revision SafariConverterLib 4.3.0 resolves to; the release
# binary crashes without this bundle next to it.
psl_revision=7ccee9d576d4ca45219440e346f61117f44c816f
# The compiled WebKit format this output targets (Field's deployment target).
safari_version=26.0
# WebKit refuses a list over this many rules (ContentExtensionParser.cpp).
max_rules=150000

tools=build/tools/safari-converter-$converter_version
work=build/lists
out=Field/Resources/Lists
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
if [ ! -f "$bundle/version.txt" ]; then
    mkdir -p "$bundle"
    for file in common.bin negated.bin asterisk.bin version.txt; do
        fetch "$bundle/$file" \
            "https://raw.githubusercontent.com/ameshkov/swift-psl/$psl_revision/Sources/PublicSuffixList/Resources/$file"
    done
fi

lists=(
    "easylist https://easylist.to/easylist/easylist.txt"
    "easyprivacy https://easylist.to/easylist/easyprivacy.txt"
)

entries=()
for list in "${lists[@]}"; do
    read -r name source <<<"$list"
    echo "Fetching $name"
    fetch "$work/$name.txt" "$source"
    echo "Converting $name"
    "$tools/ConverterTool" convert -s "$safari_version" -a false \
        --input-path "$work/$name.txt" \
        --safari-rules-json-path "$work/$name.json" \
        --advanced-blocking-rules-path "$work/$name.advanced.txt" >"$work/$name.log" 2>&1 || {
        cat "$work/$name.log" >&2
        exit 1
    }
    rules=$(jq length "$work/$name.json")
    if [ "$rules" -ge "$max_rules" ]; then
        echo "$name has $rules rules; WebKit takes fewer than $max_rules." >&2
        exit 1
    fi
    # -n leaves the name and time out, so the same list gives the same file.
    gzip -9 -n -c "$work/$name.json" >"$out/$name.json.gz"
    sha=$(shasum -a 256 "$work/$name.json" | cut -d' ' -f1)
    expires=$(grep -m1 -i '^! Expires:' "$work/$name.txt" | sed 's/^! Expires: *//' || true)
    list_version=$(grep -m1 -i '^! Version:' "$work/$name.txt" | sed 's/^! Version: *//' || true)
    echo "  $rules rules, $(wc -c <"$out/$name.json.gz" | tr -d ' ') bytes gzipped"
    entries+=("$(jq -n --arg name "$name" --arg file "$name.json.gz" --arg source "$source" \
        --argjson rules "$rules" --arg sha256 "$sha" --arg listVersion "$list_version" --arg expires "$expires" \
        '{name: $name, file: $file, source: $source, rules: $rules, sha256: $sha256, listVersion: $listVersion, expires: $expires}')")
done

# The app keys each compiled list by the sha256 of its JSON, so a list that
# changed compiles again and one that didn't is left alone.
printf '%s\n' "${entries[@]}" | jq -s \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg converter "SafariConverterLib $converter_version" \
    --arg safari "$safari_version" \
    '{date: $date, converter: $converter, safariVersion: $safari, lists: .}' >"$out/blocking-manifest.json"
echo "Wrote $out"
