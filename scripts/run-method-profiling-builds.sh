#!/usr/bin/env bash
#
# Seventh follow-up to run-method-profiling-measurements.sh: two Java 28
# builds side by side. On 28-ea+20, the cache from 100 training iterations
# was behind the run without a cache already in iterations 81 to 100; on
# 28-ea+23 only after iteration 120. The two series ran on different
# evenings, so the question is whether the builds differ or the series.
# This script creates the caches for both builds and measures them
# alternately in one series.
#
# Uses AotCompile.jar of the main script (target/method-profiling/28/), so
# run that first.
#
# Usage: scripts/run-method-profiling-builds.sh <path-to-jdk-a> <name-a> <path-to-jdk-b> <name-b> <machine-id>
# Example: scripts/run-method-profiling-builds.sh ~/jdk-28-ea20 ea20 ~/jdk-28-ea23 ea23 apple-m5-pro
#
# Runs about 15 minutes.

set -euo pipefail

jdk_a=$1
name_a=$2
jdk_b=$3
name_b=$4
machine_id=$5
out="results/method-profiling/$machine_id"
work="target/method-profiling/builds"
jar="target/method-profiling/28/AotCompile.jar"

cd "$(dirname "$0")/.."
rm -rf "$work"
mkdir -p "$work"

echo "Builds compared, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

{
  for jdk in "$jdk_a" "$jdk_b"; do
    "$jdk/bin/java" -version 2>&1 | sed -n 2p
  done
} > "$out/builds-versions.txt"

for pair in "$name_a=$jdk_a" "$name_b=$jdk_b"; do
  name=${pair%%=*}
  jdk=${pair#*=}
  for iterations in 20 100; do
    "$jdk/bin/java" -XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching \
      -XX:AOTCacheOutput="$work/$name-t$iterations.aot" -cp "$jar" AotCompile $iterations \
      > "$work/$name-t$iterations.log" 2>&1
  done
done

java_a="$jdk_a/bin/java"
java_b="$jdk_b/bin/java"
program="-cp $jar AotCompile 200"
python3 -I scripts/measure.py "$out/builds.csv" 10 \
  --blocks 1-20,21-40,41-60,61-80,81-100,101-120,121-140,141-160,161-180,181-200 \
  "$name_a-none=$java_a $program" \
  "$name_a-training20=$java_a -XX:AOTCache=$work/$name_a-t20.aot $program" \
  "$name_a-training100=$java_a -XX:AOTCache=$work/$name_a-t100.aot $program" \
  "$name_b-none=$java_b $program" \
  "$name_b-training20=$java_b -XX:AOTCache=$work/$name_b-t20.aot $program" \
  "$name_b-training100=$java_b -XX:AOTCache=$work/$name_b-t100.aot $program" \
  | sed -e "s|$java_a|java-$name_a|g" -e "s|$java_b|java-$name_b|g" > "$out/builds-summary.txt"

echo "Builds compared, load at end: $(uptime)" >> "$out/environment.txt"
cat "$out/builds-summary.txt"
