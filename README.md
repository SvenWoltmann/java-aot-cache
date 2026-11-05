# Java AOT Cache

[![Build](https://github.com/SvenWoltmann/java-aot-cache/actions/workflows/build.yml/badge.svg)](https://github.com/SvenWoltmann/java-aot-cache/actions/workflows/build.yml)
[![Maintainability Rating](https://sonarcloud.io/api/project_badges/measure?project=SvenWoltmann_java-aot-cache&metric=sqale_rating)](https://sonarcloud.io/dashboard?id=SvenWoltmann_java-aot-cache)
[![Reliability Rating](https://sonarcloud.io/api/project_badges/measure?project=SvenWoltmann_java-aot-cache&metric=reliability_rating)](https://sonarcloud.io/dashboard?id=SvenWoltmann_java-aot-cache)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=SvenWoltmann_java-aot-cache&metric=security_rating)](https://sonarcloud.io/dashboard?id=SvenWoltmann_java-aot-cache)

Example programs and measurements of the HappyCoders.eu articles on the AOT cache of Project Leyden:

* "Ahead-of-Time Class Loading & Linking" – JEP 483, 514, 515 and 516 ([English](https://www.happycoders.eu/java/ahead-of-time-class-loading-and-linking/), [German](https://www.happycoders.eu/de/java/ahead-of-time-class-loading-and-linking/))
* "Ahead-of-Time Code Compilation" – JEP 544, Java 28 (not yet published)

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

`scripts/run-code-compilation-measurements.sh <path-to-jdk-28> <machine-id>` reproduces all measurements of the code-compilation article in about 15 minutes and writes them to `results/code-compilation/<machine-id>/`:

* `environment.txt` – date, CPU and JDK build
* `cache-creation.txt` – duration of training run plus cache creation, and the sizes of all caches
* `aottest.csv`, `aottest-summary.txt` – 50 starts of `AotTest` each without a cache, with a cache without AOT code, and with a cache with AOT code
* `compile-20.csv`, `compile-20-summary.txt` – 30 runs of `AotCompile` with 20 rounds each, same three variants
* `compile-100.csv`, `compile-100-summary.txt` – 10 runs with 100 rounds each, to see where the variants meet
* `compile-training.csv`, `compile-training-summary.txt` – caches from training runs of 5, 20 and 60 rounds, and a cache whose AOT code has no invocation counters (`-XX:-UseAOTCodeCounters` during cache creation), 8 runs with 60 rounds each
* `compilation-<variant>.txt`, `compilation-<variant>.log.gz` – `-XX:+PrintCompilation` logs of 40 rounds and their evaluation by `scripts/analyze-compilation.py`
* `gc-mismatch.txt` – what happens when the cache was created with G1 and the application starts with the Serial, Parallel or Z garbage collector

`scripts/measure.py` starts the variants alternately, measures the wall time of each `java` process and collects the duration of each round. The summaries give the first quartile, the median and the third quartile.
