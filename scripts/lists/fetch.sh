#!/bin/bash
# Fetches the upstream lists Field's block lists are made from into
# scripts/lists/sources, gzipped and otherwise byte for byte, and records
# each one's source, revision, version, sha256, date and licence in
# sources/sources.json. build.sh builds only from these copies, so the
# repository at any commit holds the exact source of the lists it ships.
# To update the lists, run this, then build.sh, and commit both.
#
#   scripts/lists/fetch.sh <hagezi-commit>
#
# HaGeZi's lists come from the given commit of hagezi/dns-blocklists, so the
# URL names exactly what was fetched. HaGeZi rewrites that repository's
# history now and then, so an old commit can disappear upstream: the copy
# here is the one that counts. EasyList and EasyPrivacy have no URL for a
# fixed version; each copy keeps its own `! Version:` header and the
# easylist/easylist commit it was built from (`! Commit:`), and the record
# has its sha256.
set -euo pipefail
cd "$(dirname "$0")/../.."

hagezi_revision=${1:-}
if ! [[ $hagezi_revision =~ ^[0-9a-f]{40}$ ]]; then
    echo "usage: $0 <hagezi-commit>, the full sha of a hagezi/dns-blocklists commit" >&2
    exit 1
fi

easylist_licence="GPL-3.0-or-later OR CC-BY-SA-3.0+"
hagezi_licence="GPL-3.0-only"
lists=(
    "easylist https://easylist.to/easylist/easylist.txt $easylist_licence"
    "easyprivacy https://easylist.to/easylist/easyprivacy.txt $easylist_licence"
)
# Multi PRO, and the native trackers of phones, TVs and their makers' sites.
for name in pro native.apple native.amazon native.huawei native.samsung native.tiktok native.xiaomi \
    native.oppo-realme native.vivo native.lgwebos native.roku; do
    lists+=("hagezi-$name https://raw.githubusercontent.com/hagezi/dns-blocklists/$hagezi_revision/adblock/$name.txt $hagezi_licence")
done

sources=scripts/lists/sources
work=build/lists/fetch
fetch() { perl -e 'alarm 300; exec @ARGV' curl -fsSL --retry 2 -o "$1" "$2"; }
header() { grep -m1 -i "^! $1:" "$2" | sed "s/^! $1: *//" | tr -d '\r' || true; }

rm -rf "$work"
mkdir -p "$work" "$sources"
entries=()
for list in "${lists[@]}"; do
    read -r name url licence <<<"$list"
    echo "Fetching $name"
    fetch "$work/$name.txt" "$url"
    case $name in
    hagezi-*) revision=$hagezi_revision ;;
    *) revision=$(header Commit "$work/$name.txt") ;;
    esac
    entries+=("$(jq -n --arg name "$name" --arg file "$name.txt.gz" --arg url "$url" --arg revision "$revision" \
        --arg version "$(header Version "$work/$name.txt")" \
        --arg sha256 "$(shasum -a 256 "$work/$name.txt" | cut -d' ' -f1)" \
        --arg fetched "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg licence "$licence" \
        '{name: $name, file: $file, url: $url, revision: $revision, version: $version, sha256: $sha256,
          fetched: $fetched, licence: $licence}')")
done

rm -f "$sources"/*.txt.gz
for list in "${lists[@]}"; do
    read -r name _ <<<"$list"
    # -n leaves the name and time out, so the same list gives the same file.
    gzip -9 -n -c "$work/$name.txt" >"$sources/$name.txt.gz"
done
printf '%s\n' "${entries[@]}" | jq -s . >"$sources/sources.json"
echo "Wrote $sources ($(du -sh "$sources" | cut -f1)); now run scripts/lists/build.sh"
