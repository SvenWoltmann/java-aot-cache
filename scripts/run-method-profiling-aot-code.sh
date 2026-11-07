#!/usr/bin/env bash
#
# Ninth follow-up to run-method-profiling-measurements.sh: AotLambda with a
# cache that contains AOT code (JEP 544). All other Java 28 caches of the
# method-profiling series are created with -XX:-AOTCodeCaching. The JVM
# compiles the AOT code in the assembly phase from the training data, whose
# lambda rows are already purged, so the question is whether the AOT code of
# Steps.run() inlines the lambda.
#
# Uses AotLambda.jar and the cache without AOT code of
# run-method-profiling-lambda.sh.
#
# Usage: scripts/run-method-profiling-aot-code.sh <path-to-jdk-28> <machine-id>
#
# Runs about 4 minutes.

set -euo pipefail

jdk28=$1
machine_id=$2
out="results/method-profiling/$machine_id"
lambda="target/method-profiling/lambda/28"
work="target/method-profiling/aot-code"
java28="$jdk28/bin/java"
no_replay="-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining"

cd "$(dirname "$0")/.."
rm -rf "$work"
mkdir -p "$work"

echo "AotLambda with AOT code, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

"$java28" "-Xlog:aot+training=debug:file=$work/training-%p.log" \
  -XX:AOTCacheOutput="$work/AotLambda-code.aot" -cp "$lambda/AotLambda.jar" AotLambda 5 \
  > "$work/cache.log" 2>&1

program="-cp $lambda/AotLambda.jar AotLambda 30"
python3 -I scripts/measure.py "$out/lambda-aot-code.csv" 10 --blocks 1-1,2-5,6-30 \
  "none=$java28 $program" \
  "noreplay=$java28 $no_replay -XX:AOTCache=$work/AotLambda-code.aot $program" \
  "profiles=$java28 -XX:AOTCache=$lambda/AotLambda.aot $program" \
  "profiles-code=$java28 -XX:AOTCache=$work/AotLambda-code.aot $program" \
  | sed -e "s|$java28|java28|g" > "$out/lambda-aot-code-summary.txt"

{
  echo "Cache with AOT code, created by $("$java28" -version 2>&1 | sed -n 2p)"
  grep -h "AOTCache creation" "$work/cache.log" || true
  echo
  echo "Rows removed from the profiles while writing the training data (-Xlog:aot+training=debug):"
  cat "$work"/training-*.log | grep -E "Purged|Cleanup MTD" | grep AotLambda \
    | sed -E 's/^\[[^]]*\]\[[^]]*\]\[[^]]*\] /  /'
  echo
  echo "Compilations of Steps and of the lambda, and C2's decisions on op.applyAsInt(),"
  echo "one run of 10 iterations with the cache with AOT code"
  echo "(-XX:+PrintCompilation -XX:+PrintInlining; AOT code is marked in the PrintCompilation lines)"
  "$java28" -XX:+UnlockDiagnosticVMOptions -XX:AOTCache="$work/AotLambda-code.aot" \
    -XX:+PrintCompilation -XX:+PrintInlining -cp "$lambda/AotLambda.jar" AotLambda 10 2>&1 \
    | grep -E "AotLambda\\\$Steps::|AotLambda\\\$\\\$Lambda.*::applyAsInt|applyAsInt.*(inline \(hot\)|failed to inline)" \
    | sed -E -e 's/^ +//' -e 's/ +/ /g'
} > "$out/lambda-aot-code.txt"

echo "AotLambda with AOT code, load at end: $(uptime)" >> "$out/environment.txt"
cat "$out/lambda-aot-code-summary.txt" "$out/lambda-aot-code.txt"
