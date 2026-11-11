#!/usr/bin/env bash
#
# Checks which role the pause in AotLambda plays: Steps.init() and the
# half-second Thread.sleep() before the first call of Steps.run(). Runs
# AotLambda unchanged and a copy without these two lines (AotLambdaNoPause),
# on Java 28 and Java 25, and writes results/method-profiling/<machine-id>/lambda-pause.txt.
#
# Usage: scripts/run-method-profiling-pause.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>
#
# Runs about 2 minutes. For each version and program:
#   - a cache from 5 training iterations (Java 28 with -XX:-AOTCodeCaching)
#   - 3 runs of 10 iterations each without a cache, without profiles and with
#     profiles, without any logging; the mean of iterations 6 to 10 per run
#   - one run of 10 iterations each with and without profiles with
#     -XX:+PrintCompilation -XX:+PrintInlining: the compilations of Steps::run and
#     Steps::step (timestamp in ms, compile id, flags, level) and C2's decisions
#     on the lambda call. Logging slows the program down, so these runs show the
#     order of events, not representative timings.

set -euo pipefail

jdk28=$1
jdk25=$2
machine_id=$3
out="results/method-profiling/$machine_id"
work="target/method-profiling/pause"
no_replay="-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining"

cd "$(dirname "$0")/.."
rm -rf "$work"
mkdir -p "$work" "$out"
result="$out/lambda-pause.txt"

echo "AotLambda pause, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

cp src/main/java/AotLambda.java "$work/AotLambda.java"
grep -v -E 'Steps\.init\(\);|Thread\.sleep\(500\)' src/main/java/AotLambda.java > "$work/AotLambdaNoPause.java"

{
  echo "AotLambda with and without the pause before the first call of Steps.run()"
  echo "(AotLambdaNoPause is AotLambda without these two lines):"
  echo
  diff "$work/AotLambda.java" "$work/AotLambdaNoPause.java" || true
} > "$result"

for version in 28 25; do
  jdk_var="jdk$version"
  jdk=${!jdk_var}
  echo >> "$result"
  echo "== Java $version: $("$jdk/bin/java" -version 2>&1 | head -1)" >> "$result"
  for program in AotLambda AotLambdaNoPause; do
    dir="$work/$version/$program"
    mkdir -p "$dir/classes"
    "$jdk/bin/javac" -d "$dir/classes" "$work/$program.java"
    "$jdk/bin/jar" cf "$dir/$program.jar" -C "$dir/classes" .
    options=()
    [[ $version == 28 ]] && options=(-XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching)
    "$jdk/bin/java" ${options[@]+"${options[@]}"} -XX:AOTCacheOutput="$dir/$program.aot" \
      -cp "$dir/$program.jar" "$program" 5 > "$dir/cache.log" 2>&1

    echo >> "$result"
    echo "-- $program, mean of iterations 6 to 10 in ms, 3 runs each" >> "$result"
    for variant in none noreplay profiles; do
      run=()
      [[ $variant != none ]] && run=(-XX:AOTCache="$dir/$program.aot")
      [[ $variant == noreplay ]] && run=($no_replay "${run[@]}")
      means=""
      for i in 1 2 3; do
        means="$means $("$jdk/bin/java" ${run[@]+"${run[@]}"} -cp "$dir/$program.jar" "$program" 10 \
          | awk '/^Iteration/ && $2 + 0 >= 6 { sum += $3; n++ } END { printf "%.1f", sum / n }')"
      done
      printf '   %-9s%s\n' "$variant" "$means" >> "$result"
    done

    for variant in noreplay profiles; do
      run=(-XX:+UnlockDiagnosticVMOptions -XX:AOTCache="$dir/$program.aot")
      [[ $variant == noreplay ]] && run+=(-XX:-AOTReplayTraining)
      log="$dir/$variant-compilation.log"
      "$jdk/bin/java" "${run[@]}" -XX:+PrintCompilation -XX:+PrintInlining \
        -cp "$dir/$program.jar" "$program" 10 > "$log" 2>&1
      {
        echo
        echo "-- $program, $variant, one run with -XX:+PrintCompilation -XX:+PrintInlining"
        echo "   compilations of Steps::run and Steps::step (timestamp in ms, compile id, flags, level):"
        grep -oE '^ *[0-9]+ +[0-9]+ +[%sbn! ]*[0-4] +[A-Za-z]+\$Steps::(run|step) .*' "$log" \
          | sed -E -e 's/ +/ /g' -e 's/^ ?/   /' || true
        echo "   C2's decisions on the lambda call (TypeProfile: calls of the lambda class at the call site):"
        grep -oE 'applyAsInt \([0-9]+ bytes\) +(inline \(hot\)|failed to inline: [a-z ]+).*' "$log" \
          | sed -E -e 's/ +/ /g' -e 's/callee changed to [^\\]*\\-> //' -e 's/^/   /' || true
      } >> "$result"
    done
  done
done

echo "AotLambda pause, load at end: $(uptime)" >> "$out/environment.txt"
cat "$result"
