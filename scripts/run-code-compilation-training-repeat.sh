#!/usr/bin/env bash
#
# Repeats the training-length measurement of the article "Ahead-of-Time Code
# Compilation" with three independently created caches per training length
# (5, 20 and 60 iterations), to tell the effect of the training length from
# the variation between two caches of the same training length.
#
# Usage: scripts/run-code-compilation-training-repeat.sh <path-to-jdk-28> <machine-id>
#
# Runs about 10 minutes. Close other applications first.

set -euo pipefail

jdk=$1
machine_id=$2
export PATH="$jdk/bin:$PATH"
java=java
out="results/code-compilation/$machine_id"
work="target/code-compilation-repeat"

cd "$(dirname "$0")/.."
rm -rf "$work"
mkdir -p "$work" "$out"

"$jdk/bin/javac" -d "$work/AotCompile" src/main/java/AotCompile.java
"$jdk/bin/jar" cf "$work/AotCompile.jar" -C "$work/AotCompile" .

{
  echo "Date: $(date -u +%Y-%m-%dT%H:%MZ)"
  "$java" -version 2>&1 | sed -n 2p
  echo "Load at start: $(uptime)"
} > "$out/training-repeat-environment.txt"

echo "== Creating three caches per training length"
{
  echo "Cache size in bytes"
  for repetition in a b c; do
    for training in 5 20 60; do
      cache="$work/t$training$repetition.aot"
      "$java" -XX:AOTCacheOutput="$cache" -cp "$work/AotCompile.jar" AotCompile $training \
        > "$cache.log" 2>&1
      echo "t$training$repetition.aot: $(wc -c < "$cache" | tr -d ' ')"
    done
  done
} | tee "$out/training-repeat-caches.txt"

compile="-cp $work/AotCompile.jar AotCompile 60"
variants=()
for training in 5 20 60; do
  for repetition in a b c; do
    variants+=("t$training$repetition=$java -XX:AOTCache=$work/t$training$repetition.aot $compile")
  done
done

echo "== AotCompile, 8 runs of 60 iterations per cache"
python3 -I scripts/measure.py "$out/compile-training-repeat.csv" 8 \
  --blocks 1-1,2-5,6-10,11-20,21-30,31-40,41-50,51-60 "${variants[@]}" \
  | tee "$out/compile-training-repeat-summary.txt"

echo "Load at end: $(uptime)" >> "$out/training-repeat-environment.txt"
echo "Done: $out"
