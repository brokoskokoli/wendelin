// Selbsttests von tool/src/channel_check.dart mit kleinen Beispieldateien.
import 'dart:io';

import 'channel_check.dart';
import 'kotlin_unit.dart';
import 'self_check.dart';

const _dartPath = 'app/lib/platform/x.dart';
const _namesPath = 'app/lib/platform/channels.dart';
const _ktPath = 'app/android/app/src/main/kotlin/app/wendelin/XChannel.kt';

const _manifest =
    '''
{
  "dartNames": "$_namesPath",
  "channels": {
    "app.wendelin/x": {
      "dart": ["$_dartPath"],
      "kotlin": ["$_ktPath"],
      "toKotlin": {
        "ping": {"args": ["who"], "returns": "none"},
        "name": {"args": [], "returns": "value"}
      },
      "toDart": {
        "changed": {"args": [], "returns": "none"}
      }
    }
  }
}
''';

const _names = "const xChannelName = 'app.wendelin/x';\n";

const _dart = '''
class P {
  Future<void> go() => _ch.invokeMethod<void>('ping', {'who': 1});
  Future<String?> n() => _ch.invokeMethod<String>('name');
  void h() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'changed':
          break;
      }
    });
  }
}
''';

const _kt = '''
class K {
    fun h(call: MethodCall) {
        when (call.method) {
            "ping" -> call.argument<String>("who")
            "name" -> 1
        }
    }
    fun n() { channel.invokeMethod("changed", null) }
    companion object { const val CHANNEL = "app.wendelin/x" }
}
''';

ChannelReport _run({
  String manifest = _manifest,
  String dart = _dart,
  String kt = _kt,
  String names = _names,
  Map<String, String> extraDart = const {},
}) => checkChannels(
  manifestText: manifest,
  manifestPath: 'app/channels.json',
  read: (p) =>
      {_dartPath: dart, _namesPath: names, _ktPath: kt, ...extraDart}[p],
  dartFiles: [_dartPath, _namesPath, ...extraDart.keys],
  kotlinFiles: [_ktPath],
);

bool _has(ChannelReport r, String part) =>
    r.errors.any((e) => e.contains(part));

void channelChecks(SelfCheck t) {
  t.group('check_channels');
  final ok = _run();
  t.eq(ok.errors, <String>[], 'Beispiel ist grün');
  t.eq(ok.channels, 1, 'ein Kanal');
  t.eq(ok.methods, 3, 'drei Methoden');

  var r = _run(kt: _kt.replaceFirst('"ping" ->', '"pong" ->'));
  t.isTrue(
    _has(r, 'XChannel.kt:4: app.wendelin/x: Methode "pong"') &&
        _has(r, 'Methode "ping" (Dart → Kotlin): kein Handler im Kotlin-Code'),
    'Methode nur auf der Kotlin-Seite umbenannt',
  );
  r = _run(dart: _dart.replaceFirst("'ping'", "'pong'"));
  t.isTrue(
    _has(r, 'x.dart:2: app.wendelin/x: Methode "pong"') &&
        _has(r, 'Methode "ping" (Dart → Kotlin): kein Aufruf im Dart-Code'),
    'Methode nur auf der Dart-Seite umbenannt',
  );
  r = _run(dart: _dart.replaceFirst("'who': 1", "'whom': 1"));
  t.isTrue(
    _has(r, 'x.dart:2: app.wendelin/x: Argument "whom" von "ping"'),
    'Argumentschlüssel nur in Dart umbenannt',
  );
  r = _run(kt: _kt.replaceFirst('("who")', '("whom")'));
  t.isTrue(
    _has(r, 'XChannel.kt:4: app.wendelin/x: Argument "whom" wird gelesen') &&
        _has(
          r,
          'Argument "who" von "ping" wird im Kotlin-Handler nicht gelesen',
        ),
    'Argumentschlüssel nur in Kotlin umbenannt',
  );
  r = _run(dart: _dart.replaceFirst("case 'changed'", "case 'changes'"));
  t.isTrue(
    _has(r, 'Methode "changes"') && _has(r, '"changed" (Kotlin → Dart)'),
    'Rückruf nur in Dart umbenannt',
  );
  r = _run(
    kt: _kt.replaceFirst('invokeMethod("changed"', 'invokeMethod("changes"'),
  );
  t.isTrue(_has(r, 'XChannel.kt:8'), 'Rückruf nur in Kotlin umbenannt');
  r = _run(dart: _dart.replaceFirst('<String>', '<void>'));
  t.isTrue(_has(r, 'Rückgabe von "name" ist none'), 'falsche Rückgabeart');
  r = _run(
    names: '',
    extraDart: {'app/lib/y.dart': "const a = 'app.wendelin/z';"},
  );
  t.isTrue(
    _has(r, 'y.dart:1: Kanal app.wendelin/z fehlt im Manifest') &&
        _has(r, 'Kanalname fehlt in $_namesPath'),
    'Kanal ohne Manifest-Eintrag und Eintrag ohne Namen',
  );
  r = _run(kt: _kt.replaceFirst('app.wendelin/x', 'app.wendelin/q'));
  t.isTrue(
    _has(r, 'Kanalname fehlt im Kotlin-Code') &&
        _has(r, 'Kanal app.wendelin/q fehlt im Manifest'),
    'Kotlin-Kanalname weicht ab',
  );
  r = _run(
    manifest: _manifest.replaceFirst(
      '"ping": {"args": ["who"], "returns": "none"},',
      '"ping": {"args": ["who"], "returns": "none"},\n'
          '"extra": {"args": [], "returns": "none"},',
    ),
  );
  t.isTrue(
    _has(r, 'Methode "extra" (Dart → Kotlin): kein Aufruf im Dart-Code'),
    'Manifest-Eintrag ohne Code',
  );
  r = _run(kt: '// "ghost" -> 1\n$_kt');
  t.eq(r.errors, <String>[], 'Kommentare zählen nicht');
  r = _run(
    kt: _kt.replaceFirst(
      '"name" -> 1',
      '"name" -> when (call.argument<String>("who")) {\n"mode" -> 1\nelse -> 2\n}',
    ),
  );
  t.eq(r.errors, <String>[], 'Zweige anderer when-Blöcke sind keine Methoden');
  channelArgChecks(t);
  r = _run(manifest: '{');
  t.isTrue(_has(r, 'kein gültiges JSON'), 'kaputtes Manifest');
}

/// Argumentschlüssel: Helfer, Spreads, `get` und Zugriff je Methode.
void channelArgChecks(SelfCheck t) {
  ChannelReport r;
  // Schlüssel aus Helfern und Spreads, Zeichenketten im Wert zählen nicht.
  const helperDart = '''
class P {
  Future<void> go() =>
      _ch.invokeMethod<void>('ping', {...?_f(1)});
  Future<String?> n() => _ch.invokeMethod<String>('name');
  void h() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'changed':
          break;
      }
    });
  }
  static Map<String, Object?> _f(int v) => {
    'who': v ? 'who' : 'w',
  };
}
''';
  r = _run(dart: helperDart);
  t.eq(r.errors, <String>[], 'Schlüssel aus Spread-Helfer aufgelöst');
  r = _run(dart: helperDart.replaceFirst("{\n    'who'", "{\n    'whom'"));
  t.isTrue(
    _has(r, 'Argument "whom" von "ping" fehlt im Manifest') &&
        _has(r, 'Argument "who" von "ping" wird im Dart-Code nicht gesendet'),
    'Umbenannter Schlüssel im Helfer wird erkannt',
  );
  r = _run(dart: _dart.replaceFirst("{'who': 1}", "{'x': 'who'}"));
  t.isTrue(
    _has(r, 'Argument "who" von "ping" wird im Dart-Code nicht gesendet'),
    'Wert statt Schlüssel zählt nicht',
  );
  // Switch-Ausdruck als Helfer: Arme werden vereinigt, Unauflösbares ist rot.
  const switchDart = '''
class P {
  Future<void> go(int v) =>
      _ch.invokeMethod<void>('ping', {'who': 1, ...f(v)});
  Future<String?> n() => _ch.invokeMethod<String>('name');
  void h() {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'changed':
          break;
      }
    });
  }
}
Map<String, Object?> f(int v) => switch (v) {
  1 => {'a': 1},
  _ => {'b': v},
};
''';
  const switchManifest = '"args": ["who"]';
  final swManifest = _manifest.replaceFirst(
    switchManifest,
    '"args": ["who", "a", "b"]',
  );
  final swKt = _kt.replaceFirst(
    'call.argument<String>("who")',
    'call.argument<String>("who"); call.argument<String>("a"); '
        'call.argument<String>("b")',
  );
  r = _run(manifest: swManifest, dart: switchDart, kt: swKt);
  t.eq(r.errors, <String>[], 'Switch-Helfer: Arme vereinigt');
  r = _run(
    manifest: swManifest,
    dart: switchDart.replaceFirst("'b': v", "'c': v"),
  );
  t.isTrue(
    _has(r, 'Argument "c" von "ping" fehlt im Manifest') &&
        _has(r, 'Argument "b" von "ping" wird im Dart-Code nicht gesendet'),
    'Switch-Helfer: Zusatz- und fehlender Schlüssel werden erkannt',
  );
  r = _run(
    manifest: swManifest,
    dart: switchDart.replaceFirst("_ => {'b': v}", '_ => other(v)'),
    kt: swKt,
  );
  t.isTrue(
    _has(r, 'Argumente nicht auflösbar'),
    'Switch-Arm ohne Literal ist rot (fail-closed)',
  );
  r = _run(dart: _dart.replaceFirst("{'who': 1}", '{...mystery()}'));
  t.isTrue(
    _has(r, 'Argumente nicht auflösbar'),
    'Unauflösbarer Spread ist rot, kein globaler Rückfall',
  );
  // Kotlin: `args?.get`, Zugriff je Methode (auch über Hilfsfunktionen).
  const ktGet = '''
class K {
    fun h(call: MethodCall) {
        val args = call.arguments as? Map<*, *>
        when (call.method) {
            "ping" -> use(args?.get("who"))
            "name" -> 1
        }
    }
    fun n() { channel.invokeMethod("changed", null) }
    companion object { const val CHANNEL = "app.wendelin/x" }
}
''';
  r = _run(kt: ktGet);
  t.eq(r.errors, <String>[], 'args?.get("k") wird erkannt');
  r = _run(kt: ktGet.replaceFirst('get("who")', 'get("whom")'));
  t.isTrue(
    _has(r, 'Argument "whom" wird gelesen') &&
        _has(r, 'Argument "who" von "ping" wird im Kotlin-Handler nicht'),
    'Umbenannter get-Schlüssel wird erkannt',
  );
  const ktHelper = '''
class K {
    fun h(call: MethodCall) {
        when (call.method) {
            "ping" -> read(call)
            "name" -> call.argument<String>("who")
        }
    }
    fun read(call: MethodCall) = call.argument<String>("who")
    fun n() { channel.invokeMethod("changed", null) }
    companion object { const val CHANNEL = "app.wendelin/x" }
}
''';
  r = _run(kt: ktHelper);
  t.eq(r.errors, <String>[], 'Lesen in aufgerufener Hilfsfunktion');
  r = _run(
    kt: ktHelper.replaceFirst(
      'fun read(call: MethodCall) = call.argument<String>("who")',
      'fun read(call: MethodCall) = 1',
    ),
  );
  t.isTrue(
    _has(r, 'Argument "who" von "ping" wird im Kotlin-Handler nicht gelesen'),
    'Lesen nur in einer anderen Methode genügt nicht',
  );
}

/// Selbsttests der Hilfen des Gate-Schritts `kotlin-unit`.
void kotlinUnitChecks(SelfCheck t) {
  t.group('kotlin-unit');
  final dirs = {'/env/sdk', '/home/u/Library/Android/sdk'};
  bool isDir(String p) => dirs.contains(p);
  t.eq(
    androidSdk({'ANDROID_HOME': '/env/sdk'}, '/home/u', isDir),
    '/env/sdk',
    'ANDROID_HOME zuerst',
  );
  t.eq(
    androidSdk({'ANDROID_HOME': '/fehlt'}, '/home/u', isDir),
    '/home/u/Library/Android/sdk',
    'fehlender Ordner fällt auf den Standardort zurück',
  );
  t.eq(androidSdk({}, '/nirgends', isDir), null, 'ohne SDK null');
  final c = countJUnit([
    '<testsuite name="a" tests="4" skipped="0" failures="1" errors="0">',
    '<testsuite name="b" tests="3" failures="0" errors="2">',
    'kein Bericht',
  ]);
  t.eq(jdkMajor('openjdk version "21.0.5" 2024-10-15'), 21, 'JDK 21');
  t.eq(jdkMajor('openjdk version "23.0.1" 2024-10-15'), 23, 'JDK 23');
  t.eq(jdkMajor('java version "1.8.0_392"'), 8, 'JDK 8');
  t.eq(jdkMajor(''), null, 'unbekannt');
  bool has(String h) =>
      h == gradleJdkCandidates[0] || h == gradleJdkCandidates[2];
  const v23 = 'openjdk version "23.0.1"';
  t.eq(gradleJavaHome(v23, has), gradleJdkCandidates[0], 'JDK 23: openjdk@21');
  t.eq(
    gradleJavaHome(v23, (h) => h == gradleJdkCandidates[2]),
    gradleJdkCandidates[2],
    'JDK 23 ohne openjdk@21: Android-Studio-JBR',
  );
  t.eq(gradleJavaHome(v23, (_) => false), null, 'kein Kandidat: unverändert');
  t.eq(gradleJavaHome('openjdk version "21.0.5"', has), null, 'JDK 21 bleibt');
  t.eq(gradleJavaHome('openjdk version "17.0.9"', has), null, 'JDK 17 bleibt');
  t.eq(gradleJavaHome('', has), null, 'unbekannte Version: fail-open');
  t.eq(c.tests, 7, 'Testanzahl');
  t.eq(c.failures, 3, 'Fehler und Ausfälle');
}

/// Selbsttest von [clearReports].
void kotlinReportsClearChecks(SelfCheck t) {
  t.group('kotlin-unit (Berichte)');
  final d = Directory.systemTemp.createTempSync('reports');
  try {
    final dir = '${d.path}/r';
    Directory(dir).createSync();
    File('$dir/a.xml').writeAsStringSync('<testsuite tests="2">');
    t.eq(readReports(dir).length, 1, 'alter Bericht vorhanden');
    clearReports(dir);
    t.eq(readReports(dir), <String>[], 'nach dem Leeren keine Berichte');
    clearReports(dir);
  } finally {
    d.deleteSync(recursive: true);
  }
}
