#!/usr/bin/env bash
#
# Reproduces all measurements of the article "Ahead-of-Time Code Compilation"
# (JEP 544) and writes them to results/code-compilation/<machine-id>/.
#
# Usage: scripts/run-code-compilation-measurements.sh <path-to-jdk-28> <machine-id>
#
# Runs about 15 minutes. Close other applications first: the script measures
# start and warmup times, and every background load shows up in them.
# environment.txt records the load average at start and end.

set -euo pipefail

jdk=$1
machine_id=$2
# The summaries quote the command lines; with the JDK on the PATH they read "java ...".
export PATH="$jdk/bin:$PATH"
java=java
out="results/code-compilation/$machine_id"
work="target/code-compilation"

cd "$(dirname "$0")/.."
rm -rf "$work"
mkdir -p "$work" "$out"

measure() { python3 -I scripts/measure.py "$@"; }

echo "== Building the programs"
for program in AotCompile AotTest; do
  "$jdk/bin/javac" -d "$work/$program" "src/main/java/$program.java"
  "$jdk/bin/jar" cf "$work/$program.jar" -C "$work/$program" .
done

{
  echo "Date: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || grep -m1 'model name' /proc/cpuinfo)"
  echo "Logical CPUs: $(getconf _NPROCESSORS_ONLN)"
  echo
  "$java" -version 2>&1
  echo
  echo "Load at start: $(uptime)"
} > "$out/environment.txt"

# A cache with AOT code (the default since JDK 28) and one without it; both
# from the same training run, so they differ only in the AOT code.
create_cache() { # <cache-file> <program> <iterations> [java options...]
  local cache=$1 program=$2 iterations=$3
  shift 3
  "$java" "$@" -XX:AOTCacheOutput="$work/$cache" -cp "$work/$program.jar" "$program" \
    $iterations > "$work/$cache.log" 2>&1
}
no_aot_code=(-XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching)

echo "== Creating the caches"
{
  echo "Cache creation (training run + assembly), wall time in seconds and cache size in bytes"
  echo
  TIMEFORMAT=%R
  for repetition in 1 2 3; do
    for variant in code nocode; do
      options=()
      [[ $variant == nocode ]] && options=("${no_aot_code[@]}")
      seconds=$( { time create_cache "compile-$variant.aot" AotCompile 20 ${options[@]+"${options[@]}"}; } 2>&1 )
      echo "AotCompile, 20 training iterations, $variant: $seconds s," \
        "$(wc -c < "$work/compile-$variant.aot" | tr -d ' ') bytes"
    done
  done
  for repetition in 1 2 3; do
    seconds=$( { time "$java" -cp "$work/AotCompile.jar" AotCompile 20 > /dev/null; } 2>&1 )
    echo "AotCompile, 20 iterations without creating a cache: $seconds s"
  done
} | tee "$out/cache-creation.txt"

create_cache compile-t5.aot AotCompile 5
create_cache compile-t60.aot AotCompile 60
JDK_AOT_VM_OPTIONS="-XX:+UnlockDiagnosticVMOptions -XX:-UseAOTCodeCounters" \
  create_cache compile-nocounters.aot AotCompile 20
create_cache aottest-code.aot AotTest ""
create_cache aottest-nocode.aot AotTest "" "${no_aot_code[@]}"

{
  echo
  echo "Further caches, size in bytes:"
  for cache in compile-t5 compile-t60 compile-nocounters aottest-code aottest-nocode; do
    echo "$cache.aot: $(wc -c < "$work/$cache.aot" | tr -d ' ') bytes"
  done
} | tee -a "$out/cache-creation.txt"

aottest="-cp $work/AotTest.jar AotTest"
compile="-cp $work/AotCompile.jar AotCompile"

echo "== AotTest, 50 starts per variant"
measure "$out/aottest.csv" 50 \
  "none=$java $aottest" \
  "nocode=$java -XX:AOTCache=$work/aottest-nocode.aot $aottest" \
  "code=$java -XX:AOTCache=$work/aottest-code.aot $aottest" \
  | tee "$out/aottest-summary.txt"

echo "== AotCompile, 30 runs of 20 iterations per variant"
measure "$out/compile-20.csv" 30 --blocks 1-1,2-5,6-10,11-20,1-20 \
  "none=$java $compile 20" \
  "nocode=$java -XX:AOTCache=$work/compile-nocode.aot $compile 20" \
  "code=$java -XX:AOTCache=$work/compile-code.aot $compile 20" \
  | tee "$out/compile-20-summary.txt"

echo "== AotCompile, 10 runs of 100 iterations per variant"
measure "$out/compile-100.csv" 10 --blocks 1-1,2-5,6-10,11-20,21-40,41-60,61-80,81-100 \
  "none=$java $compile 100" \
  "nocode=$java -XX:AOTCache=$work/compile-nocode.aot $compile 100" \
  "code=$java -XX:AOTCache=$work/compile-code.aot $compile 100" \
  | tee "$out/compile-100-summary.txt"

echo "== AotCompile, training length and AOT code counters, 8 runs of 60 iterations"
measure "$out/compile-training.csv" 8 --blocks 1-1,2-5,6-10,11-20,21-30,31-40,41-50,51-60 \
  "nocode=$java -XX:AOTCache=$work/compile-nocode.aot $compile 60" \
  "training5=$java -XX:AOTCache=$work/compile-t5.aot $compile 60" \
  "training20=$java -XX:AOTCache=$work/compile-code.aot $compile 60" \
  "training60=$java -XX:AOTCache=$work/compile-t60.aot $compile 60" \
  "nocounters=$java -XX:AOTCache=$work/compile-nocounters.aot $compile 60" \
  | tee "$out/compile-training-summary.txt"

echo "== PrintCompilation logs, 40 iterations"
for variant in none nocode code; do
  cache=()
  [[ $variant != none ]] && cache=(-XX:AOTCache="$work/compile-$variant.aot")
  "$java" -XX:+PrintCompilation ${cache[@]+"${cache[@]}"} $compile 40 > "$work/compilation-$variant.log" 2>&1
  python3 -I scripts/analyze-compilation.py "$work/compilation-$variant.log" \
    > "$out/compilation-$variant.txt"
  gzip -9 -c "$work/compilation-$variant.log" > "$out/compilation-$variant.log.gz"
done

echo "== Cache trained with G1, started with other collectors"
{
  for gc in SerialGC ParallelGC ZGC; do
    for mode in auto required; do
      echo "### -XX:+Use$gc -XX:AOTMode=$mode -Xlog:aot"
      "$java" -XX:+Use$gc -XX:AOTMode=$mode -Xlog:aot -XX:AOTCache="$work/compile-code.aot" \
        $compile 1 2>&1 | grep -E "warning|error|disabled|Unable|Iteration|Error" || true
      echo "### the same without -Xlog:aot"
      "$java" -XX:+Use$gc -XX:AOTMode=$mode -XX:AOTCache="$work/compile-code.aot" \
        $compile 1 2>&1 || true
      echo
    done
  done
} > "$out/gc-mismatch.txt"

echo "Load at end: $(uptime)" >> "$out/environment.txt"
echo "Done: $out"
