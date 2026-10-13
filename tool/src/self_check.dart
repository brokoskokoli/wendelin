// Kleines Prüfgerüst für die Selbsttests der Werkzeuge unter `tool/`.
//
// Das Root-Paket hat bewusst keine Abhängigkeit auf package:test. Die
// Selbsttests (`dart run tool/self_test.dart`) laufen deshalb mit diesem
// Gerüst, so wie `android_device.sh --self-test` und
// `check_apk.sh --self-test` ihre eigenen Prüfungen mitbringen.
import 'dart:io';

/// Sammelt Prüfungen und meldet am Ende das Ergebnis.
final class SelfCheck {
  final _failures = <String>[];
  var _count = 0;
  String _group = '';

  /// Setzt die Gruppe für die folgenden Prüfungen (nur für die Ausgabe).
  void group(String name) => _group = name;

  /// [actual] muss [expected] entsprechen. Mengen werden sortiert
  /// verglichen, alles andere über `toString()`.
  void eq(Object? actual, Object? expected, String what) {
    _count++;
    final a = _norm(actual), e = _norm(expected);
    if (a != e) {
      _failures.add('$_group: $what\n    erwartet: $e\n    ist:      $a');
    }
  }

  /// [condition] muss gelten.
  void isTrue(bool condition, String what) {
    _count++;
    if (!condition) _failures.add('$_group: $what');
  }

  /// Gibt das Ergebnis aus und liefert den Exit-Code.
  int finish(String name) {
    if (_failures.isEmpty) {
      stdout.writeln('$name: ok ($_count Prüfungen)');
      return 0;
    }
    for (final f in _failures) {
      stderr.writeln('FEHLER $f');
    }
    stderr.writeln('$name: ${_failures.length} von $_count Prüfungen rot');
    return 1;
  }

  static String _norm(Object? v) => switch (v) {
    final Set<Object?> s => (s.map((e) => '$e').toList()..sort()).toString(),
    _ => '$v',
  };
}
