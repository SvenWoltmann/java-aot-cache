"""Counts the compilation events in a -XX:+PrintCompilation log of AotCompile.

Usage: python3 analyze-compilation.py <log-file>

The log must contain the program's "Iteration N" lines, so that each event can
be assigned to the iteration during which it happened. PrintCompilation marks
AOT code with "A", and AOT preload code (with class initialization barriers)
additionally with "P"; the number after the flags is the compilation level.
"""

import collections
import re
import sys

ITERATION = re.compile(r"Iteration\s+(\d+)")
EVENT = re.compile(
    r"\s*\d+\s+\d+\s+([%sbn!AP ]*?)\s*([0-4])\s+(\S+).*?(made not entrant: (.*))?$"
)


def kind_of(flags, level):
    prefix = "AP" if "P" in flags else "A" if "A" in flags else "JIT"
    return f"{prefix}{level}" + ("-OSR" if "%" in flags else "")


def main():
    iteration = 0  # events before the first "Iteration" line happen during iteration 1
    installed = collections.Counter()
    replaced = collections.Counter()
    replaced_a4_per_iteration = collections.Counter()
    events_per_method = collections.defaultdict(list)

    with open(sys.argv[1]) as log:
        for line in log:
            match = ITERATION.match(line)
            if match:
                iteration = int(match.group(1))
                continue
            match = EVENT.match(line)
            if not match:
                continue
            flags, level, method, _, reason = match.groups()
            kind = kind_of(flags, level)
            if reason:
                replaced[(kind, reason.strip())] += 1
                if kind == "A4" and reason.strip() == "not used":
                    replaced_a4_per_iteration[iteration + 1] += 1
            else:
                installed[(kind, "before first output" if iteration == 0 else "later")] += 1
            events_per_method[method].append((iteration, kind, reason))

    print("Installed code by kind and time:")
    for (kind, when), count in sorted(installed.items()):
        print(f"  {kind:<8} {when:<20} {count:6d}")

    print("\nCode made not entrant, by kind and reason:")
    for (kind, reason), count in replaced.most_common():
        print(f"  {kind:<8} {reason:<40} {count:6d}")

    print("\nA4 code replaced ('not used') per iteration:")
    print("  " + " ".join(f"{i}:{n}" for i, n in sorted(replaced_a4_per_iteration.items())))

    # HotSpot prints "made not entrant: not used" for the old code right after it
    # installed the new code, so the replacement is the last install before it.
    successors = collections.Counter()
    for events in events_per_method.values():
        last_install = "none"
        for _, kind, reason in events:
            if not reason:
                last_install = kind
            elif kind == "A4" and reason.strip() == "not used":
                successors[last_install] += 1
    print("\nA4 code replaced ('not used'), by the kind of code that replaced it:")
    for kind, count in successors.most_common():
        print(f"  {kind:<8} {count:6d}")


if __name__ == "__main__":
    main()
