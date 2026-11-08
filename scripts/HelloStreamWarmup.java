// The example program of JEP 515, "Ahead-of-Time Method Profiling"
// (https://openjdk.org/jeps/515), unchanged. It runs a short stream pipeline
// 100,000 times; the JEP reports 90 ms with an AOT cache without profiles and
// 73 ms with profiles.
//
// Copyright (c) Oracle Corporation and/or its affiliates. Licensed under the
// GNU General Public License, version 2, with the Classpath Exception, as
// stated on the JEP page: https://openjdk.org/legal/gplv2+ce.html

import java.util.*;
import java.util.stream.*;

public class HelloStreamWarmup {

    static String greeting(int n) {
        var words = List.of("Hello", "" + n, "world!");
        return words.stream()
            .filter(w -> !w.contains("0"))
            .collect(Collectors.joining(", "));
    }

    public static void main(String... args) {
        for (int i = 0; i < 100_000; i++)
            greeting(i);
        System.out.println(greeting(0));  // "Hello, world!"
    }

}
