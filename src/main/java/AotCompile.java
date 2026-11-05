import javax.tools.*;
import javax.tools.JavaFileObject.Kind;

static final String SOURCE_TEMPLATE =
    """
    import java.util.*;
    import java.util.stream.*;

    public class Shapes%1$d {
      sealed interface Shape permits Circle, Square, Rectangle {}
      record Circle(double radius) implements Shape {}
      record Square(double side) implements Shape {}
      record Rectangle(double width, double height) implements Shape {}

      static double area(Shape shape) {
        return switch (shape) {
          case Circle(double r) -> Math.PI * r * r;
          case Square(double s) -> s * s;
          case Rectangle(double w, double h) -> w * h;
        };
      }

      static Map<String, Double> totals(List<Shape> shapes) {
        return shapes.stream()
            .collect(Collectors.groupingBy(
                shape -> shape.getClass().getSimpleName(),
                TreeMap::new,
                Collectors.summingDouble(Shapes%1$d::area)));
      }

      static String describe(List<Shape> shapes) {
        var text = new StringBuilder();
        for (var entry : totals(shapes).entrySet()) {
          text.append("%%s: %%.2f%%n".formatted(entry.getKey(), entry.getValue()));
        }
        return text.toString();
      }
    }
    """;

void main(String[] args) {
  int iterations = args.length > 0 ? Integer.parseInt(args[0]) : 10;
  JavaCompiler compiler = ToolProvider.getSystemJavaCompiler();
  for (int i = 1; i <= iterations; i++) {
    long start = System.nanoTime();
    boolean success = compile(compiler);
    long millis = (System.nanoTime() - start) / 1_000_000;
    String result = success ? "ok" : "failed";
    IO.println("Iteration %2d: %4d ms (%s)".formatted(i, millis, result));
  }
}

boolean compile(JavaCompiler compiler) {
  var sources = new ArrayList<JavaFileObject>();
  for (int n = 0; n < 50; n++) {
    sources.add(new SourceFile("Shapes" + n, SOURCE_TEMPLATE.formatted(n)));
  }
  var standardFileManager = compiler.getStandardFileManager(null, null, null);
  var fileManager = new DiscardingFileManager(standardFileManager);
  return compiler.getTask(null, fileManager, null, null, null, sources).call();
}

class SourceFile extends SimpleJavaFileObject {
  private final String code;

  SourceFile(String className, String code) {
    super(URI.create("string:///" + className + ".java"), Kind.SOURCE);
    this.code = code;
  }

  @Override
  public CharSequence getCharContent(boolean ignoreEncodingErrors) {
    return code;
  }
}

class DiscardingFileManager extends ForwardingJavaFileManager<JavaFileManager> {
  DiscardingFileManager(JavaFileManager fileManager) {
    super(fileManager);
  }

  @Override
  public JavaFileObject getJavaFileForOutput(
      Location location, String className, Kind kind, FileObject sibling) {
    var uri = URI.create("mem:///" + className + kind.extension);
    return new SimpleJavaFileObject(uri, kind) {
      @Override
      public OutputStream openOutputStream() {
        return OutputStream.nullOutputStream();
      }
    };
  }
}
