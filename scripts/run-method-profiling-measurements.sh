#!/usr/bin/env bash
#
# Measures what the method profiles in the AOT cache (JEP 515) do to the warmup
# and the peak performance of AotCompile, on Java 28 and Java 25, and writes the
# results to results/method-profiling/<machine-id>/.
#
# Usage: scripts/run-method-profiling-measurements.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>
#
# Runs about 30 minutes. Close other applications first: the script measures
# warmup times, and every background load shows up in them. environment.txt
# records the load average at start and end.
#
# All Java 28 caches are created with -XX:-AOTCodeCaching, so they contain
# loaded and linked classes and method profiles, but no AOT code (JEP 544).
# This way they match what a Java 25 cache contains.

set -euo pipefail

jdk28=$1
jdk25=$2
machine_id=$3
out="results/method-profiling/$machine_id"
work="target/method-profiling"

cd "$(dirname "$0")/.."
rm -rf "$work"
mkdir -p "$work/25" "$work/28" "$out"

measure() { python3 -I scripts/measure.py "$@"; }

echo "== Building the programs"
for version in 25 28; do
  jdk_var="jdk$version"
  jdk=${!jdk_var}
  "$jdk/bin/javac" -d "$work/$version/AotCompile" src/main/java/AotCompile.java
  "$jdk/bin/jar" cf "$work/$version/AotCompile.jar" -C "$work/$version/AotCompile" .
  "$jdk/bin/javac" -d "$work/$version/HelloStreamWarmup" scripts/HelloStreamWarmup.java
  "$jdk/bin/jar" cf "$work/$version/HelloStreamWarmup.jar" -C "$work/$version/HelloStreamWarmup" .
done

{
  echo "Date: $(date -u +%Y-%m-%dT%H:%MZ)"
  echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || grep -m1 'model name' /proc/cpuinfo)"
  echo "Logical CPUs: $(getconf _NPROCESSORS_ONLN)"
  echo
  "$jdk28/bin/java" -version 2>&1
  echo
  "$jdk25/bin/java" -version 2>&1
  echo
  "$jdk28/bin/java" -XX:+PrintFlagsFinal -version 2>/dev/null | grep -E " (CICompilerCount|TypeProfileWidth|TypeProfileMajorReceiverPercent) "
  echo
  echo "Load at start: $(uptime)"
} > "$out/environment.txt"

java28="$jdk28/bin/java"
java25="$jdk25/bin/java"
no_aot_code=(-XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching)
no_replay="-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining"

create_cache() { # <java> <cache-file> <jar> <main-class> <arguments> [java options...]
  local java=$1 cache=$2 jar=$3 main=$4 arguments=$5
  shift 5
  "$java" "$@" -XX:AOTCacheOutput="$cache" -cp "$jar" "$main" $arguments > "$cache.log" 2>&1
}

echo "== Creating the caches"
{
  echo "Cache creation (training run + assembly), wall time in seconds and cache size in bytes"
  echo
  TIMEFORMAT=%R
  for rounds in 5 20 60 100; do
    cache="$work/28/compile-t$rounds.aot"
    seconds=$( { time create_cache "$java28" "$cache" "$work/28/AotCompile.jar" AotCompile $rounds \
      "${no_aot_code[@]}"; } 2>&1 )
    echo "Java 28, AotCompile, $rounds training iterations, without AOT code: $seconds s," \
      "$(wc -c < "$cache" | tr -d ' ') bytes"
  done
  cache="$work/25/compile-t20.aot"
  seconds=$( { time create_cache "$java25" "$cache" "$work/25/AotCompile.jar" AotCompile 20; } 2>&1 )
  echo "Java 25, AotCompile, 20 training iterations: $seconds s, $(wc -c < "$cache" | tr -d ' ') bytes"
  create_cache "$java28" "$work/28/hello.aot" "$work/28/HelloStreamWarmup.jar" HelloStreamWarmup "" \
    "${no_aot_code[@]}"
  create_cache "$java25" "$work/25/hello.aot" "$work/25/HelloStreamWarmup.jar" HelloStreamWarmup ""
  for version in 28 25; do
    echo "Java $version, HelloStreamWarmup: $(wc -c < "$work/$version/hello.aot" | tr -d ' ') bytes"
  done
} | tee "$out/cache-creation.txt"

compile28="-cp $work/28/AotCompile.jar AotCompile"
compile25="-cp $work/25/AotCompile.jar AotCompile"
blocks=1-1,2-5,6-10,11-20,21-30,31-40,41-60,61-80,81-100

echo "== Java 28, length of the training run, 15 runs of 100 iterations"
measure "$out/training-length.csv" 15 --blocks "$blocks" \
  "none=$java28 $compile28 100" \
  "noreplay=$java28 $no_replay -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  "training5=$java28 -XX:AOTCache=$work/28/compile-t5.aot $compile28 100" \
  "training20=$java28 -XX:AOTCache=$work/28/compile-t20.aot $compile28 100" \
  "training60=$java28 -XX:AOTCache=$work/28/compile-t60.aot $compile28 100" \
  "training100=$java28 -XX:AOTCache=$work/28/compile-t100.aot $compile28 100" \
  | tee "$out/training-length-summary.txt"

echo "== Java 28, after the training count is passed, 10 runs of 200 iterations"
# Lukewarm methods stay at level 2 until they have run as often as in the whole
# training run; 200 iterations show whether the variants meet afterwards.
measure "$out/long-run.csv" 10 \
  --blocks 1-20,21-40,41-60,61-80,81-100,101-120,121-140,141-160,161-180,181-200 \
  "none=$java28 $compile28 200" \
  "noreplay=$java28 $no_replay -XX:AOTCache=$work/28/compile-t20.aot $compile28 200" \
  "training20=$java28 -XX:AOTCache=$work/28/compile-t20.aot $compile28 200" \
  "training60=$java28 -XX:AOTCache=$work/28/compile-t60.aot $compile28 200" \
  "training100=$java28 -XX:AOTCache=$work/28/compile-t100.aot $compile28 200" \
  | tee "$out/long-run-summary.txt"

echo "== Java 25, 15 runs of 100 iterations"
measure "$out/java25.csv" 15 --blocks "$blocks" \
  "none=$java25 $compile25 100" \
  "noreplay=$java25 $no_replay -XX:AOTCache=$work/25/compile-t20.aot $compile25 100" \
  "training20=$java25 -XX:AOTCache=$work/25/compile-t20.aot $compile25 100" \
  | tee "$out/java25-summary.txt"

echo "== HelloStreamWarmup from JEP 515, 30 starts per variant"
for version in 28 25; do
  java_var="java$version"
  java=${!java_var}
  hello="-cp $work/$version/HelloStreamWarmup.jar HelloStreamWarmup"
  measure "$out/hello-java$version.csv" 30 \
    "none=$java $hello" \
    "noreplay=$java $no_replay -XX:AOTCache=$work/$version/hello.aot $hello" \
    "profiles=$java -XX:AOTCache=$work/$version/hello.aot $hello" \
    | tee "$out/hello-java$version-summary.txt"
done

echo "== PrintCompilation and CITime, one run of 100 iterations per variant"
print_compilation() { # <java> <name> [java options...] -- the program follows in $program
  local java=$1 name=$2
  shift 2
  "$java" -XX:+PrintCompilation -XX:+CITime "$@" $program 100 > "$work/compilation-$name.log" 2>&1
  python3 -I scripts/compilations-per-iteration.py "$work/compilation-$name.log" \
    > "$out/compilations-$name.txt"
  echo >> "$out/compilations-$name.txt"
  sed -n '/Accumulated compiler times/,$p' "$work/compilation-$name.log" >> "$out/compilations-$name.txt"
  gzip -9 -c "$work/compilation-$name.log" > "$out/compilation-$name.log.gz"
}
program=$compile28
print_compilation "$java28" java28-none
print_compilation "$java28" java28-noreplay $no_replay -XX:AOTCache="$work/28/compile-t20.aot"
for rounds in 5 20 60 100; do
  print_compilation "$java28" java28-training$rounds -XX:AOTCache="$work/28/compile-t$rounds.aot"
done
program=$compile25
print_compilation "$java25" java25-none
print_compilation "$java25" java25-noreplay $no_replay -XX:AOTCache="$work/25/compile-t20.aot"
print_compilation "$java25" java25-training20 -XX:AOTCache="$work/25/compile-t20.aot"

echo "== LogCompilation, one run of 100 iterations per variant"
# The logs are about 100 MB each, so only their evaluation goes into the results.
for variant in none noreplay training20; do
  options=()
  [[ $variant == noreplay ]] && options=($no_replay)
  [[ $variant != none ]] && options+=(-XX:AOTCache="$work/28/compile-t20.aot")
  "$java28" -XX:+UnlockDiagnosticVMOptions ${options[@]+"${options[@]}"} -XX:+LogCompilation \
    -XX:LogFile="$work/logcompilation-$variant.xml" $compile28 100 > /dev/null
  python3 -I scripts/analyze-logcompilation.py "$work/logcompilation-$variant.xml" \
    > "$out/logcompilation-java28-$variant.txt"
done

echo "== JFR execution samples from second 4 to the end, 5 runs of 100 iterations per variant"
for variant in noreplay training20; do
  options=()
  [[ $variant == noreplay ]] && options=($no_replay)
  for run in 1 2 3 4 5; do
    "$java28" ${options[@]+"${options[@]}"} -XX:AOTCache="$work/28/compile-t20.aot" \
      "-XX:StartFlightRecording:delay=4s,filename=$work/$variant-$run.jfr,jdk.ExecutionSample#period=1ms" \
      $compile28 100 > /dev/null 2>&1
  done
done
for variant in noreplay training20; do
  for run in 1 2 3 4 5; do
    "$jdk28/bin/jfr" print --json --stack-depth 64 \
      --events jdk.ExecutionSample,jdk.ThreadAllocationStatistics \
      "$work/$variant-$run.jfr" > "$work/$variant-$run.json"
  done
done
files() { local v=$1; echo "$work/$v-1.json,$work/$v-2.json,$work/$v-3.json,$work/$v-4.json,$work/$v-5.json"; }
python3 -I scripts/analyze-jfr-samples.py "noreplay=$(files noreplay)" "training20=$(files training20)" \
  > "$out/jfr-samples-java28.txt"

# The summaries quote the command lines; "java28" and "java25" read better than the JDK paths.
for summary in "$out"/*-summary.txt; do
  sed -i.bak -e "s|$jdk28/bin/java|java28|g" -e "s|$jdk25/bin/java|java25|g" "$summary"
  rm "$summary.bak"
done

echo "Load at end: $(uptime)" >> "$out/environment.txt"
echo "Done: $out"
