#!/usr/bin/env bash
#
# Follow-up to run-method-profiling-measurements.sh: where the lasting gap
# with method profiles comes from, and why Java 25 profits in iteration 1
# while Java 28 loses. Uses the programs and caches of the main script in
# target/method-profiling/, so run that one first.
#
# Usage: scripts/run-method-profiling-followup.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>
#
# Runs about 10 minutes.

set -euo pipefail

jdk28=$1
jdk25=$2
machine_id=$3
out="results/method-profiling/$machine_id"
work="target/method-profiling"

cd "$(dirname "$0")/.."
java28="$jdk28/bin/java"
java25="$jdk25/bin/java"
no_replay="-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining"
compile28="-cp $work/28/AotCompile.jar AotCompile"
compile25="-cp $work/25/AotCompile.jar AotCompile"

echo "Follow-up, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

echo "== Heap sizing: one run of 100 iterations per variant with -Xlog:gc"
gc_run() { # <name> <java> [java options...] -- program in $program
  local name=$1 java=$2
  shift 2
  "$java" "$@" -Xlog:gc:file="$work/gc-$name.log" $program 100 > /dev/null
}
program=$compile28
gc_run java28-none "$java28"
gc_run java28-noreplay "$java28" $no_replay -XX:AOTCache="$work/28/compile-t20.aot"
gc_run java28-training20 "$java28" -XX:AOTCache="$work/28/compile-t20.aot"
gc_run java28-training100 "$java28" -XX:AOTCache="$work/28/compile-t100.aot"
program=$compile25
gc_run java25-none "$java25"
gc_run java25-noreplay "$java25" $no_replay -XX:AOTCache="$work/25/compile-t20.aot"
gc_run java25-training20 "$java25" -XX:AOTCache="$work/25/compile-t20.aot"
python3 -I scripts/analyze-gc-log.py "$work"/gc-java28-*.log "$work"/gc-java25-*.log > "$out/gc-heap-sizing.txt"

echo "== Java 28 with a fixed heap (-Xms2g -Xmx2g -Xmn512m), 15 runs of 100 iterations"
fixed="-Xms2g -Xmx2g -Xmn512m"
python3 -I scripts/measure.py "$out/fixed-heap.csv" 15 \
  --blocks 1-1,2-5,6-10,11-20,21-30,31-40,41-60,61-80,81-100 \
  "none=$java28 $fixed $compile28 100" \
  "noreplay=$java28 $fixed $no_replay -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  "training20=$java28 $fixed -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  "training100=$java28 $fixed -XX:AOTCache=$work/28/compile-t100.aot $compile28 100" \
  | sed -e "s|$java28|java28|g" > "$out/fixed-heap-summary.txt"

echo "== LogCompilation on Java 25, one run of 100 iterations per variant"
for variant in noreplay training20; do
  options=()
  [[ $variant == noreplay ]] && options=($no_replay)
  "$java25" -XX:+UnlockDiagnosticVMOptions ${options[@]+"${options[@]}"} \
    -XX:AOTCache="$work/25/compile-t20.aot" -XX:+LogCompilation \
    -XX:LogFile="$work/logcompilation-java25-$variant.xml" $compile25 100 > /dev/null
  python3 -I scripts/analyze-logcompilation.py "$work/logcompilation-java25-$variant.xml" \
    > "$out/logcompilation-java25-$variant.txt"
done

echo "Follow-up, load at end: $(uptime)" >> "$out/environment.txt"
echo "Done: $out"
