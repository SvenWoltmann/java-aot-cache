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

Both programs are compact source files with an instance `main()` method, so they need Java 25 or newer. They are in the unnamed package, since a compact source file cannot declare a package.

* `AotTest` – prints the current date and time; the example of the class-loading article. It starts within a few dozen milliseconds, so it shows what the AOT cache saves on a tiny program.
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

`scripts/measure.py` starts the variants alternately, measures the wall time of each `java` process and collects the duration of each round. The summaries give the first quartile, the median and the third quartile.
