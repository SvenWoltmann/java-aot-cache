#!/usr/bin/env bash
#
# Third follow-up to run-method-profiling-measurements.sh: does the lasting
# gap come from the trap history in the profiles? The method profiles of a
# training run also record where C2 code hit uncommon traps, and C2 avoids the
# same speculation in the production run (Compile::too_many_traps()). A
# training run with -XX:PerMethodTrapLimit=0 -XX:PerMethodSpecTrapLimit=0
# makes C2 skip these speculations from the start, so the run hits almost no
# uncommon traps and the profiles in the cache carry almost no trap history.
# The production runs start without these options. Uses the programs and
# caches of the main script in target/method-profiling/.
#
# Usage: scripts/run-method-profiling-traps.sh <path-to-jdk-28> <machine-id>
#
# Runs about 8 minutes.

set -euo pipefail

jdk28=$1
machine_id=$2
out="results/method-profiling/$machine_id"
work="target/method-profiling"

cd "$(dirname "$0")/.."
java28="$jdk28/bin/java"
no_replay="-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining"
compile28="-cp $work/28/AotCompile.jar AotCompile"

echo "Trap history, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

"$java28" -XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching \
  -XX:+UnlockExperimentalVMOptions -XX:PerMethodTrapLimit=0 -XX:PerMethodSpecTrapLimit=0 \
  -XX:AOTCacheOutput="$work/28/compile-t20-notraps.aot" $compile28 20 \
  > "$work/28/compile-t20-notraps.aot.log" 2>&1

echo "== Java 28, cache from a training run without trap history, 15 runs of 100 iterations"
python3 -I scripts/measure.py "$out/trap-history.csv" 15 \
  --blocks 1-1,2-5,6-10,11-20,21-30,31-40,41-60,61-80,81-100 \
  "none=$java28 $compile28 100" \
  "noreplay=$java28 $no_replay -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  "training20=$java28 -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  "training20-notraps=$java28 -XX:AOTCache=$work/28/compile-t20-notraps.aot $compile28 100" \
  | sed -e "s|$java28|java28|g" > "$out/trap-history-summary.txt"

echo "== LogCompilation with the cache without trap history"
"$java28" -XX:+UnlockDiagnosticVMOptions -XX:AOTCache="$work/28/compile-t20-notraps.aot" \
  -XX:+LogCompilation -XX:LogFile="$work/logcompilation-java28-notraps.xml" $compile28 100 > /dev/null
python3 -I scripts/analyze-logcompilation.py "$work/logcompilation-java28-notraps.xml" \
  > "$out/logcompilation-java28-training20-notraps.txt"

echo "Trap history, load at end: $(uptime)" >> "$out/environment.txt"
echo "Done: $out"
