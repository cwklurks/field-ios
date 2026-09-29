#!/bin/bash
# Records an Instruments trace (Animation Hitches) on a device while the
# scroll test runs, then prints the hitch time per second of scrolling: the
# ground truth that XCTHitchMetric approximates. See docs/perf.md.
#
#   scripts/perf/hitches.sh <device-udid> [glass|solid]
#
# Instruments can't record hitches on a simulator. The trace stays in
# build/perf/traces; open it in Instruments to see each hitch.
set -euo pipefail
cd "$(dirname "$0")/../.."

udid=${1:?usage: hitches.sh <device-udid> [glass|solid]}
look=${2:-glass}
case $look in
    glass) test=testScrollGlass ;;
    solid) test=testScrollSolid ;;
    *) echo "The look is glass or solid, not $look." >&2; exit 2 ;;
esac

# A locked phone makes xcodebuild wait forever for it, so stop now instead.
lock=$(mktemp)
perl -e 'alarm 60; exec @ARGV' xcrun devicectl device info lockState --device "$udid" --quiet --json-output "$lock" >/dev/null 2>&1 || true
locked=$(jq -r '.result.passcodeRequired' "$lock" 2>/dev/null || echo unknown)
rm -f "$lock"
if [ "$locked" != false ]; then
    echo "The phone is locked or not connected. Unlock it (and set Auto-Lock to Never for the run), then try again." >&2
    exit 1
fi

[ -d Field.xcodeproj ] || xcodegen generate --quiet

stamp=$(date +%Y-%m-%d-%H%M%S)
mkdir -p build/perf/traces
trace="build/perf/traces/$stamp-$look.trace"
log="build/perf/traces/$stamp-$look.log"
xcodebuild=(xcodebuild -project Field.xcodeproj -scheme FieldPerf -destination "platform=iOS,id=$udid"
    -derivedDataPath build/perf -allowProvisioningUpdates -collect-test-diagnostics never)

echo "Building FieldPerf for $udid; log in $log"
perl -e 'alarm 1800; exec @ARGV' "${xcodebuild[@]}" build-for-testing >"$log" 2>&1

# Start recording and wait until it has really started. The test runner's
# "scroll" signposts mark what to count, hence the os_signpost instrument.
started="com.connork.field.perftests.tracing.$$"
perl -e 'alarm 120; exec @ARGV' notifyutil -1 "$started" >/dev/null &
waiter=$!
# xctrace itself, not xcrun, so the interrupt below reaches it and it saves the trace.
"$(xcrun -f xctrace)" record --template 'Animation Hitches' --instrument os_signpost \
    --device "$udid" --all-processes --no-prompt --notify-tracing-started "$started" \
    --time-limit 15m --output "$trace" >>"$log" 2>&1 &
recorder=$!
sleep 2
if ! wait $waiter || ! kill -0 $recorder 2>/dev/null; then
    kill -INT $recorder 2>/dev/null || true
    echo "Instruments didn't start recording; the end of $log:" >&2
    tail -5 "$log" >&2
    exit 1
fi

echo "Recording; running ScrollTests/$test"
perl -e 'alarm 1800; exec @ARGV' "${xcodebuild[@]}" test-without-building \
    -only-testing "FieldPerfTests/ScrollTests/$test" >>"$log" 2>&1 || echo "The test failed; counting what was recorded."

kill -INT $recorder 2>/dev/null || true
wait $recorder || true
if [ ! -d "$trace" ]; then
    echo "No trace was saved; see $log" >&2
    exit 1
fi

echo "Trace: $trace"
uv run --quiet --script scripts/perf/hitches.py "$trace"
