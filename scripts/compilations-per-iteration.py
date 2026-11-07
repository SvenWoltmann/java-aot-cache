"""Counts the JIT compilations per iteration and level in a -XX:+PrintCompilation log of AotCompile.

Usage: python3 compilations-per-iteration.py <log-file>

The log must contain the program's "Iteration N" lines. An event belongs to the
iteration whose "Iteration N" line follows it, so events before the first line
count for iteration 1. Native method wrappers (level 0) and OSR compilations
are counted separately; "made not entrant" lines are not compilations.
"""

import collections
import re
import sys

ITERATION = re.compile(r"Iteration\s+(\d+)")
EVENT = re.compile(r"\s*\d+\s+\d+\s+([%sbn!AP ]*?)\s*([0-4])\s+(\S+)")
BLOCKS = [(1, 1), (2, 2), (3, 3), (4, 5), (6, 10), (11, 15), (16, 20), (21, 25), (26, 30), (31, 40),
          (41, 50), (51, 60), (61, 70), (71, 80), (81, 90), (91, 100)]


def main():
    counts = collections.defaultdict(collections.Counter)  # iteration -> kind -> count
    iteration = 1
    last_iteration = 0
    with open(sys.argv[1]) as log:
        for line in log:
            match = ITERATION.match(line)
            if match:
                last_iteration = int(match.group(1))
                iteration = last_iteration + 1
                continue
            if "made not entrant" in line or "made zombie" in line:
                continue
            match = EVENT.match(line)
            if not match:
                continue
            flags, level = match.group(1), int(match.group(2))
            if "n" in flags:
                kind = "native"
            elif "%" in flags:
                kind = "OSR"
            else:
                kind = f"level {level}"
            counts[iteration][kind] += 1

    kinds = ["level 1", "level 2", "level 3", "level 4", "OSR"]
    print("Compilations per iteration and level (an event belongs to the iteration it happened in)")
    print(f"  {'iterations':<12}" + "".join(f"{kind:>9}" for kind in kinds))
    for first, last in BLOCKS:
        if first > last_iteration:
            break
        last = min(last, last_iteration)
        total = collections.Counter()
        for i in range(first, last + 1):
            total.update(counts[i])
        label = f"{first}" if first == last else f"{first}-{last}"
        print(f"  {label:<12}" + "".join(f"{total[kind]:9d}" for kind in kinds))
    after = collections.Counter()
    for i, counter in counts.items():
        if i > last_iteration:
            after.update(counter)
    print(f"  {'after last':<12}" + "".join(f"{after[kind]:9d}" for kind in kinds))


if __name__ == "__main__":
    main()
