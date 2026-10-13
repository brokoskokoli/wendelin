// Selbsttests von tool/src/channel_check.dart mit kleinen Beispieldateien.
import 'channel_check.dart';
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
        _has(r, 'Argument "who" von "ping" kommt im Kotlin-Code nicht vor'),
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
  r = _run(manifest: '{');
  t.isTrue(_has(r, 'kein gültiges JSON'), 'kaputtes Manifest');
}
