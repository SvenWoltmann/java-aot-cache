#!/usr/bin/env bash
#
# Second follow-up to run-method-profiling-measurements.sh: what eager
# compilation does. When the AOT code cache is in use, Java 28 sets the
# diagnostic option AOTCompileEagerly ergonomically (aotCodeCache.cpp) -- also
# for a cache without AOT code, because the cache still holds adapters and
# stubs. The JVM then compiles the methods from the training run as soon as
# their classes are initialized, before they are called. In Java 25 the option
# is experimental and off. This script switches it off in Java 28 and on in
# Java 25. Uses the programs and caches of the main script in
# target/method-profiling/, so run that one first.
#
# Usage: scripts/run-method-profiling-eager.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>
#
# Runs about 11 minutes.

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
no_eager="-XX:+UnlockDiagnosticVMOptions -XX:-AOTCompileEagerly"
eager="-XX:+UnlockExperimentalVMOptions -XX:+AOTCompileEagerly"
compile28="-cp $work/28/AotCompile.jar AotCompile"
compile25="-cp $work/25/AotCompile.jar AotCompile"
blocks=1-1,2-5,6-10,11-20,21-30,31-40,41-60,61-80,81-100

echo "Eager compilation, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

{
  for version in 28 25; do
    java_var="java$version"
    echo "Java $version: $("${!java_var}" -XX:AOTCache="$work/$version/compile-t20.aot" \
      -XX:+UnlockDiagnosticVMOptions -XX:+UnlockExperimentalVMOptions -XX:+PrintFlagsFinal \
      $( [[ $version == 28 ]] && echo "$compile28" || echo "$compile25" ) 1 2>/dev/null \
      | grep -E ' AOTCompileEagerly ' | tr -s ' ')"
  done
} > "$out/eager-flag.txt"

echo "== Java 28, eager compilation off, 15 runs of 100 iterations"
python3 -I scripts/measure.py "$out/eager-java28.csv" 15 --blocks "$blocks" \
  "noreplay=$java28 $no_replay -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  "training20=$java28 -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  "training20-noeager=$java28 $no_eager -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  | sed -e "s|$java28|java28|g" > "$out/eager-java28-summary.txt"

echo "== Java 25, eager compilation on, 15 runs of 100 iterations"
python3 -I scripts/measure.py "$out/eager-java25.csv" 15 --blocks "$blocks" \
  "noreplay=$java25 $no_replay -XX:AOTCache=$work/25/compile-t20.aot $compile25 100" \
  "training20=$java25 -XX:AOTCache=$work/25/compile-t20.aot $compile25 100" \
  "training20-eager=$java25 $eager -XX:AOTCache=$work/25/compile-t20.aot $compile25 100" \
  | sed -e "s|$java25|java25|g" > "$out/eager-java25-summary.txt"

echo "== LogCompilation of the two switched variants"
"$java28" $no_eager -XX:AOTCache="$work/28/compile-t20.aot" -XX:+LogCompilation \
  -XX:LogFile="$work/logcompilation-java28-noeager.xml" $compile28 100 > /dev/null
python3 -I scripts/analyze-logcompilation.py "$work/logcompilation-java28-noeager.xml" \
  > "$out/logcompilation-java28-training20-noeager.txt"
"$java25" $eager -XX:+UnlockDiagnosticVMOptions -XX:AOTCache="$work/25/compile-t20.aot" -XX:+LogCompilation \
  -XX:LogFile="$work/logcompilation-java25-eager.xml" $compile25 100 > /dev/null
python3 -I scripts/analyze-logcompilation.py "$work/logcompilation-java25-eager.xml" \
  > "$out/logcompilation-java25-training20-eager.txt"

echo "Eager compilation, load at end: $(uptime)" >> "$out/environment.txt"
echo "Done: $out"
