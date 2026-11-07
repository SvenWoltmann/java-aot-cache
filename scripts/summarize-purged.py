"""Summarizes what the JVM removes from the training data while writing the AOT cache.

Usage: python3 summarize-purged.py <log-file> ...

The log files come from -Xlog:aot+training=debug during cache creation. Two
kinds of lines matter (methodData.cpp and trainingData.cpp):

* "Purged <class> from MDO: excluded class" -- a row of a type profile that
  named a class the cache does not contain; the JVM clears the row and the
  call counter of the call site,
* "Cleanup MTD <method>" -- the training data of a method of such a class,
  which the JVM drops completely.

Lambda classes appear with an address that differs from run to run; the
script replaces it with "0x...".
"""

import collections
import re
import sys

PURGED = re.compile(r"Purged (\S+) from MDO: (.*)$")
CLEANUP = re.compile(r"Cleanup MTD (\S+?)::")


def kind(name):
    if "$$Lambda" in name:
        return "lambda class"
    if "LambdaForm" in name or "$Holder" in name or "$Species_" in name:
        return "method handle class"
    return "other class"


def main():
    purged = collections.Counter()
    classes = collections.Counter()
    cleanup = collections.Counter()
    for path in sys.argv[1:]:
        for line in open(path):
            match = PURGED.search(line)
            if match:
                name = re.sub(r"\+0x[0-9a-f]+", "+0x...", match.group(1))
                purged[(match.group(2).strip(), kind(name))] += 1
                classes[name] += 1
            match = CLEANUP.search(line)
            if match:
                cleanup[match.group(1)] += 1
    print("Rows removed from type profiles (\"Purged ... from MDO\"), by reason and kind of class:")
    for (reason, k), n in purged.most_common():
        print(f"  {n:5d}  {reason}, {k}")
    print(f"  {sum(purged.values()):5d}  in total")
    print("\nClasses with the most removed rows:")
    for name, n in classes.most_common(15):
        print(f"  {n:5d}  {name}")
    print(f"\nMethods whose training data the JVM drops (\"Cleanup MTD\"): {sum(cleanup.values())}")
    for name, n in cleanup.most_common(10):
        print(f"  {n:5d}  {name}")


if __name__ == "__main__":
    main()
