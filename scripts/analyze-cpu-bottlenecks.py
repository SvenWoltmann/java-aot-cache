"""Bottleneck shares of the main thread of AotCompile, from an Instruments recording.

Usage:
  python3 analyze-cpu-bottlenecks.py <seconds> <label>=<xml>:<out>[,<xml>:<out>...] ...

Each XML file is the export of the table "CounterMetricByThread" of one
recording made with the template "CPU Counters" (mode "CPU Bottlenecks"):

  xcrun xctrace export --input <file.trace> \\
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="CounterMetricByThread"]'

(<out> is accepted for symmetry with analyze-pmc-samples.py and not used.)

Every row holds the counters of one thread for about one millisecond, as an
array of four values. Instruments' legend for the mode names the metrics
Useful, Instruction Processing Bottleneck, Instruction Delivery Bottleneck
and Discarded Bottleneck; the table definition maps them to the array in
this order (areaGraphSepcIndexTometricIndex). The main thread is the thread
named "java" with the most rows, as in analyze-pmc-samples.py.

The script prints per variant the share of each metric in the sum of all
four within the last <seconds> of the main thread's rows.
"""

import collections
import re
import statistics
import sys

ROW = re.compile(r"<row>(.*?)</row>", re.S)
NAMES = ["useful", "processing", "delivery", "discarded"]


def lookup(row, id_pattern, ref_pattern, table):
    match = re.search(id_pattern, row)
    if match:
        table[match.group(1)] = match.group(2)
        return match.group(2)
    match = re.search(ref_pattern, row)
    return table.get(match.group(1)) if match else None


def main_thread_rows(path):
    threads, starts, arrays = {}, {}, {}
    rows = collections.defaultdict(list)
    for row in ROW.findall(open(path).read()):
        name = lookup(row, r'<thread id="(\d+)" fmt="([^"]*)"', r'<thread ref="(\d+)"/>', threads) or ""
        start = lookup(row, r'<start-time id="(\d+)"[^>]*>(\d+)<', r'<start-time ref="(\d+)"/>', starts)
        values = lookup(row, r'<uint64-array id="(\d+)"[^>]*>([\d ]+)<',
                        r'<uint64-array ref="(\d+)"/>', arrays)
        if name.startswith("java (") and start is not None and values is not None:
            rows[name].append((int(start), list(map(int, values.split()))))
    return max(rows.values(), key=len)


def main():
    seconds = float(sys.argv[1])
    print(f"Main thread, last {seconds:g} s of each run, share of the four bottleneck metrics in %"
          " (median over the runs):")
    print(f"  {'variant':<12}" + "".join(f"{n:>12}" for n in NAMES) + "  rows per run")
    for argument in sys.argv[2:]:
        label, pairs = argument.split("=", 1)
        shares = {name: [] for name in NAMES}
        counts = []
        for pair in pairs.split(","):
            rows = main_thread_rows(pair.split(":")[0])
            end = max(t for t, _ in rows)
            late = [v for t, v in rows if t >= end - seconds * 1e9]
            sums = [sum(v[i] for v in late) for i in range(4)]
            counts.append(len(late))
            for i, name in enumerate(NAMES):
                shares[name].append(100 * sums[i] / sum(sums))
        print(f"  {label:<12}" + "".join(f"{statistics.median(shares[n]):12.1f}" for n in NAMES)
              + "  " + " ".join(map(str, counts)))


if __name__ == "__main__":
    main()
