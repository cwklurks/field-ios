#!/bin/bash
# Archives a Release build of Field and exports it signed for App Store
# Connect, ready for TestFlight. See docs/release.md.
#
#   scripts/release/archive.sh            archive and export an .ipa, nothing leaves the Mac
#   scripts/release/archive.sh --upload   the same, then send it to App Store Connect
#   scripts/release/archive.sh --build N  use N as the build number
#
# The build number is the commit count, so each commit gets a higher one; a
# build number App Store Connect has already seen is refused, so a second
# upload of the same commit needs --build. Signing is automatic: Xcode makes
# the distribution certificate and profile the first time, which is why the
# Xcode account for team H435XM227M has to be signed in.
set -euo pipefail
cd "$(dirname "$0")/../.."

upload=false
build=$(git rev-list --count HEAD)
while [ $# -gt 0 ]; do
    case $1 in
        --upload) upload=true ;;
        --build) build=${2:?--build needs a number}; shift ;;
        *) echo "usage: archive.sh [--upload] [--build N]" >&2; exit 2 ;;
    esac
    shift
done
[[ $build =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] || { echo "A build number is up to three whole numbers joined by dots, not $build." >&2; exit 2; }

if [ -n "$(git status --porcelain)" ]; then
    echo "Note: there are uncommitted changes; build $build won't match commit $(git rev-parse --short HEAD) exactly."
fi

out=build/release
archive=$out/Field.xcarchive
export=$out/export
mkdir -p "$out"
log=$out/archive.log

xcodegen generate --quiet

echo "Archiving Field, build $build; log in $log"
perl -e 'alarm 1800; exec @ARGV' xcodebuild archive \
    -project Field.xcodeproj -scheme Field -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$out" -archivePath "$archive" \
    -allowProvisioningUpdates \
    CURRENT_PROJECT_VERSION="$build" >"$log" 2>&1 \
    || { tail -30 "$log" >&2; echo "The archive failed; the whole log is in $log." >&2; exit 1; }

app=$archive/Products/Applications/Field.app
# An incremental build can swap in a new profile without re-signing
# (docs/release.md), so nothing goes further unless the signature holds.
codesign --verify --deep --strict "$app"

options=scripts/release/ExportOptions.plist
if $upload; then
    options=$(mktemp -t ExportOptions).plist
    cp scripts/release/ExportOptions.plist "$options"
    /usr/libexec/PlistBuddy -c "Set :destination upload" "$options"
    echo "Exporting and uploading to App Store Connect"
else
    echo "Exporting to $export"
fi
perl -e 'alarm 1800; exec @ARGV' xcodebuild -exportArchive \
    -archivePath "$archive" -exportPath "$export" \
    -exportOptionsPlist "$options" -allowProvisioningUpdates >>"$log" 2>&1 \
    || { tail -30 "$log" >&2; echo "The export failed; the whole log is in $log." >&2; exit 1; }

info=$app/Info.plist
version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info")
bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info")
id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$info")

if $upload; then
    echo "Uploaded Field $version ($bundle), $id. It shows in TestFlight once App Store Connect has processed it, usually 5 to 30 minutes."
    exit 0
fi

# The exported .ipa is what App Store Connect would get: check its signature
# and that its profile is a distribution one (no debugger, no device list).
ipa=$export/Field.ipa
check=$(mktemp -d)
unzip -q "$ipa" -d "$check"
signed=$check/Payload/Field.app
codesign --verify --deep --strict "$signed"
signer=$(codesign -dvv "$signed" 2>&1 | sed -n 's/^Authority=\(Apple Distribution.*\)/\1/p' | head -1)
profile=$check/profile.plist
security cms -D -i "$signed/embedded.mobileprovision" >"$profile"
name=$(/usr/libexec/PlistBuddy -c 'Print :Name' "$profile")
if [ -z "$signer" ] \
    || [ "$(/usr/libexec/PlistBuddy -c 'Print :Entitlements:get-task-allow' "$profile" 2>/dev/null)" != false ] \
    || /usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$profile" >/dev/null 2>&1; then
    echo "The .ipa isn't signed for distribution; see $log." >&2
    exit 1
fi
rm -rf "$check"

echo
echo "Field $version ($bundle), $id"
echo "  signed by $signer"
echo "  profile   $name"
echo "  $ipa ($(du -h "$ipa" | cut -f1))"
echo "Nothing was uploaded. Run with --upload to send it to App Store Connect."
