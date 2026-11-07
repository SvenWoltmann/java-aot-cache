"""Summarizes the heap sizing in -Xlog:gc files of AotCompile.

Usage: python3 analyze-gc-log.py <gc-log> ...

For each file: the number of young pauses, the sum of all pause times, and,
for the pauses after second 2 (when the program has warmed up), the median
heap occupancy before the pause (which is about the eden size) and the
median committed heap size.
"""

import re
import statistics
import sys

PAUSE = re.compile(
    r"\[(\d+\.\d+)s\].*Pause Young.*?(\d+)M->(\d+)M\((\d+)M\) (\d+\.\d+)ms"
)


def main():
    print(f"{'log':<32} {'pauses':>6} {'pause sum':>10} {'before GC':>10} {'committed':>10}")
    print(f"{'':<32} {'':>6} {'[ms]':>10} {'[MB]':>10} {'[MB]':>10}")
    for path in sys.argv[1:]:
        pauses = []
        with open(path) as log:
            for line in log:
                match = PAUSE.search(line)
                if match:
                    pauses.append(tuple(float(g) for g in match.groups()))
        late = [p for p in pauses if p[0] >= 2.0]
        name = path.rsplit("/", 1)[-1]
        print(f"{name:<32} {len(pauses):6d} {sum(p[4] for p in pauses):10.1f}"
              f" {statistics.median(p[1] for p in late):10.0f}"
              f" {statistics.median(p[3] for p in late):10.0f}")


if __name__ == "__main__":
    main()
