// Gate-Schritt `kotlin-unit`: JVM-Unit-Tests der Kotlin-Logik unter
// app/android/app/src/test (./gradlew :app:testDebugUnitTest).
import 'dart:io';

/// Ordner der Testberichte (Flutter legt den Build-Ordner unter app/build ab).
const kotlinReportDir = 'app/build/app/test-results/testDebugUnitTest';

/// Ordner des Android-SDK: `ANDROID_HOME`, `ANDROID_SDK_ROOT`, dann die
/// üblichen Orte unter [home]; `null`, wenn keiner existiert.
String? androidSdk(
  Map<String, String> env,
  String home,
  bool Function(String) isDir,
) {
  for (final c in [
    env['ANDROID_HOME'],
    env['ANDROID_SDK_ROOT'],
    '$home/Library/Android/sdk',
    '$home/Android/Sdk',
  ]) {
    if (c != null && c.isNotEmpty && isDir(c)) return c;
  }
  return null;
}

/// Summe der `tests`- und `failures`-Zähler aus JUnit-XML-Berichten.
({int tests, int failures}) countJUnit(Iterable<String> xmlTexts) {
  var tests = 0, failures = 0;
  final suite = RegExp(r'<testsuite\b[^>]*>');
  int attr(String tag, String name) =>
      int.tryParse(RegExp('\\b$name="(\\d+)"').firstMatch(tag)?[1] ?? '') ?? 0;
  for (final x in xmlTexts) {
    final tag = suite.firstMatch(x)?[0];
    if (tag == null) continue;
    tests += attr(tag, 'tests');
    failures += attr(tag, 'failures') + attr(tag, 'errors');
  }
  return (tests: tests, failures: failures);
}

/// Berichte im Ordner [dir] (leer, wenn er fehlt).
List<String> readReports(String dir) {
  final d = Directory(dir);
  if (!d.existsSync()) return const [];
  return [
    for (final f in d.listSync())
      if (f is File && f.path.endsWith('.xml')) f.readAsStringSync(),
  ];
}

/// Löscht alte Berichte im Ordner [dir], damit nur der aktuelle Lauf zählt.
void clearReports(String dir) {
  final d = Directory(dir);
  if (d.existsSync()) d.deleteSync(recursive: true);
}

/// Hauptversion aus der Ausgabe von `java -version` (`"21.0.5"`, `"1.8.0_x"`,
/// `openjdk 23 2024`); `null`, wenn nicht erkennbar.
int? jdkMajor(String versionOutput) {
  final m =
      RegExp(r'version "(\d+)(?:\.(\d+))?').firstMatch(versionOutput) ??
      RegExp(r'^\s*\w+ (\d+)\b').firstMatch(versionOutput);
  if (m == null) return null;
  final major = int.parse(m[1]!);
  return major == 1 ? int.tryParse(m[2] ?? '') : major;
}

/// Neueste JDK-Hauptversion, mit der Gradle hier noch baut.
const maxGradleJdk = 21;

/// JDK-Orte, wie in `tool/e2e_android.sh`: zuerst openjdk@21 von Homebrew,
/// sonst das JBR von Android Studio.
const gradleJdkCandidates = [
  '/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home',
  '/usr/local/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home',
  '/Applications/Android Studio.app/Contents/jbr/Contents/Home',
];

/// `JAVA_HOME` für Gradle, wenn das aktuelle JDK ([versionOutput]) zu neu ist
/// (Major > [maxGradleJdk]) und ein Kandidat mit `bin/java` existiert
/// ([hasJava]); sonst `null` (Umgebung unverändert, fail-open).
String? gradleJavaHome(
  String versionOutput,
  bool Function(String javaHome) hasJava, {
  List<String> candidates = gradleJdkCandidates,
}) {
  final major = jdkMajor(versionOutput);
  if (major == null || major <= maxGradleJdk) return null;
  for (final c in candidates) {
    if (hasJava(c)) return c;
  }
  return null;
}
