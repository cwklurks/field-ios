#!/bin/bash
# Runs the FieldPerf scheme (a Release build) and prints each interaction
# against its budget from docs/PLAN.md, "Smooth". See docs/perf.md.
#
#   scripts/perf/run.sh "iPhone 17e"                  a simulator, by name
#   scripts/perf/run.sh 00008150-000A1234ABCD001C     a device (or a simulator) by UDID
#   scripts/perf/run.sh "iPhone 17e" ScrollTests InputTests/testKeystroke
#                                                     only those tests
#
# Only the iPhone 17 counts against the budgets; simulator numbers are for
# spotting regressions and checking the harness works.
set -euo pipefail
cd "$(dirname "$0")/../.."

destination=${1:?usage: run.sh <simulator name | device UDID> [TestClass[/testMethod] ...]}
shift

simulators=$(xcrun simctl list devices available -j)
if jq -e --arg d "$destination" '[.devices[][] | select(.name == $d)] | length > 0' <<<"$simulators" >/dev/null; then
    kind=simulator
    target="platform=iOS Simulator,name=$destination"
elif jq -e --arg d "$destination" '[.devices[][] | select(.udid == $d)] | length > 0' <<<"$simulators" >/dev/null; then
    kind=simulator
    target="platform=iOS Simulator,id=$destination"
else
    kind=device
    target="platform=iOS,id=$destination"
fi

if [ "$kind" = device ]; then
    udid=$destination
    # A locked phone makes xcodebuild wait forever for it, so stop now instead.
    lock=$(mktemp)
    perl -e 'alarm 60; exec @ARGV' xcrun devicectl device info lockState --device "$udid" --quiet --json-output "$lock" >/dev/null 2>&1 || true
    locked=$(jq -r '.result.passcodeRequired' "$lock" 2>/dev/null || echo unknown)
    rm -f "$lock"
    if [ "$locked" != false ]; then
        echo "The phone is locked or not connected. Unlock it (and set Auto-Lock to Never for the run), then try again." >&2
        exit 1
    fi
fi

[ -d Field.xcodeproj ] || xcodegen generate --quiet

stamp=$(date +%Y-%m-%d-%H%M%S)
results=build/perf/results
mkdir -p "$results"
result="$results/$stamp-$kind.xcresult"
log="$results/$stamp-$kind.log"

only=()
for test in "$@"; do
    only+=(-only-testing "FieldPerfTests/$test")
done
signing=()
[ "$kind" = device ] && signing=(-allowProvisioningUpdates)

echo "Running FieldPerf on $destination ($kind); log in $log"
status=0
# No diagnostics on failure: on a simulator, collecting them waits 10 minutes and times out.
perl -e 'alarm 3600; exec @ARGV' xcodebuild test \
    -project Field.xcodeproj -scheme FieldPerf \
    -destination "$target" -derivedDataPath build/perf -collect-test-diagnostics never \
    -resultBundlePath "$result" ${signing[@]+"${signing[@]}"} ${only[@]+"${only[@]}"} \
    >"$log" 2>&1 || status=$?
grep -E "^Test Case .*(passed|failed|skipped)" "$log" | sed -E "s/^Test Case '-\[FieldPerfTests\.([^]]*)\]'/  \1/" || true

if [ ! -d "$result" ]; then
    echo "No result bundle; xcodebuild exited $status. The end of the log:" >&2
    tail -20 "$log" >&2
    exit 1
fi

summary=$(xcrun xcresulttool get test-results summary --path "$result" --compact)
device=$(jq -r '.devicesAndConfigurations[0].device | "\(.deviceName) (\(.modelName), \(.platform) \(.osVersion))"' <<<"$summary")
build=$(git describe --always --dirty 2>/dev/null || echo "no commits yet")

echo
echo "$(date '+%Y-%m-%d %H:%M')  $device  Release build $build"
[ "$kind" = simulator ] && echo "SIMULATOR: these numbers don't count against the budgets; only the iPhone 17 does."
echo
{
    printf 'Interaction\tMeasured\tBudget\tResult\n'
    jq -r --argjson tests "$(xcrun xcresulttool get test-results tests --path "$result" --compact)" \
        --arg kind "$kind" -f scripts/perf/report.jq \
        <(xcrun xcresulttool get test-results metrics --path "$result" --compact)
} | tee "$results/$stamp-$kind.tsv" | column -t -s $'\t'
echo
echo "Result bundle: $result"

# On a device, a missed budget fails the run; a failed test always does.
if [ "$kind" = device ] && grep -q $'\tFAIL$' "$results/$stamp-$kind.tsv"; then
    exit 1
fi
[ "$(jq -r '.result' <<<"$summary")" != Failed ]
