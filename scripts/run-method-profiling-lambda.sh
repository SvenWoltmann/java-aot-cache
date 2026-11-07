#!/usr/bin/env bash
#
# Fifth follow-up to run-method-profiling-measurements.sh: the program
# AotLambda shows on a small scale why C2 inlines less with method profiles.
#
# When the JVM writes the training data into the cache, it removes every
# class from the profiles that it does not archive (is_excluded() in
# methodData.cpp) -- among them the lambda classes that the training run
# generated. ReceiverTypeData::clean_weak_klass_links() clears their rows in
# the type profiles, and clear_row() also sets the call counter of the call
# site to 0. In the production run, C2 then sees a call site that was hardly
# ever called and does not inline the lambda ("low call site frequency").
#
# AotLambda initializes the class Steps and waits half a second, so that the
# JVM compiles Steps from the training data before its first call; the
# profile of Steps.step() keeps the call counter of 0. Without the wait, the
# interpreter fills the profile again before the compilation.
#
# Usage: scripts/run-method-profiling-lambda.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>
#
# Runs about 4 minutes.

set -euo pipefail

jdk28=$1
jdk25=$2
machine_id=$3
out="results/method-profiling/$machine_id"
work="target/method-profiling/lambda"
no_replay="-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining"

cd "$(dirname "$0")/.."
rm -rf "$work"
mkdir -p "$work" "$out"

echo "AotLambda, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

for version in 28 25; do
  jdk_var="jdk$version"
  jdk=${!jdk_var}
  dir="$work/$version"
  "$jdk/bin/javac" -d "$dir/classes" src/main/java/AotLambda.java
  "$jdk/bin/jar" cf "$dir/AotLambda.jar" -C "$dir/classes" .
  options=()
  [[ $version == 28 ]] && options=(-XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching)
  "$jdk/bin/java" ${options[@]+"${options[@]}"} "-Xlog:aot+training=debug:file=$dir/training-%p.log" \
    -XX:AOTCacheOutput="$dir/AotLambda.aot" -cp "$dir/AotLambda.jar" AotLambda 5 > "$dir/cache.log" 2>&1
done

{
  echo "Rows that the JVM removed from the profiles while writing the training data"
  echo "(-Xlog:aot+training=debug, lines with \"AotLambda\"):"
  for version in 28 25; do
    echo
    echo "Java $version:"
    cat "$work/$version"/training-*.log | grep -E "Purged|Cleanup MTD" | grep AotLambda | sed -E 's/^\[[^]]*\]\[[^]]*\]\[[^]]*\] //'
  done
} > "$out/lambda-purged.txt"

for version in 28 25; do
  jdk_var="jdk$version"
  java="${!jdk_var}/bin/java"
  dir="$work/$version"
  program="-cp $dir/AotLambda.jar AotLambda 30"
  python3 -I scripts/measure.py "$out/lambda-java$version.csv" 10 --blocks 1-1,2-5,6-30 \
    "none=$java $program" \
    "noreplay=$java $no_replay -XX:AOTCache=$dir/AotLambda.aot $program" \
    "profiles=$java -XX:AOTCache=$dir/AotLambda.aot $program" \
    | sed -e "s|$java|java$version|g" > "$out/lambda-java$version-summary.txt"
done

{
  echo "C2's decisions on the call op.applyAsInt() in Steps.step() (inlined into Steps.run()),"
  echo "Java 28, one run of 10 iterations; only the C2 decisions (\"hot\" or \"failed\")"
  echo "(-XX:+PrintCompilation -XX:+PrintInlining)"
  for variant in noreplay profiles; do
    options=(-XX:AOTCache="$work/28/AotLambda.aot")
    [[ $variant == noreplay ]] && options=($no_replay "${options[@]}")
    echo
    echo "### $variant"
    "$jdk28/bin/java" -XX:+UnlockDiagnosticVMOptions "${options[@]}" -XX:+PrintCompilation \
      -XX:+PrintInlining -cp "$work/28/AotLambda.jar" AotLambda 10 2>&1 \
      | grep -E "applyAsInt.*(inline \(hot\)|failed to inline)" \
      | sed -E -e 's/^ +//' -e 's/ +/ /g' -e 's/TypeProfile \([0-9]+\/([0-9]+) counts\)/TypeProfile (\1 counts)/'
  done
} > "$out/lambda-inlining.txt"

# The same for AotCompile: the cache from 20 training iterations, as in the main script.
"$jdk28/bin/java" -XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching \
  "-Xlog:aot+training=debug:file=$work/aotcompile-training-%p.log" \
  -XX:AOTCacheOutput="$work/AotCompile.aot" -cp target/method-profiling/28/AotCompile.jar AotCompile 20 \
  > "$work/aotcompile-cache.log" 2>&1
python3 -I scripts/summarize-purged.py "$work"/aotcompile-training-*.log > "$out/aotcompile-purged.txt"

echo "AotLambda, load at end: $(uptime)" >> "$out/environment.txt"
cat "$out/lambda-purged.txt" "$out/lambda-inlining.txt"
