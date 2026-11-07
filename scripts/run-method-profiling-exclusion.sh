#!/usr/bin/env bash
#
# Eighth follow-up to run-method-profiling-measurements.sh, Java 28-ea+23 or
# newer: why the JVM excludes the lambda class of AotLambda from the
# training data, also in an iterative training run.
#
# The training run writes the AOT configuration (a "preimage"). There,
# AOTArtifactFinder::find_artifacts() keeps a hidden class only if an
# archivable constant-pool entry or heap object refers to it. The preimage
# archives neither resolved invokedynamic entries nor AOT-linked classes
# (CDSConfig::is_dumping_aot_linked_classes() is true only for the final
# cache), so every lambda class is excluded as "Unreferenced hidden class",
# and TrainingData::cleanup_training_data(), called right after, removes it
# from the profiles. -Xlog:aot=debug shows both steps, for the first and for
# the second (iterative) training run.
#
# Uses AotLambda.jar of run-method-profiling-lambda.sh.
#
# Usage: scripts/run-method-profiling-exclusion.sh <path-to-jdk-28> <machine-id>
#
# Runs a few seconds.

set -euo pipefail

jdk28=$1
machine_id=$2
out="results/method-profiling/$machine_id"
work="target/method-profiling/exclusion"
jar="target/method-profiling/lambda/28/AotLambda.jar"
java28="$jdk28/bin/java"

cd "$(dirname "$0")/.."
rm -rf "$work"
mkdir -p "$work"

"$java28" -XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching \
  "-Xlog:aot=debug,aot+training=debug:file=$work/first-%p.log" \
  -XX:AOTCacheOutput="$work/first.aot" -cp "$jar" AotLambda 5 > /dev/null 2>&1
"$java28" -XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching -XX:AOTCache="$work/first.aot" \
  "-Xlog:aot=debug,aot+training=debug,class+load=info:file=$work/second-%p.log" \
  -XX:AOTCacheOutput="$work/second.aot" -cp "$jar" AotLambda 5 > /dev/null 2>&1
"$java28" -XX:AOTCache="$work/first.aot" -Xlog:class+load=info -cp "$jar" AotLambda 1 \
  > "$work/production.log" 2>&1

{
  echo "Lines on the lambda class of AotLambda, $("$java28" -version 2>&1 | sed -n 2p)"
  echo "(-Xlog:aot=debug,aot+training=debug, in the second run also class+load=info;"
  echo "one log per process: training run, then assembly)"
  for run in first second; do
    echo
    echo "### $run training run"
    for log in "$work/$run"-*.log; do
      echo "process $(basename "$log" .log | sed 's/.*-//'):"
      grep -F 'AotLambda$$Lambda' "$log" | sed -E 's/^\[[^]]*\]\[[^]]*\]\[[^]]*\] */  /' || echo "  (none)"
    done
  done
  echo
  echo "### where the lambda class comes from in a run with the first cache (-Xlog:class+load)"
  grep -F 'AotLambda$$Lambda' "$work/production.log" | sed -E 's/^\[[^]]*\]\[[^]]*\]\[[^]]*\] */  /'
} > "$out/lambda-exclusion.txt"

cat "$out/lambda-exclusion.txt"
