"""Alternating start-time measurement of several JVM command lines.

Usage:
  python3 measure.py <csv-file> <runs> [--blocks 1-1,2-5,...] <label>=<command> ...

Each round starts every command once, in an order rotated by one per round,
so that no variant always runs first. The script records the wall time of the
whole java process and every "Iteration N: X ms" line the program prints,
writes all values to <csv-file>, and prints the medians.

With --blocks, it also prints, per variant, the median over all runs of the
mean iteration time within each block of iterations.
"""

import csv
import re
import shlex
import statistics
import subprocess
import sys
import time

ITERATION = re.compile(r"Iteration\s+(\d+):\s+(\d+)\s+ms")


def parse_arguments(arguments):
    csv_file, runs, rest = arguments[0], int(arguments[1]), arguments[2:]
    blocks = []
    if rest and rest[0] == "--blocks":
        blocks = [tuple(map(int, block.split("-"))) for block in rest[1].split(",")]
        rest = rest[2:]
    variants = [argument.split("=", 1) for argument in rest]
    return csv_file, runs, blocks, variants


def run_once(label, command):
    start = time.perf_counter_ns()
    result = subprocess.run(shlex.split(command), capture_output=True, text=True)
    wall_ms = (time.perf_counter_ns() - start) / 1e6
    if result.returncode != 0:
        sys.exit(f"{label} failed:\n{result.stderr}")
    row = {"variant": label, "wall_ms": round(wall_ms, 1)}
    for match in ITERATION.finditer(result.stdout):
        row[f"it{match.group(1)}"] = int(match.group(2))
    return row


def quartiles(values):
    q1, median, q3 = statistics.quantiles(values, n=4)
    return f"{q1:.1f} / {median:.1f} / {q3:.1f}"


def main():
    csv_file, runs, blocks, variants = parse_arguments(sys.argv[1:])

    rows = []
    for run in range(runs):
        shift = run % len(variants)
        for label, command in variants[shift:] + variants[:shift]:
            rows.append({"run": run, **run_once(label, command)})

    iteration_keys = sorted(
        {key for row in rows for key in row if key.startswith("it")},
        key=lambda key: int(key[2:]),
    )
    with open(csv_file, "w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=["run", "variant", "wall_ms", *iteration_keys])
        writer.writeheader()
        writer.writerows(rows)

    print(f"{csv_file}: {runs} runs per variant, quartiles Q1 / median / Q3")
    for label, command in variants:
        own = [row for row in rows if row["variant"] == label]
        print(f"\n{label}: {command}")
        print(f"  wall time [ms]:      {quartiles([row['wall_ms'] for row in own])}")
        if iteration_keys:
            print(f"  iteration 1 [ms]:    {quartiles([row['it1'] for row in own])}")
            medians = [statistics.median(row[key] for row in own) for key in iteration_keys]
            print("  median per iteration [ms]: " + " ".join(f"{m:g}" for m in medians))
        for first, last in blocks:
            means = [statistics.mean(row[f"it{k}"] for k in range(first, last + 1)) for row in own]
            print(f"  iterations {first}-{last}, mean per iteration [ms]: {quartiles(means)}")


if __name__ == "__main__":
    main()
