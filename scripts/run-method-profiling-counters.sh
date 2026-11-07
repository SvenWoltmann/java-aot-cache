#!/usr/bin/env bash
#
# Fourth follow-up to run-method-profiling-measurements.sh, macOS with Xcode
# only: records the CPU performance counters (Instruments template "CPU
# Counters", mode "CPU Bottlenecks") for runs without a cache, with the cache
# but without profiles, and with profiles, and compares cycles, instructions
# and the bottleneck shares of the main thread in the late iterations. Needs
# no root rights. Uses the programs and caches of the main script in
# target/method-profiling/.
#
# Usage: scripts/run-method-profiling-counters.sh <path-to-jdk-28> <machine-id>
#
# Runs about 10 minutes, most of it exporting the recordings (about 450 MB
# of XML per run, deleted after the evaluation).

set -euo pipefail

jdk28=$1
machine_id=$2
out="results/method-profiling/$machine_id"
work="target/method-profiling"
traces="$work/counters"

cd "$(dirname "$0")/.."
rm -rf "$traces"
mkdir -p "$traces"
java28="$jdk28/bin/java"
compile28="-cp $work/28/AotCompile.jar AotCompile"

echo "CPU counters, $(date -u +%Y-%m-%dT%H:%MZ), load at start: $(uptime)" >> "$out/environment.txt"

for run in 1 2 3 4; do
  for variant in none noreplay training20; do
    case $variant in
      none) vm=() ;;
      noreplay) vm=(-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining -XX:AOTCache="$work/28/compile-t20.aot") ;;
      training20) vm=(-XX:AOTCache="$work/28/compile-t20.aot") ;;
    esac
    xcrun xctrace record --quiet --template 'CPU Counters' --no-prompt \
      --output "$traces/$variant-$run.trace" --target-stdout "$traces/$variant-$run.out" \
      --launch -- "$java28" ${vm[@]+"${vm[@]}"} $compile28 100 > /dev/null 2>&1
  done
done
echo "CPU counters, recordings done, load: $(uptime)" >> "$out/environment.txt"

table() { # <trace> <schema>
  xcrun xctrace export --input "$1" --xpath "/trace-toc/run[@number=\"1\"]/data/table[@schema=\"$2\"]"
}
for variant in none noreplay training20; do
  for run in 1 2 3 4; do
    table "$traces/$variant-$run.trace" kdebug-counters-with-kdebug-sample > "$traces/$variant-$run.pmc.xml"
    table "$traces/$variant-$run.trace" CounterMetricByThread > "$traces/$variant-$run.metrics.xml"
  done
done

arguments() { # <suffix> -> label=xml:out,... for the three variants
  local suffix=$1 variant run list
  for variant in none noreplay training20; do
    list=""
    for run in 1 2 3 4; do
      list+="${list:+,}$traces/$variant-$run.$suffix.xml:$traces/$variant-$run.out"
    done
    echo "$variant=$list"
  done
}
python3 -I scripts/analyze-pmc-samples.py 2.0 $(arguments pmc) > "$out/cpu-counters.txt"
python3 -I scripts/analyze-cpu-bottlenecks.py 2.0 $(arguments metrics) > "$out/cpu-bottlenecks.txt"
rm -f "$traces"/*.xml
cat "$out/cpu-counters.txt" "$out/cpu-bottlenecks.txt"
