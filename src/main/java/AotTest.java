void main() {
  var now = LocalDateTime.now();
  var nowString =
      now.format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM));
  System.out.println("Hello, it's " + nowString);
}
