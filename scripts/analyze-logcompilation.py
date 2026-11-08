"""Evaluates a -XX:+LogCompilation file of AotCompile.

Usage:
  python3 analyze-logcompilation.py <log-file> [<method-list-file>]

Prints, for all C2 compilations (level 4, no OSR) and separately for the last
C2 compilation of each method:

* how many compilations started with trap history in the method profile
  ("observe trap ... total" at the start of parsing: the profile already
  records deoptimizations at this method),
* decompiles recorded in the profile when the task was queued,
* how often C2 decided against a speculation because the profile reports a
  trap at this bytecode or too many traps in the method ("observe trap" during
  parsing; C2 then compiles the general path instead of an uncommon trap),
* the virtual call sites by their type profile: whether one or two receiver
  types cover at least 90 % of the profiled calls (TypeProfileMajorReceiverPercent),
  or the profile has seen more types,
* the inlining decisions by reason,
* the uncommon traps that the compiled code hit at runtime, by reason,
* per compilation level and time window after JVM start: how many tasks were
  queued, how long they waited in the queue, and how much compiler-thread time
  the compilations took,
* the level of the code each method ends with (the newest code that was not
  made not entrant).

With a method-list file (one method per line, in LogCompilation notation such
as "java.util.HashMap getNode (Ljava/lang/Object;)Ljava/util/HashMap$Node;"),
it also prints, per listed method, the facts of its last C2 compilation.
"""

import collections
import html
import re
import sys

ATTRIBUTE = re.compile(r"(\w+)='([^']*)'")


def attributes(line):
    return {key: html.unescape(value) for key, value in ATTRIBUTE.findall(line)}


WINDOWS = [(0.0, 0.25), (0.25, 0.5), (0.5, 1.0), (1.0, 2.0), (2.0, 1e9)]


def parse(path):
    level_of = {}  # compile_id -> level, from <task_queued> and <nmethod>
    queued = {}  # compile_id -> (level, stamp, reason), without OSR tasks
    nmethods = {}  # compile_id -> (method, level), without OSR code
    not_entrant = set()
    tasks = []
    traps_at_runtime = collections.Counter()
    current = None
    with open(path, errors="replace") as log:
        for line in log:
            if line.startswith("<task_queued "):
                a = attributes(line)
                # LogCompilation omits the level of C2 tasks (the highest level).
                level = int(a.get("level", 4))
                level_of.setdefault(a["compile_id"], level)
                if "osr_bci" not in a:
                    queued[a["compile_id"]] = (level, float(a["stamp"]), a.get("comment", "?"))
            elif line.startswith("<nmethod "):
                a = attributes(line)
                if "level" in a and "compile_id" in a:
                    level_of.setdefault(a["compile_id"], int(a["level"]))
                    if a.get("compile_kind") != "osr":
                        nmethods[a["compile_id"]] = (a["method"], int(a["level"]))
            elif line.startswith("<make_not_entrant "):
                not_entrant.add(attributes(line).get("compile_id"))
            elif line.startswith("<uncommon_trap thread=") and "compile_id=" in line:
                a = attributes(line)
                if a.get("compiler") == "c2" and "count" in a:
                    traps_at_runtime[a["reason"]] += 1
            elif line.startswith("<task "):
                a = attributes(line)
                current = {
                    "id": a["compile_id"],
                    "method": a["method"],
                    "osr": "osr_bci" in a,
                    "decompiles": int(a.get("decompiles", 0)),
                    "stamp": float(a["stamp"]),
                    "history": 0,
                    "too_many_traps": collections.Counter(),
                    "inline": collections.Counter(),
                    "calls": collections.Counter(),
                    "nmsize": 0,
                    "inlined_bytes": 0,
                    "success": False,
                    "done": None,
                }
            elif current is None:
                continue
            elif line.startswith("<observe trap="):
                a = attributes(line)
                if "total" in a:
                    current["history"] += 1
                else:
                    current["too_many_traps"][a["trap"]] += 1
            elif line.startswith("<call ") and "virtual='1'" in line:
                a = attributes(line)
                count = int(a.get("count", 0))
                profiled = int(a.get("receiver_count", 0)) + int(a.get("receiver2_count", 0))
                if count <= 0:
                    kind = "never executed"
                elif "receiver" not in a:
                    kind = "no receiver type in the profile"
                elif profiled >= 0.9 * count:
                    kind = "receiver types cover >= 90 % of the calls"
                else:
                    kind = "receiver types cover < 90 % of the calls"
                current["calls"][kind] += 1
                current["calls"][kind + " (calls)"] += max(count, 0)
            elif line.startswith("<inline_success") or line.startswith("<inline_fail"):
                a = attributes(line)
                kind = "inline" if line.startswith("<inline_success") else "fail"
                current["inline"][f"{kind}: {a.get('reason', '?')}"] += 1
            elif line.startswith("<task_done"):
                a = attributes(line)
                current["success"] = a.get("success") == "1"
                current["nmsize"] = int(a.get("nmsize", 0))
                current["inlined_bytes"] = int(a.get("inlined_bytes", 0))
                current["done"] = float(a["stamp"])
            elif line.startswith("</task>"):
                current["level"] = level_of.get(current["id"], -1)
                tasks.append(current)
                current = None
    final_level = {}
    for compile_id, (method, level) in nmethods.items():
        if compile_id in not_entrant:
            continue
        if method not in final_level or int(compile_id) > final_level[method][0]:
            final_level[method] = (int(compile_id), level)
    return tasks, traps_at_runtime, queued, final_level


def quantile(values, q):
    values = sorted(values)
    return values[min(len(values) - 1, int(q * len(values)))] if values else 0.0


def print_queue(tasks, queued):
    started = {t["id"]: t for t in tasks}
    print("\nCompile queue and compiler-thread time per level and window after JVM start")
    print("  (queued tasks, of which queued without an invocation (reason must_be_compiled);")
    print("  median / 90th percentile of the queue wait in ms, of all tasks and of the tasks")
    print("  queued with an invocation (not must_be_compiled); sum of compilation times in ms):")
    for level in (1, 2, 3, 4):
        print(f"  level {level}:")
        for first, last in WINDOWS:
            ids = [i for i, (lv, st, _) in queued.items() if lv == level and first <= st < last]
            eager = sum(1 for i in ids if queued[i][2] == "must_be_compiled")
            waits = [(started[i]["stamp"] - queued[i][1]) * 1000 for i in ids if i in started]
            invoked = [(started[i]["stamp"] - queued[i][1]) * 1000 for i in ids
                       if i in started and queued[i][2] != "must_be_compiled"]
            busy = sum((started[i]["done"] - started[i]["stamp"]) * 1000
                       for i in ids if i in started and started[i]["done"] is not None)
            window = f"{first:.2f}-{last:.2f} s" if last < 1e8 else f"{first:.2f} s-end"
            print(f"    {window:<14} queued {len(ids):5d} ({eager:5d})   wait"
                  f" {quantile(waits, 0.5):7.1f} / {quantile(waits, 0.9):7.1f}"
                  f"   invoked {quantile(invoked, 0.5):7.1f} / {quantile(invoked, 0.9):7.1f}"
                  f"   compiling {busy:8.0f}")


def summarize(title, tasks):
    print(f"\n{title}: {len(tasks)} compilations")
    with_history = sum(1 for t in tasks if t["history"])
    with_decompiles = sum(1 for t in tasks if t["decompiles"])
    print(f"  with trap history in the profile:       {with_history:6d}")
    print(f"  with decompiles recorded in the profile: {with_decompiles:6d}")
    too_many = collections.Counter()
    inline = collections.Counter()
    for t in tasks:
        too_many.update(t["too_many_traps"])
        inline.update(t["inline"])
    print(f"  speculations dropped because of traps:   {sum(too_many.values()):6d}")
    for reason, count in too_many.most_common():
        print(f"    {reason:<36} {count:6d}")
    print(f"  code size (nmsize), sum [bytes]:        {sum(t['nmsize'] for t in tasks):9d}")
    print(f"  inlined bytecode, sum [bytes]:          {sum(t['inlined_bytes'] for t in tasks):9d}")
    calls = collections.Counter()
    for t in tasks:
        calls.update(t["calls"])
    print("  virtual call sites by type profile (sites; profiled calls):")
    for kind in ("receiver types cover >= 90 % of the calls",
                 "receiver types cover < 90 % of the calls",
                 "no receiver type in the profile", "never executed"):
        print(f"    {kind:<44} {calls[kind]:6d}  {calls[kind + ' (calls)']:12d}")
    print("  inlining decisions:")
    for reason, count in inline.most_common(14):
        print(f"    {reason:<56} {count:6d}")


def main():
    tasks, traps_at_runtime, queued, final_level = parse(sys.argv[1])
    levels = collections.Counter(level for _, level in final_level.values())
    print("Methods by the level of the code they end with:")
    print("  " + "   ".join(f"level {lv}: {n}" for lv, n in sorted(levels.items())))
    print_queue(tasks, queued)
    c2 = [t for t in tasks if t["level"] == 4 and not t["osr"] and t["success"]]
    summarize("All C2 compilations (level 4, no OSR)", c2)

    last = {}
    for t in c2:
        last[t["method"]] = t
    summarize("Last C2 compilation per method", list(last.values()))

    print("\nUncommon traps hit by C2 code at runtime, by reason:")
    for reason, count in traps_at_runtime.most_common():
        print(f"  {reason:<36} {count:6d}")
    print(f"  {'total':<36} {sum(traps_at_runtime.values()):6d}")

    if len(sys.argv) > 2:
        print("\nLast C2 compilation of selected methods:")
        with open(sys.argv[2]) as file:
            for method in (line.strip() for line in file):
                if not method:
                    continue
                t = last.get(method)
                if t is None:
                    print(f"\n  {method}\n    no C2 compilation")
                    continue
                count = sum(1 for x in c2 if x["method"] == method)
                fails = sum(n for r, n in t["inline"].items() if r.startswith("fail"))
                print(f"\n  {method}\n    C2 compilations: {count}, last at {t['stamp']:.3f} s,"
                      f" nmsize {t['nmsize']}, inlined bytes {t['inlined_bytes']},"
                      f" trap history {'yes' if t['history'] else 'no'},"
                      f" decompiles {t['decompiles']},"
                      f" dropped speculations {sum(t['too_many_traps'].values())},"
                      f" inlining failures {fails}")


if __name__ == "__main__":
    main()
