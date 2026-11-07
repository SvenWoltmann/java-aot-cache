#!/usr/bin/env bash
#
# Sixth follow-up to run-method-profiling-measurements.sh, Java 28-ea+23 or
# newer: iterative training (JDK-8353598). A training run may load an existing
# AOT cache (-XX:AOTCache together with -XX:AOTCacheOutput); the new training
# data then contains that of the old cache and that of the new run. The
# question: does a second training run keep the profile rows of the lambda
# classes, which the first one loses (run-method-profiling-lambda.sh)?
#
# Uses the programs and caches of the main script and of the lambda script in
# target/method-profiling/, so run those first.
#
# Usage: scripts/run-method-profiling-iterative.sh <path-to-jdk-28> <machine-id>
#
# Runs about 15 minutes.

set -euo pipefail

jdk28=$1
machine_id=$2
out="results/method-profiling/$machine_id"
work="target/method-profiling"
iter="$work/iterative"
java28="$jdk28/bin/java"
no_code=(-XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching)
no_replay="-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining"

cd "$(dirname "$0")/.."
rm -rf "$iter"
mkdir -p "$iter"

echo "Iterative training, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

train() { # <log-name> <cache-output> <jar> <main> <iterations> [more java options...]
  local name=$1 output=$2 jar=$3 main=$4 iterations=$5
  shift 5
  "$java28" "${no_code[@]}" "$@" "-Xlog:aot+training=debug:file=$iter/$name-%p.log" \
    -XX:AOTCacheOutput="$output" -cp "$jar" "$main" $iterations > "$iter/$name.out" 2>&1
}

# AotLambda: the cache of the lambda script, trained again for 5 iterations.
lambda_jar="$work/lambda/28/AotLambda.jar"
train lambda-first "$iter/AotLambda-first.aot" "$lambda_jar" AotLambda 5
train lambda-second "$iter/AotLambda-second.aot" "$lambda_jar" AotLambda 5 \
  -XX:AOTCache="$iter/AotLambda-first.aot"

# AotCompile: 20 iterations, then 20 more on top; for comparison 40 in one run.
compile_jar="$work/28/AotCompile.jar"
train compile-first "$iter/compile-t20.aot" "$compile_jar" AotCompile 20
train compile-second "$iter/compile-t20-plus20.aot" "$compile_jar" AotCompile 20 \
  -XX:AOTCache="$iter/compile-t20.aot"
train compile-t40 "$iter/compile-t40.aot" "$compile_jar" AotCompile 40

{
  for name in lambda-first lambda-second compile-first compile-second compile-t40; do
    echo "### $name"
    grep -h "re-training\|AOTCache creation" "$iter/$name.out" || true
    python3 -I scripts/summarize-purged.py "$iter/$name"-*.log | head -4
    echo
  done
} > "$out/iterative-purged.txt"

echo "== AotLambda, 10 runs of 30 iterations"
lambda="-cp $lambda_jar AotLambda 30"
python3 -I scripts/measure.py "$out/iterative-lambda.csv" 10 --blocks 1-1,2-5,6-30 \
  "none=$java28 $lambda" \
  "noreplay=$java28 $no_replay -XX:AOTCache=$iter/AotLambda-first.aot $lambda" \
  "first=$java28 -XX:AOTCache=$iter/AotLambda-first.aot $lambda" \
  "second=$java28 -XX:AOTCache=$iter/AotLambda-second.aot $lambda" \
  | sed -e "s|$java28|java28|g" > "$out/iterative-lambda-summary.txt"

echo "== AotCompile, 15 runs of 100 iterations"
compile="-cp $compile_jar AotCompile 100"
python3 -I scripts/measure.py "$out/iterative-compile.csv" 15 \
  --blocks 1-1,2-5,6-10,11-20,21-30,31-40,41-60,61-80,81-100 \
  "none=$java28 $compile" \
  "noreplay=$java28 $no_replay -XX:AOTCache=$iter/compile-t20.aot $compile" \
  "training20=$java28 -XX:AOTCache=$iter/compile-t20.aot $compile" \
  "training20plus20=$java28 -XX:AOTCache=$iter/compile-t20-plus20.aot $compile" \
  "training40=$java28 -XX:AOTCache=$iter/compile-t40.aot $compile" \
  | sed -e "s|$java28|java28|g" > "$out/iterative-compile-summary.txt"

echo "== LogCompilation with the iteratively trained cache, compared with no profiles"
"$java28" -XX:+UnlockDiagnosticVMOptions -XX:AOTCache="$iter/compile-t20-plus20.aot" \
  -XX:+LogCompilation -XX:LogFile="$iter/logcompilation-plus20.xml" $compile > /dev/null
"$java28" $no_replay -XX:AOTCache="$iter/compile-t20.aot" \
  -XX:+LogCompilation -XX:LogFile="$iter/logcompilation-noreplay.xml" $compile > /dev/null
python3 -I scripts/compare-inlining.py "$iter/logcompilation-noreplay.xml" \
  "$iter/logcompilation-plus20.xml" > "$out/iterative-inlining.txt"

echo "Iterative training, load at end: $(uptime)" >> "$out/environment.txt"
echo "Done: $out"
