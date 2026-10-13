// Prüfung der Plattformkanäle (app/channels.json) gegen Dart- und Kotlin-
// Quelltext per Textanalyse. Reine Logik ohne Dateizugriff, damit die
// Selbsttests sie mit kleinen Beispieldateien füttern können.
import 'dart:convert';

/// Liefert den Text einer Datei oder `null`, wenn sie fehlt.
typedef ReadFile = String? Function(String path);

/// Ergebnis der Prüfung.
final class ChannelReport {
  /// Fehler im Format `datei:zeile: text`.
  final errors = <String>[];

  /// Anzahl geprüfter Kanäle.
  int channels = 0;

  /// Anzahl geprüfter Methoden (beide Richtungen).
  int methods = 0;
}

/// Prüft das Manifest [manifestText] (Pfad [manifestPath], für Meldungen)
/// in beide Richtungen. [dartFiles] und [kotlinFiles] sind alle
/// Produktivdateien, in denen unbekannte Kanalnamen gesucht werden.
ChannelReport checkChannels({
  required String manifestText,
  required String manifestPath,
  required ReadFile read,
  required List<String> dartFiles,
  required List<String> kotlinFiles,
}) {
  final r = ChannelReport();
  final Object? json;
  try {
    json = jsonDecode(manifestText);
  } on FormatException catch (e) {
    r.errors.add('$manifestPath:1: kein gültiges JSON (${e.message})');
    return r;
  }
  final root = json is Map<String, Object?> ? json : const <String, Object?>{};
  final namesPath = root['dartNames'];
  final channels = root['channels'];
  if (namesPath is! String || channels is! Map) {
    r.errors.add('$manifestPath:1: "dartNames" und "channels" fehlen');
    return r;
  }
  final names = _load(namesPath, read);
  if (names == null) {
    r.errors.add('$manifestPath:1: Datei $namesPath fehlt');
  }
  final cache = <String, _Src?>{};
  _Src? src(String p) => cache.putIfAbsent(p, () => _load(p, read));

  int mline(String needle) {
    final i = manifestText.indexOf('"$needle"');
    return i < 0 ? 1 : '\n'.allMatches(manifestText.substring(0, i)).length + 1;
  }

  for (final e in channels.entries) {
    final name = '${e.key}';
    final c = e.value is Map ? e.value as Map : const <String, Object?>{};
    r.channels++;
    final dart = <_Src>[], kotlin = <_Src>[];
    for (final (key, into) in [('dart', dart), ('kotlin', kotlin)]) {
      for (final p in (c[key] as List?) ?? const []) {
        final s = src('$p');
        if (s == null) {
          r.errors.add('$manifestPath:${mline(name)}: $name: Datei $p fehlt');
        } else {
          into.add(s);
        }
      }
    }
    final toKotlin = _methods(c['toKotlin']);
    final toDart = _methods(c['toDart']);
    r.methods += toKotlin.length + toDart.length;
    final ctx = _Ctx(r, manifestPath, mline, name);

    if (names != null && !names.text.contains("'$name'")) {
      ctx.err(manifestPath, mline(name), 'Kanalname fehlt in $namesPath');
    }
    if (!kotlin.any((k) => k.text.contains('"$name"'))) {
      ctx.err(manifestPath, mline(name), 'Kanalname fehlt im Kotlin-Code');
    }

    final dartCalls = [for (final s in dart) ..._dartCalls(s)];
    final dartHandlers = [for (final s in dart) ..._dartHandlers(s)];
    final ktHandlers = [for (final s in kotlin) ..._ktHandlers(s)];
    final ktCalls = [for (final s in kotlin) ..._ktCalls(s)];

    _direction(
      ctx,
      'Dart → Kotlin',
      toKotlin,
      senders: dartCalls,
      receivers: ktHandlers,
      senderSide: 'Dart',
      receiverSide: 'Kotlin',
    );
    _direction(
      ctx,
      'Kotlin → Dart',
      toDart,
      senders: ktCalls,
      receivers: dartHandlers,
      senderSide: 'Kotlin',
      receiverSide: 'Dart',
    );
    _argKeys(ctx, toKotlin, toDart, dart, kotlin);
  }

  final known = {for (final k in channels.keys) '$k'};
  for (final (files, re) in [
    (dartFiles, RegExp(r"'(app\.wendelin/\w+)'")),
    (kotlinFiles, RegExp(r'"(app\.wendelin/\w+)"')),
  ]) {
    for (final p in files) {
      final s = src(p);
      if (s == null) continue;
      for (final m in re.allMatches(s.code)) {
        if (!known.contains(m[1])) {
          r.errors.add(
            '$p:${s.line(m.start)}: Kanal ${m[1]} fehlt im Manifest '
            '($manifestPath)',
          );
        }
      }
    }
  }
  r.errors.sort();
  return r;
}

final class _Ctx {
  _Ctx(this.r, this.manifest, this.mline, this.channel);
  final ChannelReport r;
  final String manifest;
  final int Function(String) mline;
  final String channel;

  void err(String file, int line, String msg) =>
      r.errors.add('$file:$line: $channel: $msg');

  void at(String at, String msg) => r.errors.add('$at: $channel: $msg');
}

final class _Method {
  _Method(this.args, this.returns);
  final Set<String> args;
  final String? returns;
}

Map<String, _Method> _methods(Object? raw) => {
  if (raw is Map)
    for (final e in raw.entries)
      '${e.key}': _Method({
        if (e.value is Map && (e.value as Map)['args'] is List)
          for (final a in (e.value as Map)['args'] as List) '$a',
      }, e.value is Map ? (e.value as Map)['returns'] as String? : null),
};

/// Eine Aufrufstelle oder ein Handler im Quelltext.
final class _Site {
  _Site(this.src, this.offset, this.method, {this.keys, this.returns});
  final _Src src;
  final int offset;
  final String method;

  /// Schlüssel eines direkt angegebenen Argument-Maps, sonst `null`.
  final Set<String>? keys;

  /// Rückgabeart aus dem Typargument des Aufrufs, sonst `null`.
  final String? returns;

  String get at => '${src.path}:${src.line(offset)}';
}

void _direction(
  _Ctx ctx,
  String title,
  Map<String, _Method> manifest, {
  required List<_Site> senders,
  required List<_Site> receivers,
  required String senderSide,
  required String receiverSide,
}) {
  final mf = ctx.manifest;
  for (final (sites, side) in [
    (senders, senderSide),
    (receivers, receiverSide),
  ]) {
    for (final s in sites) {
      if (!manifest.containsKey(s.method)) {
        ctx.r.errors.add(
          '${s.at}: ${ctx.channel}: Methode "${s.method}" ($title, nur im '
          '$side-Code) fehlt im Manifest $mf',
        );
      }
    }
  }
  for (final m in manifest.keys) {
    final line = ctx.mline(m);
    if (!senders.any((s) => s.method == m)) {
      ctx.err(
        mf,
        line,
        'Methode "$m" ($title): kein Aufruf im $senderSide-Code',
      );
    }
    if (!receivers.any((s) => s.method == m)) {
      ctx.err(
        mf,
        line,
        'Methode "$m" ($title): kein Handler im $receiverSide-Code',
      );
    }
  }
  for (final s in senders) {
    final mm = manifest[s.method];
    if (mm == null) continue;
    final keys = s.keys;
    if (keys != null) {
      for (final k in keys.difference(mm.args)) {
        ctx.at(s.at, 'Argument "$k" von "${s.method}" fehlt im Manifest');
      }
    }
    final ret = s.returns;
    if (ret != null && mm.returns != null && ret != mm.returns) {
      ctx.at(
        s.at,
        'Rückgabe von "${s.method}" ist $ret, im Manifest ${mm.returns}',
      );
    }
  }
}

void _argKeys(
  _Ctx ctx,
  Map<String, _Method> toKotlin,
  Map<String, _Method> toDart,
  List<_Src> dart,
  List<_Src> kotlin,
) {
  final all = {
    for (final m in [...toKotlin.values, ...toDart.values]) ...m.args,
  };
  for (final entry in [...toKotlin.entries, ...toDart.entries]) {
    for (final a in entry.value.args) {
      if (!dart.any((s) => RegExp('[\'"]$a[\'"]').hasMatch(s.code))) {
        ctx.err(
          ctx.manifest,
          ctx.mline(entry.key),
          'Argument "$a" von "${entry.key}" kommt im Dart-Code nicht vor',
        );
      }
      if (!kotlin.any((s) => s.code.contains('"$a"'))) {
        ctx.err(
          ctx.manifest,
          ctx.mline(entry.key),
          'Argument "$a" von "${entry.key}" kommt im Kotlin-Code nicht vor',
        );
      }
    }
  }
  // `call.argument<T>("k")` and the typed accessors of ChannelArgs.
  final read = RegExp(
    r'\b(?:argument|hasArgument|args\.(?:string|requireString|requireLong|'
    r'requireBytes|isTrue|stringList))\s*(?:<[^()]*>)?\s*\(\s*"(\w+)"',
  );
  for (final s in kotlin) {
    for (final m in read.allMatches(s.code)) {
      if (!all.contains(m[1])) {
        ctx.err(
          s.path,
          s.line(m.start),
          'Argument "${m[1]}" wird gelesen, steht aber nicht im Manifest',
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Quelltext lesen

final class _Src {
  _Src(this.path, String text) : code = _blankComments(text) {
    var i = -1;
    while ((i = code.indexOf('\n', i + 1)) >= 0) {
      _starts.add(i + 1);
    }
  }

  final String path;

  /// Text ohne Kommentare (gleiche Offsets wie das Original).
  final String code;
  final _starts = <int>[0];

  String get text => code;

  int line(int offset) {
    var lo = 0, hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo + 1;
  }

  String lineText(int n) {
    final from = _starts[n - 1];
    final to = n < _starts.length ? _starts[n] - 1 : code.length;
    return code.substring(from, to);
  }
}

_Src? _load(String path, ReadFile read) {
  final t = read(path);
  return t == null ? null : _Src(path, t);
}

/// Ersetzt Kommentare durch Leerzeichen, Zeichenketten bleiben.
String _blankComments(String t) {
  final out = StringBuffer();
  var i = 0;
  while (i < t.length) {
    final c = t[i];
    final next = i + 1 < t.length ? t[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < t.length && t[i] != '\n') {
        out.write(' ');
        i++;
      }
    } else if (c == '/' && next == '*') {
      while (i < t.length &&
          !(t[i] == '*' && i + 1 < t.length && t[i + 1] == '/')) {
        out.write(t[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < t.length) {
        out.write('  ');
        i += 2;
      }
    } else if (c == "'" || c == '"') {
      final end = _stringEnd(t, i);
      out.write(t.substring(i, end));
      i = end;
    } else {
      out.write(c);
      i++;
    }
  }
  return out.toString();
}

/// Index hinter dem Ende der Zeichenkette, die bei [start] beginnt.
int _stringEnd(String t, int start) {
  final q = t[start];
  var i = start + 1;
  while (i < t.length && t[i] != q && t[i] != '\n') {
    i += t[i] == r'\' ? 2 : 1;
  }
  return i < t.length && t[i] == q ? i + 1 : i;
}

int _indent(String line) => line.length - line.trimLeft().length;

/// Ob die nächste weniger eingerückte Zeile vor [line] zu [header] passt.
bool _underHeader(_Src s, int line, RegExp header) {
  final ind = _indent(s.lineText(line));
  for (var j = line - 1; j >= 1; j--) {
    final l = s.lineText(j);
    if (l.trim().isEmpty) continue;
    if (_indent(l) < ind) return header.hasMatch(l);
  }
  return false;
}

// ---------------------------------------------------------------------------
// Dart

const _generic = r'(?:<(?:[^<>]|<(?:[^<>]|<[^<>]*>)*>)*>)?';
final _dartCall = RegExp(
  r'\b(invokeMethod|invokeMapMethod|invokeListMethod|_call|_invoke|_list)\s*'
  '($_generic)'
  r"\s*\(\s*'(\w+)'",
);

List<_Site> _dartCalls(_Src s) => [
  for (final m in _dartCall.allMatches(s.code))
    _Site(
      s,
      m.start,
      m[3]!,
      keys: _dartMapKeys(s.code, m.end),
      returns: _dartReturn(m[1]!, m[2]!),
    ),
];

String? _dartReturn(String caller, String generic) {
  if (caller == 'invokeMapMethod') return 'map';
  if (caller == 'invokeListMethod') return 'list';
  if (generic.isEmpty) return null;
  final t = generic.substring(1, generic.length - 1).trim();
  if (t.startsWith('Object') || t.startsWith('dynamic')) return null;
  if (t.startsWith('void')) return 'none';
  if (t.startsWith('List')) return 'list';
  if (t.startsWith('Map')) return 'map';
  return 'value';
}

final _dartCase = RegExp(r"case\s+'(\w+)'\s*:");
final _dartSwitch = RegExp(r'switch\s*\(\s*call\.method\s*\)');
final _dartEq = RegExp(r"call\.method\s*==\s*'(\w+)'");

List<_Site> _dartHandlers(_Src s) => [
  for (final m in _dartCase.allMatches(s.code))
    if (_underHeader(s, s.line(m.start), _dartSwitch)) _Site(s, m.start, m[1]!),
  for (final m in _dartEq.allMatches(s.code)) _Site(s, m.start, m[1]!),
];

// ---------------------------------------------------------------------------
// Kotlin

final _ktArm = RegExp(r'"(\w+)"\s*->');
final _ktWhen = RegExp(r'when\s*\(\s*(?:call\.)?method\s*\)');
final _ktEq = RegExp(r'call\.method\s*[=!]=\s*"(\w+)"');
final _ktCall = RegExp(
  r'\b(?:invokeMethod|send)\s*\(\s*"(\w+)"\s*(?:,\s*(mapOf\())?',
);

List<_Site> _ktHandlers(_Src s) => [
  for (final m in _ktArm.allMatches(s.code))
    if (_underHeader(s, s.line(m.start), _ktWhen)) _Site(s, m.start, m[1]!),
  for (final m in _ktEq.allMatches(s.code)) _Site(s, m.start, m[1]!),
];

List<_Site> _ktCalls(_Src s) => [
  for (final m in _ktCall.allMatches(s.code))
    _Site(
      s,
      m.start,
      m[1]!,
      keys: m[2] == null ? null : _ktMapKeys(s.code, m.end - 1),
    ),
];

/// Schlüssel des Map-Literals `, {'a': 1}` (auch `, const {}`) hinter [from],
/// `null`, wenn dort kein Literal steht.
Set<String>? _dartMapKeys(String t, int from) {
  final m = RegExp(r'\s*,\s*(?:const\s+)?\{').matchAsPrefix(t, from);
  return m == null ? null : _topKeys(t, m.end - 1, '{', '}', ':');
}

/// Schlüssel von `mapOf("a" to 1)`; [open] ist der Index der `(`.
Set<String> _ktMapKeys(String t, int open) => _topKeys(t, open, '(', ')', 'to');

/// Zeichenketten auf der obersten Ebene hinter [open], auf die [sep] folgt.
Set<String> _topKeys(String t, int open, String o, String c, String sep) {
  final keys = <String>{};
  var depth = 0;
  var i = open;
  while (i < t.length) {
    final ch = t[i];
    if (ch == "'" || ch == '"') {
      final end = _stringEnd(t, i);
      if (depth == 1) {
        final key = t.substring(i + 1, end - 1);
        if (RegExp('\\s*${RegExp.escape(sep)}(?!\\w)').matchAsPrefix(t, end) !=
            null) {
          keys.add(key);
        }
      }
      i = end;
      continue;
    }
    if (ch == '(' || ch == '{' || ch == '[') depth++;
    if (ch == ')' || ch == '}' || ch == ']') {
      depth--;
      if (depth == 0) break;
    }
    i++;
  }
  return keys;
}
