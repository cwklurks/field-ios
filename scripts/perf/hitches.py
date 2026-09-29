# /// script
# requires-python = ">=3.11"
# ///
"""Hitch time per second of scrolling, from an Animation Hitches trace.

The scroll test marks each stretch of scrolling with a "scroll" signpost from
the test runner; this adds up the hitches that begin inside those stretches.
Usage: uv run --script scripts/perf/hitches.py <trace>
"""
import subprocess
import sys
import xml.etree.ElementTree as ET

SUBSYSTEM = "com.connork.field.perftests"
APP = "Field"  # the process whose hitches count
BUDGET = 2.0  # ms of hitch time per second, docs/PLAN.md "Smooth"


def table(trace, schema):
    """The rows of one table in the trace as {column: element}, or None if it isn't there."""
    xpath = f'/trace-toc/run[@number="1"]/data/table[@schema="{schema}"]'
    export = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--xpath", xpath],
                            capture_output=True, check=True).stdout
    node = ET.fromstring(export).find("node")
    schema = node.find("schema") if node is not None else None
    if node is None or schema is None:
        return None
    columns = [col.findtext("mnemonic") for col in schema.findall("col")]
    # xctrace writes each distinct value once with an id, then refers back to it.
    seen = {}
    rows = []
    for row in node.findall("row"):
        cells = {}
        for column, cell in zip(columns, row):
            if "ref" in cell.attrib:
                cell = seen[cell.attrib["ref"]]
            else:
                for element in cell.iter():
                    if "id" in element.attrib:
                        seen[element.attrib["id"]] = element
            cells[column] = cell
        rows.append(cells)
    return rows


def text(cell):
    return cell.attrib.get("fmt") or cell.text or ""


def nanoseconds(cell):
    return int(cell.text)


def main(trace):
    # Xcode 27 names the intervals table OSSignpostIntervals; older ones, os-signpost-interval.
    signposts = table(trace, "OSSignpostIntervals") or table(trace, "os-signpost-interval")
    # Xcode 27 names the hitches table "hitches", with one row per process a
    # late frame touched; older ones, "hitches-summary".
    hitches = table(trace, "hitches")
    if hitches is None:
        hitches = table(trace, "hitches-summary")
    if hitches is None:
        toc = subprocess.run(["xcrun", "xctrace", "export", "--input", trace, "--toc"],
                             capture_output=True, check=True).stdout
        found = sorted({t.get("schema", "") for t in ET.fromstring(toc).iter("table") if "hitch" in t.get("schema", "").lower()})
        sys.exit("The trace has no hitches table; record with the Animation Hitches template on a device. "
                 f"Hitch tables in this trace: {', '.join(found) or 'none'}.")
    windows = [(nanoseconds(row["start"]), nanoseconds(row["duration"]))
               for row in signposts or []
               if text(row["name"]) == "scroll" and text(row["subsystem"]) == SUBSYSTEM]
    if not windows:
        sys.exit("The trace has no scroll signposts: did the scroll test skip? See its log.")

    # Field's hitches only, each once: the process reads "Field (1234)".
    ours = {(nanoseconds(row["start"]), nanoseconds(row["duration"])) for row in hitches
            if "process" not in row or text(row["process"]).rsplit(" (", 1)[0] == APP}
    inside = [length for begin, length in sorted(ours)
              if any(start <= begin < start + window for start, window in windows)]
    seconds = sum(length for _, length in windows) / 1e9
    hitch_ms = sum(inside) / 1e6
    ratio = hitch_ms / seconds
    print(f"Scrolling:   {len(windows)} stretches, {seconds:.1f} s")
    print(f"Hitches:     {len(inside)}" + (f", worst {max(inside) / 1e6:.1f} ms" if inside else ""))
    print(f"Hitch time:  {hitch_ms:.1f} ms")
    print(f"Hitch ratio: {ratio:.2f} ms/s  (budget {BUDGET:g} ms/s: {'pass' if ratio < BUDGET else 'FAIL'})")
    return 0 if ratio < BUDGET else 1


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    sys.exit(main(sys.argv[1]))
