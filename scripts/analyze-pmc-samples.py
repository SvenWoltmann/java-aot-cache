"""Cycles and instructions of the main thread of AotCompile, from an Instruments recording.

Usage:
  python3 analyze-pmc-samples.py <seconds> <label>=<xml>:<out>[,<xml>:<out>...] ...

Each XML file is the export of the table "kdebug-counters-with-kdebug-sample"
of one recording made with the template "CPU Counters":

  xcrun xctrace export --input <file.trace> \\
    --xpath '/trace-toc/run[@number="1"]/data/table[@schema="kdebug-counters-with-kdebug-sample"]'

and <out> is the program output of the same run (the "Iteration N: X ms" lines).

Every row is a kernel trace event of a thread of the process, with the values
of the core's performance counters at that moment. The counters run per core,
not per thread, so the script only adds up the difference between two
consecutive events of the main thread on the same core, both "Running", at
most 20 ms apart. The counters count only user mode (EL0), and the main
thread is busy all the time, so in between it ran on that core; the
kernel samples it about every 10 ms. The first two
counters are the fixed counters of Apple silicon: cycles and instructions
(at about 1 kHz sampling, their ratio gives 3 to 5 GHz and an IPC of 2 to 3,
which fits only this way round).

Per run, the script takes the last <seconds> of the main thread's events and
divides by the number of iterations in that time (from the program output,
counted backwards from the last iteration).
"""

import collections
import re
import statistics
import sys

ROW = re.compile(r"<row>(.*?)</row>")
TIME_ID = re.compile(r'<event-time id="(\d+)"[^>]*>(\d+)</event-time>')
TIME_REF = re.compile(r'<event-time ref="(\d+)"/>')
THREAD_ID = re.compile(r'<thread id="(\d+)" fmt="([^"]*)"')
THREAD_REF = re.compile(r'<thread ref="(\d+)"/>')
CORE_ID = re.compile(r'<core id="(\d+)" fmt="[^"]*">(\d+)</core>')
CORE_REF = re.compile(r'<core ref="(\d+)"/>')
STATE_ID = re.compile(r'<thread-state id="(\d+)" fmt="([^"]*)"')
STATE_REF = re.compile(r'<thread-state ref="(\d+)"/>')
PMC_ID = re.compile(r'<pmc-events id="(\d+)"[^>]*>([\d ]+)</pmc-events>')
PMC_REF = re.compile(r'<pmc-events ref="(\d+)"/>')


def lookup(row, id_pattern, ref_pattern, table):
    match = id_pattern.search(row)
    if match:
        table[match.group(1)] = match.group(2)
        return match.group(2)
    match = ref_pattern.search(row)
    return table.get(match.group(1)) if match else None


def main_thread_events(path):
    """Events of the thread that runs main(). Instruments names it "java": the
    launcher starts main() in a new thread, and the JVM gives its own threads
    names starting with "Java: ". Of the threads named "java", the one with
    the most events is the one that runs the program."""
    threads, cores, states, pmcs, times = {}, {}, {}, {}, {}
    events = collections.defaultdict(list)
    with open(path) as file:
        for line in file:
            for row in ROW.findall(line):
                time = lookup(row, TIME_ID, TIME_REF, times)
                thread = lookup(row, THREAD_ID, THREAD_REF, threads)
                core = lookup(row, CORE_ID, CORE_REF, cores)
                state = lookup(row, STATE_ID, STATE_REF, states)
                pmc = lookup(row, PMC_ID, PMC_REF, pmcs)
                if not thread or not thread.startswith("java (") or pmc is None:
                    continue
                values = list(map(int, pmc.split()))
                events[thread].append((int(time), core, state, values[0], values[1]))
    main = max(events.values(), key=len)
    main.sort()
    return main


def iterations_in_last(out_path, milliseconds):
    times = [int(line.split()[2]) for line in open(out_path) if line.startswith("Iteration")]
    total, count = 0.0, 0.0
    for t in reversed(times):
        if total + t > milliseconds:
            return count + (milliseconds - total) / t
        total += t
        count += 1
    return count


def evaluate(xml, out, seconds):
    events = main_thread_events(xml)
    end = events[-1][0]
    start = end - seconds * 1e9
    cycles = instructions = covered = 0
    for (t0, c0, s0, cy0, in0), (t1, c1, s1, cy1, in1) in zip(events, events[1:]):
        if t0 < start or c0 != c1 or s0 != "Running" or s1 != "Running" or t1 - t0 > 20e6:
            continue
        cycles += cy1 - cy0
        instructions += in1 - in0
        covered += t1 - t0
    iterations = iterations_in_last(out, seconds * 1000)
    coverage = covered / (seconds * 1e9)
    # Scale to the full window: the pairs that pass the filter cover most, not all, of it.
    return cycles / coverage / iterations, instructions / coverage / iterations, coverage


def main():
    seconds = float(sys.argv[1])
    print(f"Main thread, last {seconds:g} s of each run, per iteration (median over the runs):")
    print(f"  {'variant':<12}{'cycles [M]':>12}{'instr. [M]':>12}{'IPC':>7}{'coverage':>10}  runs")
    for argument in sys.argv[2:]:
        label, pairs = argument.split("=", 1)
        results = [evaluate(*pair.split(":"), seconds) for pair in pairs.split(",")]
        cycles = statistics.median(r[0] for r in results)
        instructions = statistics.median(r[1] for r in results)
        coverage = statistics.median(r[2] for r in results)
        ipc = statistics.median(r[1] / r[0] for r in results)
        print(f"  {label:<12}{cycles / 1e6:12.1f}{instructions / 1e6:12.1f}{ipc:7.3f}"
              f"{coverage:10.2f}  {len(results)}")
        for r in results:
            print(f"    run: {r[0] / 1e6:8.1f} {r[1] / 1e6:8.1f} {r[1] / r[0]:6.3f} {r[2]:6.2f}")


if __name__ == "__main__":
    main()
