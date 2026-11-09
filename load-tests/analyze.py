#!/usr/bin/env python3
"""Turn a k6 run into report tables: 10-second latency/error buckets and pod usage.

Usage: python3 load-tests/analyze.py load-tests/results/<label>
Writes analysis.md into that directory.
"""
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

BUCKET_SECONDS = 10


def percentile(ordered, fraction):
    if not ordered:
        return 0.0
    return ordered[min(len(ordered) - 1, int(len(ordered) * fraction))]


def bucket_table(path):
    durations, failed, total = defaultdict(list), defaultdict(int), defaultdict(int)
    start = None
    with open(path, newline="") as handle:
        for row in csv.DictReader(handle):
            stamp = int(float(row["timestamp"]))
            start = stamp if start is None else min(start, stamp)
            value = float(row["metric_value"])
            if row["metric_name"] == "http_req_duration":
                durations[stamp].append(value)
            elif row["metric_name"] == "http_req_failed":
                total[stamp] += 1
                failed[stamp] += int(value)

    groups = defaultdict(lambda: {"d": [], "f": 0, "t": 0})
    for stamp, values in durations.items():
        groups[(stamp - start) // BUCKET_SECONDS]["d"].extend(values)
    for stamp, count in total.items():
        group = groups[(stamp - start) // BUCKET_SECONDS]
        group["t"] += count
        group["f"] += failed[stamp]

    lines = [
        "| Window (s) | Req/s | Error % | p50 (ms) | p95 (ms) | p99 (ms) |",
        "|---|---|---|---|---|---|",
    ]
    for key in sorted(groups):
        group = groups[key]
        ordered = sorted(group["d"])
        rate = group["t"] / BUCKET_SECONDS
        errors = 100 * group["f"] / group["t"] if group["t"] else 0
        lines.append(
            f"| {key * BUCKET_SECONDS}-{(key + 1) * BUCKET_SECONDS} | {rate:.1f} | {errors:.2f} "
            f"| {percentile(ordered, .5):.0f} | {percentile(ordered, .95):.0f} "
            f"| {percentile(ordered, .99):.0f} |"
        )
    return lines


def usage_table(path):
    cpu, memory = defaultdict(list), defaultdict(list)
    for line in Path(path).read_text().splitlines():
        match = re.match(r"(\S+)\s+(\d+)m\s+(\d+)Mi", line)
        if match:
            cpu[match[1]].append(int(match[2]))
            memory[match[1]].append(int(match[3]))
    lines = [
        "| Pod | CPU avg (m) | CPU peak (m) | Memory avg (Mi) | Memory peak (Mi) |",
        "|---|---|---|---|---|",
    ]
    for pod in sorted(cpu):
        lines.append(
            f"| {pod} | {sum(cpu[pod]) / len(cpu[pod]):.0f} | {max(cpu[pod])} "
            f"| {sum(memory[pod]) / len(memory[pod]):.0f} | {max(memory[pod])} |"
        )
    return lines


def main():
    out = Path(sys.argv[1])
    text = ["## Latency and errors over time", ""]
    text += bucket_table(out / "metrics.csv")
    text += ["", "## Pod resource usage (kubectl top, sampled every 5 s)", ""]
    text += usage_table(out / "kubectl-top.txt")
    (out / "analysis.md").write_text("\n".join(text) + "\n")
    print("\n".join(text))


if __name__ == "__main__":
    main()
