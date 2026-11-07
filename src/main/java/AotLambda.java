import java.util.function.IntUnaryOperator;

void main(String[] args) throws InterruptedException {
  int rounds = args.length > 0 ? Integer.parseInt(args[0]) : 10;
  int factor = 31;
  int offset = 7;
  IntUnaryOperator op = x -> (x * factor + offset) ^ (x >>> 3);

  Steps.init();
  Thread.sleep(500); // gives the JVM time to compile Steps before its first call

  for (int i = 1; i <= rounds; i++) {
    long start = System.nanoTime();
    int sum = 0;
    for (int j = 0; j < 1_000; j++) {
      sum = Steps.run(op, sum);
    }
    long millis = (System.nanoTime() - start) / 1_000_000;
    IO.println("Iteration %2d: %4d ms (%d)".formatted(i, millis, sum));
  }
}

class Steps {
  static final int[] DATA = new int[100_000];

  static void init() {}

  static int run(IntUnaryOperator op, int sum) {
    int[] data = DATA;
    for (int i = 0; i < data.length; i++) {
      sum += step(op, data[i] + i);
    }
    return sum;
  }

  static int step(IntUnaryOperator op, int value) {
    return op.applyAsInt(value);
  }
}
