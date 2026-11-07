"""Compares the inlining decisions of C2 in two -XX:+LogCompilation files of AotCompile.

Usage: python3 compare-inlining.py <log-a> <log-b> [<method-substring> ...]

For every method, the script takes the last successful C2 compilation (level 4,
no OSR) in each log and lists its call sites: the path of inlined methods from
the compiled method to the call, the bytecode index, the callee, and C2's
decision with the reason. A call site is the same in both logs if path, index
and callee match.

It prints how many call sites C2 inlined in A but not in B, grouped by B's
reason, and the other way round. With method substrings, it also lists these
call sites for the compiled methods whose name contains one of them.
"""

import collections
import html
import re
import sys

ATTRIBUTE = re.compile(r"(\w+)='([^']*)'")


def attributes(line):
    return {k: html.unescape(v) for k, v in ATTRIBUTE.findall(line)}


def parse(path):
    """Returns {root method: {site: (decision, reason, count, callee info)}}."""
    last = {}
    with open(path, errors="replace") as log:
        task = None
        for line in log:
            if line.startswith("<task "):
                a = attributes(line)
                if "level" in a or "osr_bci" in a:
                    task = None
                    continue
                task = {"root": a["method"], "klass": {}, "method": {}, "stack": [],
                        "bci": None, "pending": None, "sites": {}, "ok": False}
                continue
            if task is None:
                continue
            if line.startswith("<klass "):
                a = attributes(line)
                task["klass"][a["id"]] = a["name"]
            elif line.startswith("<method "):
                a = attributes(line)
                holder = task["klass"].get(a["holder"], "?")
                task["method"][a["id"]] = (f"{holder}::{a['name']}({a.get('bytes', '?')})",
                                           a.get("compile_kind", ""), a.get("level", ""))
            elif line.startswith("<parse method="):
                a = attributes(line)
                task["stack"].append(task["method"].get(a["method"], ("?",))[0])
            elif line.startswith("</parse>"):
                if task["stack"]:
                    task["stack"].pop()
            elif line.startswith("<bc "):
                task["bci"] = attributes(line).get("bci")
            elif line.startswith("<call "):
                a = attributes(line)
                callee = task["method"].get(a["method"], ("?", "", ""))
                site = (tuple(task["stack"]), task["bci"], callee[0])
                task["pending"] = (site, int(a.get("count", -1)), callee)
            elif line.startswith("<inline_success") or line.startswith("<inline_fail"):
                if task["pending"]:
                    site, count, callee = task["pending"]
                    decision = "inline" if line.startswith("<inline_success") else "fail"
                    task["sites"].setdefault(site, (decision, attributes(line).get("reason", ""),
                                                    count, callee))
                    task["pending"] = None
            elif line.startswith("<task_done"):
                task["ok"] = attributes(line).get("success") == "1"
            elif line.startswith("</task>"):
                if task["ok"]:
                    last[task["root"]] = task["sites"]
                task = None
    return last


def main():
    a_log, b_log, filters = sys.argv[1], sys.argv[2], sys.argv[3:]
    a, b = parse(a_log), parse(b_log)
    common = sorted(set(a) & set(b))
    print(f"A: {a_log}\nB: {b_log}")
    print(f"Methods compiled by C2 in both: {len(common)} (only A: {len(set(a) - set(b))},"
          f" only B: {len(set(b) - set(a))})")

    for first, second, name_first, name_second in ((a, b, "A", "B"), (b, a, "B", "A")):
        reasons = collections.Counter()
        examples = collections.defaultdict(list)
        for root in common:
            for site, (decision, reason, count, callee) in first[root].items():
                other = second[root].get(site)
                if decision == "inline" and other and other[0] == "fail":
                    reasons[other[1]] += 1
                    examples[root].append((site, reason, other, count))
        print(f"\nCall sites inlined in {name_first} but not in {name_second},"
              f" by {name_second}'s reason ({sum(reasons.values())} in total):")
        for reason, n in reasons.most_common(12):
            print(f"  {n:6d}  {reason}")
        if filters:
            for root, items in examples.items():
                if any(f in root for f in filters):
                    print(f"\n  {root}")
                    for (path, bci, callee), reason, other, count in items[:15]:
                        where = " > ".join(p.split("::")[-1] for p in path[1:]) or "(top)"
                        print(f"    bci {bci} in {where}: {callee}  {name_first}: {reason}"
                              f" [count {count}]  {name_second}: {other[1]} [count {other[2]}],"
                              f" callee {other[3][1]} level {other[3][2]}")


if __name__ == "__main__":
    main()
