#!/usr/bin/env bash
#
# Tenth follow-up to run-method-profiling-measurements.sh: the 200-round series
# of long-run.csv on Java 25, without a cache and with a cache from 100
# training rounds. Java 28 keeps lukewarm methods at level 2 until they have
# run as often as in the whole training run, and with the 100-round cache it
# falls behind the run without a cache from round 121 on. Java 25 delays such
# methods by a fixed factor on the usual thresholds instead; this series shows
# whether it falls behind at the same point.
#
# Uses AotCompile.jar of run-method-profiling-measurements.sh.
#
# Usage: scripts/run-method-profiling-long-run-java25.sh <path-to-jdk-25> <machine-id>
#
# Runs about 5 minutes.

set -euo pipefail

jdk25=$1
machine_id=$2
out="results/method-profiling/$machine_id"
work="target/method-profiling/25"
java25="$jdk25/bin/java"

cd "$(dirname "$0")/.."

echo "Java 25 long run, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

TIMEFORMAT=%R
seconds=$( { time "$java25" -XX:AOTCacheOutput="$work/compile-t100.aot" -cp "$work/AotCompile.jar" \
  AotCompile 100 > "$work/compile-t100.aot.log" 2>&1; } 2>&1 )
echo "Java 25, AotCompile, 100 training iterations: $seconds s," \
  "$(wc -c < "$work/compile-t100.aot" | tr -d ' ') bytes" >> "$out/cache-creation.txt"

compile25="-cp $work/AotCompile.jar AotCompile"
python3 -I scripts/measure.py "$out/long-run-java25.csv" 10 \
  --blocks 1-20,21-40,41-60,61-80,81-100,101-120,121-140,141-160,161-180,181-200 \
  "none=$java25 $compile25 200" \
  "training100=$java25 -XX:AOTCache=$work/compile-t100.aot $compile25 200" \
  | sed -e "s|$java25|java25|g" > "$out/long-run-java25-summary.txt"

echo "Java 25 long run, load at end: $(uptime)" >> "$out/environment.txt"
cat "$out/long-run-java25-summary.txt"
