# Java AOT Cache

[![Build](https://github.com/SvenWoltmann/java-aot-cache/actions/workflows/build.yml/badge.svg)](https://github.com/SvenWoltmann/java-aot-cache/actions/workflows/build.yml)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=SvenWoltmann_java-aot-cache&metric=sqale_rating)](https://sonarcloud.io/dashboard?id=SvenWoltmann_java-aot-cache)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=SvenWoltmann_java-aot-cache&metric=reliability_rating)](https://sonarcloud.io/dashboard?id=SvenWoltmann_java-aot-cache)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=SvenWoltmann_java-aot-cache&metric=security_rating)](https://sonarcloud.io/dashboard?id=SvenWoltmann_java-aot-cache)

Example programs and measurements of the HappyCoders.eu articles on the AOT cache of Project Leyden:

* "Ahead-of-Time Class Loading & Linking" – JEP 483, 514, 515 and 516 ([English](https://www.happycoders.eu/java/ahead-of-time-class-loading-and-linking/), [German](https://www.happycoders.eu/de/java/ahead-of-time-class-loading-and-linking/))
* "Ahead-of-Time Code Compilation" – JEP 544, Java 28 (not yet published)
* "Ahead-of-Time Method Profiling" – JEP 515, Java 25 (in preparation)

## Programs

All three programs are compact source files with an instance `main()` method, so they need Java 25 or newer. They are in the unnamed package, since a compact source file cannot declare a package.

* `AotTest` – prints the current date and time; the example of the class-loading article. It starts within a few dozen milliseconds, so it shows what the AOT cache saves on a tiny program.
* `AotLambda` – calls a lambda for each element of an array, 100,000 times per round, and prints the duration of each round (argument: number of rounds, default 10). It shows on a small scale why C2 inlines less with the method profiles of JEP 515: when the JVM writes the training data into the cache, it removes the lambda classes of the training run from the type profiles and sets the counter of the call site to 0. C2 then considers the call site cold and does not inline the lambda. The program waits half a second after initializing the class with the hot loop, so that the JVM compiles it from the training data before it runs. On Java 28, the interpreter fills the profile again without the wait before C2 compiles the loop, and the effect does not show. On Java 25, it shows without the wait too: C2 compiles `Steps.step()` right after its first calls, when the interpreter has counted only a few thousand calls at the call site (`lambda-pause.txt`).
* `AotCompile` – compiles 50 generated source files with the Java compiler, in memory, and prints the duration of each round. Its only argument is the number of rounds (default 10). It loads, links and compiles enough code for the effect of AOT code to show in the first round and in the warmup that follows – the same idea as the `javac` benchmark in JEP 544.

## Running AotCompile with an AOT cache

Ahead-of-time code compilation needs Java 28 (early-access builds: [jdk.java.net/28](https://jdk.java.net/28/)). In `src/main/java`, compile the program and pack it into a JAR file – the JVM refuses to create an AOT cache when the class path contains a non-empty directory:

```
javac -d classes AotCompile.java
jar cf AotCompile.jar -C classes .
```

Create the AOT cache in a training run of 20 rounds:

```
java -XX:AOTCacheOutput=AotCompile.aot -cp AotCompile.jar AotCompile 20
```

Then compare a start without and with the cache:

```
java -cp AotCompile.jar AotCompile 20
java -XX:AOTCache=AotCompile.aot -cp AotCompile.jar AotCompile 20
```

To compare with a cache that contains loaded classes and profiles but no AOT code, create a second cache with the diagnostic option `-XX:-AOTCodeCaching`:

```
java -XX:+UnlockDiagnosticVMOptions -XX:-AOTCodeCaching \
     -XX:AOTCacheOutput=AotCompile-without-code.aot -cp AotCompile.jar AotCompile 20
```

`-XX:+PrintCompilation` shows which methods are loaded from the cache: AOT code carries the flag `A`, AOT code with class initialization barriers additionally `P`.

## Measurements

### AOT code (JEP 544)

`scripts/run-code-compilation-measurements.sh <path-to-jdk-28> <machine-id>` reproduces all measurements of the code-compilation article in about 30 minutes and writes them to `results/code-compilation/<machine-id>/`:

* `environment.txt` – date, CPU and JDK build
* `cache-creation.txt` – duration of training run plus cache creation, and the sizes of all caches
* `aottest.csv`, `aottest-summary.txt` – 50 starts of `AotTest` each without a cache, with a cache without AOT code, and with a cache with AOT code
* `compile-100.csv`, `compile-100-summary.txt` – 30 runs of `AotCompile` with 100 rounds each, same three variants: the first rounds show the head start of the AOT code, the later ones where the variants meet
* `compile-training.csv`, `compile-training-summary.txt` – caches from training runs of 5, 20 and 60 rounds, and a cache whose AOT code has no invocation counters (`-XX:-UseAOTCodeCounters` during cache creation), 8 runs with 60 rounds each
* `profiles.csv`, `profiles-summary.txt` – where the gap to the run without a cache after 20 rounds comes from, 15 runs with 100 rounds each: without a cache, with the cache without AOT code, with the same cache but `-XX:-AOTReplayTraining` (the JVM ignores the method profiles), and with a cache created with `-XX:-AOTClassLinking` (loaded classes only, no linking, no profiles, no code)
* `compilation-<variant>.txt`, `compilation-<variant>.log.gz` – `-XX:+PrintCompilation` logs of 40 rounds and their evaluation by `scripts/analyze-compilation.py`; `compilation-nocounters.*` is a run of 60 rounds with the cache whose AOT code has no counters
* `aot-code-entries.txt` – how much AOT code the caches from training runs of 5, 20 and 60 rounds contain (`-Xlog:aot`)
* `gc-mismatch.txt` – what happens when the cache was created with G1 and the application starts with the Serial, Parallel or Z garbage collector

`scripts/run-code-compilation-training-repeat.sh <path-to-jdk-28> <machine-id> <build-name>` repeats the training-length measurement with three independently created caches per training length, in about 10 minutes. The article's table on the training length comes from the run on 28-ea+20:

* `compile-training-repeat-<build>.csv`, `compile-training-repeat-summary-<build>.txt` – 9 caches (5, 20 and 60 training rounds, three each), 8 runs with 60 rounds per cache
* `training-repeat-caches-<build>.txt`, `training-repeat-environment-<build>.txt` – cache sizes, JDK build and load
* `training-repeat-aot-code-ea20.txt` – how much AOT code each of the nine caches on 28-ea+20 contains (`-Xlog:aot`)

### Method profiles (JEP 515)

`scripts/run-method-profiling-measurements.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>` measures what the method profiles in the AOT cache do to the warmup and the peak performance, in about 30 minutes, and writes the results to `results/method-profiling/<machine-id>/`. All Java 28 caches are created with `-XX:-AOTCodeCaching`, so they contain classes and profiles but no AOT code – like a Java 25 cache. In the variants, `noreplay` is the cache from 20 training iterations started with `-XX:+UnlockDiagnosticVMOptions -XX:-AOTReplayTraining`: the JVM uses the loaded and linked classes, but not the profiles.

* `environment.txt`, `cache-creation.txt` – as above; caches from training runs of 5, 20, 60 and 100 iterations
* `training-length.csv`, `training-length-summary.txt` – Java 28, 15 runs of 100 iterations: without a cache, `noreplay`, and the four training lengths
* `long-run.csv`, `long-run-summary.txt` – Java 28, 10 runs of 200 iterations: without a cache, `noreplay`, and the caches from 20, 60 and 100 training iterations – whether the variants meet once the iterations have passed the training run
* `java25.csv`, `java25-summary.txt` – Java 25, 15 runs of 100 iterations: without a cache, `noreplay`, and the cache from 20 training iterations
* `hello-java28.csv`, `hello-java25.csv` and their summaries – the example program of JEP 515 (`scripts/HelloStreamWarmup.java`), 30 starts each without a cache, with a cache but without profiles, and with profiles
* `compilations-<java>-<variant>.txt`, `compilation-<java>-<variant>.log.gz` – one run of 100 iterations with `-XX:+PrintCompilation -XX:+CITime`: the compilations per iteration and level (`scripts/compilations-per-iteration.py`) and the accumulated compiler times
* `logcompilation-java28-<variant>.txt` – one run of 100 iterations with `-XX:+LogCompilation`, evaluated by `scripts/analyze-logcompilation.py`: the level each method ends with, the compile queue per level and time window – including the compilations the JVM queues without an invocation (reason `must_be_compiled`) –, and for the C2 compilations the trap history in the profiles, the speculations C2 drops because of it, the type profiles of the virtual call sites and the inlining decisions; the logs themselves are about 100 MB each and not part of the results
* `jfr-samples-java28.txt` – JFR execution samples from second 4 to the end of 5 runs each, with and without the profiles, evaluated by `scripts/analyze-jfr-samples.py`: where the time goes, as shares per leaf method, and the bytes allocated by the main thread
* `inlining-comparison-java28.txt` – the C2 inlining decisions of one run with and one without the profiles, compared call site by call site (`scripts/compare-inlining.py <log-a> <log-b>`): how many call sites C2 inlines only in one of the two runs, by the reason it gives in the other, and how many of them lead through lambda, method handle or string concatenation classes

Ten follow-up scripts use the programs and caches of the main script and add to the same directory:

* `scripts/run-method-profiling-followup.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>` (about 10 minutes): `gc-heap-sizing.txt` – heap sizing per variant from `-Xlog:gc` (`scripts/analyze-gc-log.py`); `fixed-heap.csv` and its summary – Java 28 with `-Xms2g -Xmx2g -Xmn512m`, 15 runs of 100 iterations, to rule out the heap sizing as the cause of the lasting gap; `logcompilation-java25-<variant>.txt` – the compile queue on Java 25
* `scripts/run-method-profiling-eager.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>` (about 11 minutes): the diagnostic option `AOTCompileEagerly`, which Java 28 switches on whenever the AOT code cache is in use – also for a cache without AOT code – and which makes the JVM compile the methods from the training run as soon as their classes are initialized. `eager-flag.txt` shows the value in both versions, `eager-java28.csv` switches it off in Java 28, `eager-java25.csv` on in Java 25 (15 runs of 100 iterations each), and `logcompilation-java28-training20-noeager.txt` and `logcompilation-java25-training20-eager.txt` show the compile queues
* `scripts/run-method-profiling-counters.sh <path-to-jdk-28> <machine-id>` (macOS with Xcode, no root rights needed, about 10 minutes): CPU performance counters of the main thread from Instruments (template "CPU Counters", mode "CPU Bottlenecks"), 4 runs each without a cache, without profiles and with profiles. `cpu-counters.txt` – cycles, instructions and IPC per iteration in the last 2 seconds (`scripts/analyze-pmc-samples.py`); `cpu-bottlenecks.txt` – the shares of useful work and of the instruction-processing, instruction-delivery and discarded bottlenecks (`scripts/analyze-cpu-bottlenecks.py`)
* `scripts/run-method-profiling-lambda.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>` (about 4 minutes): `AotLambda` with and without the profiles. `lambda-purged.txt` – the profile rows the JVM removes while writing the training data (`-Xlog:aot+training=debug`); `lambda-java28.csv`, `lambda-java25.csv` and their summaries – 10 runs of 30 rounds each without a cache, without profiles and with profiles; `lambda-inlining.txt` – C2’s decisions on the lambda call (`-XX:+PrintInlining`); `aotcompile-purged.txt` – the same removal for `AotCompile`, summarized by `scripts/summarize-purged.py`.
* `scripts/run-method-profiling-traps.sh <path-to-jdk-28> <machine-id>` (about 8 minutes): a cache from a training run with `-XX:PerMethodTrapLimit=0 -XX:PerMethodSpecTrapLimit=0`, whose profiles carry hardly any trap history – `trap-history.csv` and its summary (15 runs of 100 iterations) and `logcompilation-java28-training20-notraps.txt`
* `scripts/run-method-profiling-iterative.sh <path-to-jdk-28> <machine-id>` (JDK 28-ea+23 or newer, uses the caches of the lambda script too, about 15 minutes): iterative training (JDK-8353598), where a training run loads an existing cache with `-XX:AOTCache` and writes a new one with `-XX:AOTCacheOutput`. `iterative-purged.txt` – the profile rows removed in the first and in the second training run, for `AotLambda` and for `AotCompile` (20 iterations, then 20 more on top, and 40 in one run for comparison); `iterative-lambda.csv`, `iterative-compile.csv` and their summaries – the iteratively trained caches against the single ones (10 runs of 30 and 15 runs of 100 iterations); `iterative-inlining.txt` – the inlining comparison for the iteratively trained cache
* `scripts/run-method-profiling-builds.sh <path-to-jdk-a> <name-a> <path-to-jdk-b> <name-b> <machine-id>` (about 15 minutes): two Java 28 builds measured alternately in one series, 10 runs of 200 iterations each without a cache and with the caches from 20 and 100 training iterations – `builds.csv`, `builds-summary.txt`, `builds-versions.txt`; it shows whether a difference between two evenings comes from the builds or from the series
* `scripts/run-method-profiling-exclusion.sh <path-to-jdk-28> <machine-id>` (JDK 28-ea+23 or newer, a few seconds): `lambda-exclusion.txt` – why the training run drops the lambda class of `AotLambda`, also when it loads the class from an existing cache: `-Xlog:aot=debug` shows it as “Unreferenced hidden class” right before the profile rows are purged, and the assembly phase generates it anew
* `scripts/run-method-profiling-aot-code.sh <path-to-jdk-28> <machine-id>` (about 4 minutes): `AotLambda` with a cache that contains AOT code – `lambda-aot-code.csv` and its summary (10 runs of 30 iterations without a cache, without profiles, with profiles but without AOT code, and with profiles and AOT code) and `lambda-aot-code.txt` (the purged rows, the compilations of `Steps` and C2’s decision on the lambda call)
* `scripts/run-method-profiling-long-run-java25.sh <path-to-jdk-25> <machine-id>` (about 5 minutes): the 200-iteration series of `long-run.csv` on Java 25, without a cache and with a cache from 100 training iterations – `long-run-java25.csv` and its summary (10 runs each); it shows whether Java 25, which delays lukewarm methods by a fixed factor instead of their training count, falls behind at the same point as Java 28
* `scripts/run-method-profiling-pause.sh <path-to-jdk-28> <path-to-jdk-25> <machine-id>` (about 2 minutes): `lambda-pause.txt` – `AotLambda` with and without the pause before the first call of `Steps.run()`, on both versions: 3 runs of 10 iterations each without a cache, without profiles and with profiles (mean of iterations 6 to 10), and one run each with `-XX:+PrintCompilation -XX:+PrintInlining` for the order of the compilations of `Steps` and C2's decision on the lambda call

`scripts/measure.py` starts the variants alternately, measures the wall time of each `java` process and collects the duration of each round. The summaries give the first quartile, the median and the third quartile.
