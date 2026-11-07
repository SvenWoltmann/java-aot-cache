"""Compares where AotCompile spends its time in two or more variants, from JFR execution samples.

Usage:
  python3 analyze-jfr-samples.py <label>=<json-file>[,<json-file>...] ...

Each JSON file is the output of
  jfr print --json --stack-depth 64 --events jdk.ExecutionSample,jdk.ThreadAllocationStatistics <file.jfr>
of one run. The script prints per variant:

* the samples per run,
* the share of samples by the kind of code the thread was executing (interpreted,
  JIT compiled, native) -- the first frame that is not inlined,
* the bytes the main thread allocated during the whole run,
* the 30 leaf methods (top frame, inlined or not) with the most samples, with the
  share of samples in each variant.

Shares instead of absolute numbers: a variant that runs slower collects more
samples in the same window. If every method is slower by the same factor, the
shares stay the same; if the extra time sits in a few methods, their shares grow.
"""

import collections
import json
import statistics
import sys


def name(frame):
    method = frame["method"]
    return f"{method['type']['name'].replace('/', '.')}.{method['name']}"


def load(paths):
    leaf = collections.Counter()
    kind = collections.Counter()
    samples_per_run = []
    allocated = []
    for path in paths:
        with open(path) as file:
            events = json.load(file)["recording"]["events"]
        samples = 0
        main_allocated = 0
        for event in events:
            values = event["values"]
            if event["type"] == "jdk.ThreadAllocationStatistics":
                if (values.get("thread") or {}).get("javaName") == "main":
                    main_allocated = max(main_allocated, values["allocated"])
                continue
            frames = values["stackTrace"]["frames"]
            if not frames:
                continue
            samples += 1
            leaf[name(frames[0])] += 1
            executing = next((f for f in frames if f["type"] != "Inlined"), frames[-1])
            kind[executing["type"]] += 1
        samples_per_run.append(samples)
        allocated.append(main_allocated)
    return leaf, kind, samples_per_run, allocated


def main():
    variants = []
    for argument in sys.argv[1:]:
        label, files = argument.split("=", 1)
        variants.append((label, *load(files.split(","))))

    for label, leaf, kind, samples_per_run, allocated in variants:
        total = sum(kind.values())
        print(f"{label}: {len(samples_per_run)} runs, samples per run "
              f"{' '.join(map(str, samples_per_run))}")
        print("  executing frame: " + ", ".join(
            f"{k} {100 * v / total:.1f} %" for k, v in kind.most_common()))
        print(f"  allocated by the main thread per run [MB]: "
              f"{' '.join(f'{a / 1e6:.0f}' for a in allocated)}"
              f" (median {statistics.median(allocated) / 1e6:.0f})")

    combined = collections.Counter()
    for _, leaf, *_ in variants:
        total = sum(leaf.values())
        for method, count in leaf.items():
            combined[method] += count / total
    print("\nLeaf methods with the most samples, share of all samples in % per variant:")
    print("  " + "".join(f"{label:>10}" for label, *_ in variants) + "  method")
    for method, _ in combined.most_common(30):
        shares = []
        for _, leaf, *_ in variants:
            shares.append(100 * leaf[method] / sum(leaf.values()))
        print("  " + "".join(f"{share:10.2f}" for share in shares) + f"  {method}")

    if len(variants) == 2:
        (label_a, leaf_a, *_), (label_b, leaf_b, *_) = variants
        total_a, total_b = sum(leaf_a.values()), sum(leaf_b.values())
        differences = sorted(
            ((leaf_b[m] / total_b - leaf_a[m] / total_a) * 100, m) for m in set(leaf_a) | set(leaf_b)
        )
        print(f"\nLargest differences in share, {label_b} minus {label_a}, in percentage points:")
        for difference, method in differences[-12:][::-1]:
            print(f"  {difference:+6.2f}  {method}")
        print("  ...")
        for difference, method in differences[:12][::-1]:
            print(f"  {difference:+6.2f}  {method}")


if __name__ == "__main__":
    main()
