#!/bin/bash
# The video loop in docs/motion.md: records FieldPerfTests/MotionScript on a
# booted-headless simulator, then cuts frame strips and counts, for each tap,
# the frames from the finger lifting to the first change on screen.
#
#   scripts/motion/record.sh <out-dir> [glass|solid]
#
# SIM picks the simulator by name (default "iPhone 17"). The build is the
# FieldPerf scheme's Release build, in build/motion-perf.
set -euo pipefail
cd "$(dirname "$0")/../.."

out=${1:?usage: record.sh <out-dir> [glass|solid]}
look=${2:-glass}
sim=${SIM:-iPhone 17}
udid=$(xcrun simctl list devices available -j | jq -r --arg n "$sim" '[.devices[][] | select(.name == $n)][0].udid')
[ "$udid" != null ] || { echo "No simulator named $sim" >&2; exit 1; }
mkdir -p "$out"

xcrun simctl bootstatus "$udid" -b >/dev/null
[ -d Field.xcodeproj ] || xcodegen generate --quiet
perl -e 'alarm 1200; exec @ARGV' xcodebuild build-for-testing -project Field.xcodeproj -scheme FieldPerf \
    -destination "id=$udid" -derivedDataPath build/motion-perf -quiet >"$out/build.log" 2>&1 \
    || { grep -E "error:" "$out/build.log" | head -20 >&2; exit 1; }

rm -f "$out/raw.mp4"
xcrun simctl io "$udid" recordVideo --codec h264 --force "$out/raw.mp4" >/dev/null 2>&1 &
recorder=$!
sleep 2
status=0
TEST_RUNNER_MOTION_LOOK=$look perl -e 'alarm 400; exec @ARGV' xcodebuild test-without-building \
    -project Field.xcodeproj -scheme FieldPerf -destination "id=$udid" -derivedDataPath build/motion-perf \
    -collect-test-diagnostics never -only-testing FieldPerfTests/MotionScript/testChoreography \
    >"$out/test.log" 2>&1 || status=$?
sleep 1
kill -INT $recorder
wait $recorder || true
grep -E "^Test Case .*(passed|failed|skipped)" "$out/test.log" || tail -20 "$out/test.log"
[ $status = 0 ] || echo "xcodebuild exited $status" >&2

uv run --quiet --with numpy --with pillow python3 scripts/motion/frames.py "$out/raw.mp4" "$out"
