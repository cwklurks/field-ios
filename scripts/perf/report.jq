# Turns `xcresulttool get test-results metrics` into the rows of run.sh's table.
# Arguments: $tests (`xcresulttool get test-results tests`) and $kind
# ("simulator" or "device"). Output: tab-separated rows, no header.

# The budgets from docs/PLAN.md, "Smooth". `pick` is a regex on the metric's
# identifier, or "hitch" for XCTHitchMetric's hitch time ratio. `max` holds
# the slowest iteration to the budget instead of the average.
#
# On a device XCTest also reports hitches inside each animation interval (the
# app begins them with beginAnimationInterval). Those catch hitches that
# XCTHitchMetric misses, so each interaction is held to both.
def budgets: [
  {test: "LaunchTests/testColdLaunch()", what: "first frame", pick: "AppLaunch\\.duration$", budget: 400},
  {test: "LaunchTests/testColdLaunch()", what: "ready for input", pick: "FirstFramePresentationResponsive", budget: 500},
  {test: "ScrollTests/testScrollGlass()", what: "hitch time", pick: "hitch", budget: 2},
  {test: "ScrollTests/testScrollGlass()", what: "hitch time, scrolling", pick: "Scroll_DraggingAndDeceleration\\.animation\\.hitch\\.time\\.ratio", budget: 2},
  {test: "ScrollTests/testScrollGlass()", what: "hitch time, bar.collapse", pick: "bar\\.collapse\\.animation\\.hitch\\.time\\.ratio", budget: 2},
  {test: "ScrollTests/testScrollGlass()", what: "hitch time, bar.expand", pick: "bar\\.expand\\.animation\\.hitch\\.time\\.ratio", budget: 2},
  {test: "ScrollTests/testScrollGlass()", what: "bar.collapse", pick: "bar\\.collapse\\.duration"},
  {test: "ScrollTests/testScrollGlass()", what: "bar.expand", pick: "bar\\.expand\\.duration"},
  {test: "ScrollTests/testScrollSolid()", what: "hitch time", pick: "hitch", budget: 2},
  {test: "ScrollTests/testScrollSolid()", what: "hitch time, scrolling", pick: "Scroll_DraggingAndDeceleration\\.animation\\.hitch\\.time\\.ratio", budget: 2},
  {test: "ScrollTests/testScrollSolid()", what: "hitch time, bar.collapse", pick: "bar\\.collapse\\.animation\\.hitch\\.time\\.ratio", budget: 2},
  {test: "ScrollTests/testScrollSolid()", what: "hitch time, bar.expand", pick: "bar\\.expand\\.animation\\.hitch\\.time\\.ratio", budget: 2},
  {test: "ScrollTests/testScrollSolid()", what: "bar.collapse", pick: "bar\\.collapse\\.duration"},
  {test: "ScrollTests/testScrollSolid()", what: "bar.expand", pick: "bar\\.expand\\.duration"},
  {test: "InputTests/testOpenField()", what: "field.open", pick: "field\\.open\\.duration"},
  {test: "InputTests/testOpenField()", what: "hitch time", pick: "hitch", budget: 2},
  {test: "InputTests/testOpenField()", what: "hitch time, field.open", pick: "field\\.open\\.animation\\.hitch\\.time\\.ratio", budget: 2},
  {test: "InputTests/testKeystroke()", what: "field.keystroke, slowest", pick: "field\\.keystroke\\.duration", budget: 8.3, max: true},
  {test: "InputTests/testTypingHitches()", what: "hitch time", pick: "hitch", budget: 2},
  {test: "WelcomeTests/testChoose()", what: "welcome.choose", pick: "welcome\\.choose\\.duration"},
  {test: "WelcomeTests/testChoose()", what: "hitch time", pick: "hitch", budget: 2},
  {test: "WelcomeTests/testChoose()", what: "hitch time, welcome.choose", pick: "welcome\\.choose\\.animation\\.hitch\\.time\\.ratio", budget: 2},
  {test: "BaselineTests/testColdLaunch()", what: "first frame", pick: "AppLaunch\\.duration$"},
  {test: "BaselineTests/testColdLaunch()", what: "ready for input", pick: "FirstFramePresentationResponsive"},
  {test: "BaselineTests/testKeystroke()", what: "field.keystroke, slowest", pick: "field\\.keystroke\\.duration", max: true}
];

def interaction: {
  "LaunchTests/testColdLaunch()": "Cold launch",
  "ScrollTests/testScrollGlass()": "Scroll, glass bar",
  "ScrollTests/testScrollSolid()": "Scroll, solid bar",
  "InputTests/testOpenField()": "Open the field",
  "InputTests/testKeystroke()": "Keystroke",
  "BaselineTests/testColdLaunch()": "Baseline (bare field), cold launch",
  "BaselineTests/testKeystroke()": "Baseline (bare field), keystroke",
  "InputTests/testTypingHitches()": "Type a word",
  "WelcomeTests/testChoose()": "Welcome choice"
}[.] // .;

# XCTHitchMetric's ratio, e.g. XCTMetric_Hitch-field.time.ratio. Not its
# total duration, whose name also contains "ratio".
def hitch: (.identifier // "") | test("XCTMetric_Hitch-.*time\\.ratio$");
def matches($pick): if $pick == "hitch" then hitch else (.identifier // "") | test($pick) end;
def values: if .unitOfMeasurement == "s" then .measurements | map(. * 1000) else .measurements end;
def unit: if .unitOfMeasurement == "s" then "ms" elif .unitOfMeasurement == "ms per s" then "ms/s" else .unitOfMeasurement end;
def num: if . >= 100 then round | tostring else (. * 10 | round) / 10 | tostring end;
def avg: add / length;

# Why a budgeted metric has no value.
def missing($case; $pick):
  if $case.result == "Skipped" then
    "skipped: " + ([$case | .. | objects | select(.nodeType? | test("Message"; "i")? // false) | .name] | first // "no reason given" | sub("^Test skipped - "; ""))
  elif $case.result == "Failed" then "test failed"
  elif ($pick | test("hitch")) and $kind == "simulator" then "n/a on simulator"
  else "not reported" end;

([$tests | .. | objects | select(.nodeType? == "Test Case") | {key: .nodeIdentifier, value: .}] | from_entries) as $cases
| (map({key: .testIdentifier, value: [.testRuns[].metrics[]]}) | from_entries) as $metrics
| (budgets | map(.test) | reduce .[] as $t ([]; if index([$t]) then . else . + [$t] end)) as $known
| ($known + ($cases | keys | map(select(IN($known[]) | not))))[]
| . as $test
| select($cases[$test] != null)
| $cases[$test] as $case
| ($metrics[$test] // []) as $found
| (budgets | map(select(.test == $test))) as $rows
| (
    ($rows[] as $row
      | ([$found[] | select(matches($row.pick))] | first) as $metric
      | [ ($test | interaction) + ": " + $row.what,
          (if $metric == null then "-"
           elif $row.max then ($metric | values | max | num) + " " + ($metric | unit) + " (avg " + ($metric | values | avg | num) + ")"
           else ($metric | values | avg | num) + " " + ($metric | unit) end),
          (if $row.budget then ($row.budget | tostring) + " " + (if $row.pick | test("hitch") then "ms/s" else "ms" end) else "-" end),
          (if $metric == null then missing($case; $row.pick)
           elif $row.budget == null then "-"
           elif ($metric | values | if $row.max then max else avg end) <= $row.budget then "pass"
           else "FAIL" end)
        ] | @tsv),
    # The rest, except what's always 0 or repeats a row above.
    ($found[] | select(. as $m | $rows | all(. as $row | $m | matches($row.pick) | not))
      | select(.displayName | test("Frame Count|Hitches Total Duration|Hitch Time Ratio|\\(field\\)$") | not)
      | [ ($test | interaction) + ": " + .displayName, (values | avg | num) + " " + unit, "-", "-" ] | @tsv),
    (if ($rows | length) == 0 and ($found | length) == 0 then
       [ ($test | interaction), "-", "-", missing($case; "") ] | @tsv
     else empty end)
  )
