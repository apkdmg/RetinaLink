#!/usr/bin/env python3
"""Summarize exported Instruments display tables without reading screen pixels.

Export each named XML table with xctrace first. Values are interned across the
entire export, so resolve id/ref before interpreting rows. Frame numbers here
are Instruments identities; correlate them to application sequence separately.
"""
import argparse
import collections
import json
import re
import statistics
import xml.etree.ElementTree as ET
from pathlib import Path


def table(path):
    root = ET.parse(path).getroot()
    ids = {e.get("id"): e for e in root.iter() if e.get("id") is not None}

    def resolve(cell):
        visited = set()
        while cell.get("ref") is not None:
            key = cell.get("ref")
            if key in visited:
                raise ValueError("Cyclic Instruments XML reference")
            visited.add(key)
            cell = ids[key]
        return cell

    result = []
    for node in root.findall("node"):
        columns = [col.findtext("mnemonic") for col in node.find("schema")]
        for row in node.findall("row"):
            result.append({key: {
                "raw": cell.text,
                "fmt": cell.get("fmt", cell.text or ""),
                "tag": cell.tag,
            } for key, source in zip(columns, row) for cell in [resolve(source)]})
    return result


def raw(row, key):
    value = row.get(key)
    return None if value is None or value["tag"] == "sentinel" else value["raw"]


def text(row, key):
    value = row.get(key)
    return "" if value is None or value["tag"] == "sentinel" else value["fmt"]


def number(row, key, default=None):
    value = raw(row, key)
    return default if value is None else float(value)


def distribution(values):
    if not values:
        return {"n": 0}
    ordered = sorted(values)

    def percentile(fraction):
        index = (len(ordered) - 1) * fraction
        lower = int(index)
        return ordered[lower] + (ordered[min(lower + 1, len(ordered) - 1)] - ordered[lower]) * (index - lower)

    return {"n": len(values), "mean": statistics.mean(values), "min": ordered[0],
            "p50": percentile(.5), "p95": percentile(.95), "p99": percentile(.99), "max": ordered[-1]}


def analyze(folder, pid):
    surfaces = table(folder / "displayed-surfaces-interval.xml")
    vsyncs = table(folder / "display-vsyncs-interval.xml")
    frame_pattern = re.compile(r"RetinaLink \(" + re.escape(str(pid)) + r"\):Frame (\d+)")
    timeline = []
    for row in surfaces:
        start = number(row, "start") / 1e9
        duration = number(row, "duration") / 1e9
        latency = number(row, "cpu-to-display-latency")
        timeline.append({"start_s": start, "duration_ms": duration * 1000, "end_s": start + duration,
                         "display": text(row, "display-name"), "surface_id": raw(row, "surface-id"),
                         "connection_uuid": raw(row, "connection-UUID"), "label": text(row, "event-label"),
                         "category": text(row, "category"),
                         "cpu_to_display_ms": None if latency is None else latency / 1e6,
                         "app_frames": [int(x) for x in frame_pattern.findall(text(row, "event-label"))]})
    timeline.sort(key=lambda row: row["start_s"])
    mapped = [row for row in timeline if row["app_frames"]]
    frame_counts = collections.Counter(frame for row in mapped for frame in row["app_frames"])
    frame_ids = sorted(frame_counts)
    first, last = min(frame_ids), max(frame_ids)
    missing = sorted(set(range(first, last + 1)) - set(frame_ids))
    mapped_span = mapped[-1]["end_s"] - mapped[0]["start_s"]
    groups = collections.defaultdict(list)
    for row in vsyncs:
        groups[(text(row, "display-name"), text(row, "event"))].append(number(row, "timestamp") / 1e9)
    refreshes = []
    for (display, event), stamps in sorted(groups.items()):
        stamps = sorted(set(stamps))
        gaps = [(b - a) * 1000 for a, b in zip(stamps, stamps[1:])]
        refreshes.append({"display": display, "event": event, "count": len(stamps),
                          "first_s": stamps[0], "last_s": stamps[-1],
                          "hz_from_elapsed": (len(stamps) - 1) / (stamps[-1] - stamps[0]),
                          "interval_ms": distribution(gaps)})
    submissions_path = folder / "metal-application-command-buffer-submissions.xml"
    submissions = []
    if submissions_path.exists():
        submissions = [row for row in table(submissions_path) if re.search(r"\(" + re.escape(str(pid)) + r"\)$", text(row, "process"))]
    result = {
        "pid": pid, "source": "Xcode Instruments Metal System Trace exported display dependencies and hardware vsync events",
        "limits": [
            "Display dependency mapping is independent of application addPresentedHandler timestamp accounting; it is not a camera or input-to-photon measurement.",
            "Physical swaps alone do not prove unique app content: app frame dependencies in interval labels are counted separately.",
            "Instruments frame numbers are not application sequence numbers until independently joined to submission events.",
            "This is one instrumented short run, not proof of stable long-run 60 fps. Boundary submissions may be displayed outside the captured interval.",
        ],
        "surface_intervals": len(timeline), "mapped_app_intervals": len(mapped),
        "unique_mapped_app_frames": len(frame_ids), "first_app_frame": first, "last_app_frame": last,
        "missing_interior_app_frames": missing,
        "repeated_mapped_app_frames": {str(k): v for k, v in frame_counts.items() if v > 1},
        "mapped_app_span_s": mapped_span, "unique_app_frames_per_covered_second": len(frame_ids) / mapped_span,
        "mapped_surface_duration_ms": distribution([row["duration_ms"] for row in mapped]),
        "cpu_to_display_ms": distribution([row["cpu_to_display_ms"] for row in mapped if row["cpu_to_display_ms"] is not None]),
        "long_mapped_intervals_over_25ms": [row for row in mapped if row["duration_ms"] > 25],
        "refresh_events": refreshes,
        "app_command_buffer_submissions": len(submissions),
        "timeline": timeline,
    }
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--pid", type=int)
    args = parser.parse_args()
    pid = args.pid
    if pid is None:
        toc = ET.parse(args.folder / "instruments-toc.xml")
        pid = int(toc.find(".//target/process").get("pid"))
    result = analyze(args.folder, pid)
    (args.folder / "metal-display-analysis.json").write_text(json.dumps(result, indent=2) + "\n")
    lines = ["# Instruments display analysis", "",
             f"The built-in display track maps {result['unique_mapped_app_frames']} distinct RetinaLink frames "
             f"({result['first_app_frame']}–{result['last_app_frame']}) to display intervals, with "
             f"{len(result['missing_interior_app_frames'])} missing interior frame identities and "
             f"{len(result['repeated_mapped_app_frames'])} repeated identities.", "",
             f"These mapped intervals cover {result['mapped_app_span_s']:.6f} seconds: "
             f"{result['unique_app_frames_per_covered_second']:.3f} distinct app frames per covered second. "
             f"There are {len(result['long_mapped_intervals_over_25ms'])} intervals longer than 25 ms.", ""]
    for refresh in result["refresh_events"]:
        lines.append(f"{refresh['display']} {refresh['event']}: {refresh['count']} events, "
                     f"{refresh['hz_from_elapsed']:.4f} Hz; interval range "
                     f"{refresh['interval_ms']['min']:.4f}–{refresh['interval_ms']['max']:.4f} ms.")
    lines.extend(["", "These are system trace display dependencies, separate from application presentation callbacks. "
                  "Keep callback/frame-sequence correlation in its own analysis; do not infer scanout from GPU completion alone.", ""])
    lines.extend(f"- {limit}" for limit in result["limits"])
    (args.folder / "metal-display-analysis.md").write_text("\n".join(lines) + "\n")
    concise = {key: value for key, value in result.items() if key not in {"timeline", "long_mapped_intervals_over_25ms"}}
    concise["long_mapped_intervals_over_25ms_count"] = len(result["long_mapped_intervals_over_25ms"])
    print(json.dumps(concise, indent=2))


if __name__ == "__main__":
    main()
