// Längen von Funktionen und Klassen in Dart- und Kotlin-Quelltext,
// gemessen mit einer Klammer-Heuristik (schnell, ohne package:analyzer):
//
// 1. Kommentare und Zeichenketten (auch `${…}`-Interpolation, rohe und
//    dreifache Strings) werden durch Leerzeichen ersetzt, Zeilenumbrüche
//    bleiben erhalten.
// 2. Eine `{` auf oberster Ebene oder direkt im Rumpf einer Klasse (nicht
//    innerhalb von Klammern) ist eine Klasse, wenn vor der ersten `(` des
//    Kopfs `class`, `mixin`, `enum`, `extension`, `object` oder `interface`
//    steht, und eine Funktion, wenn der Kopf auf `)` (ggf. mit `async`,
//    `async*`, `sync*` oder Kotlin-Rückgabetyp) oder auf `get <name>` endet
//    bzw. in Kotlin `fun` enthält. Alles andere ist ein Block.
// 3. Pfeil-Funktionen (`=> …;`) auf diesen Ebenen zählen bis zum `;`.
//
// Geschachtelte Closures zählen zur umgebenden Funktion. Die Länge reicht
// von der Zeile des Namens bis zur schließenden Klammer bzw. zum `;`.

/// Eine gemessene Funktion oder Klasse.
final class Measure {
  /// Erstellt einen Messwert.
  const Measure(this.name, this.line, this.lines);

  /// Name, bei Methoden `Klasse.methode`.
  final String name;

  /// Zeile des Namens (1-basiert).
  final int line;

  /// Länge in Zeilen.
  final int lines;

  @override
  String toString() => '$name@$line:$lines';
}

/// Funktionen und Klassen einer Datei.
final class Structure {
  /// Erstellt das Ergebnis.
  const Structure(this.functions, this.classes);

  /// Funktionen und Methoden (ohne geschachtelte Closures).
  final List<Measure> functions;

  /// Klassen, Mixins, Enums, Extensions, Kotlin-Objekte.
  final List<Measure> classes;
}

/// Ersetzt Kommentare und Zeichenketten durch Leerzeichen.
String blankNonCode(String src, {bool kotlin = false}) =>
    _Blanker(src, kotlin).run();

final class _Blanker {
  _Blanker(this.s, this.kotlin) : out = List.of(s.codeUnits);
  final String s;
  final bool kotlin;
  final List<int> out;

  static const _nl = 10, _space = 32;

  String run() {
    _code(0, false);
    return String.fromCharCodes(out);
  }

  void _blank(int from, int to) {
    for (var k = from; k < to && k < s.length; k++) {
      if (out[k] != _nl) out[k] = _space;
    }
  }

  bool _at(int i, String t) => s.startsWith(t, i);

  /// Liest Code ab [i]. Mit [inInterp] endet er an der schließenden `}`
  /// einer Interpolation und liefert den Index danach.
  int _code(int i, bool inInterp) {
    var depth = 0;
    while (i < s.length) {
      final c = s[i];
      if (_at(i, '//')) {
        final end = s.indexOf('\n', i);
        final j = end < 0 ? s.length : end;
        _blank(i, j);
        i = j;
      } else if (_at(i, '/*')) {
        final j = _blockComment(i);
        _blank(i, j);
        i = j;
      } else if (c == '"' || (c == "'" && !kotlin)) {
        final raw = !kotlin && i > 0 && s[i - 1] == 'r' && !_ident(i - 2);
        final j = _string(i, raw);
        _blank(i, j);
        i = j;
      } else if (c == "'" && kotlin) {
        final j = _charLiteral(i);
        _blank(i, j);
        i = j;
      } else {
        if (c == '{') depth++;
        if (c == '}') {
          if (inInterp && depth == 0) return i + 1;
          depth--;
        }
        i++;
      }
    }
    return i;
  }

  bool _ident(int i) {
    if (i < 0) return false;
    final c = s.codeUnitAt(i);
    return (c >= 48 && c <= 57) || // 0-9
        (c >= 65 && c <= 90) || // A-Z
        (c >= 97 && c <= 122) || // a-z
        c == 95 || // _
        c == 36; // $
  }

  int _blockComment(int i) {
    var depth = 0;
    while (i < s.length) {
      if (_at(i, '/*')) {
        depth++;
        i += 2;
      } else if (_at(i, '*/')) {
        depth--;
        i += 2;
        if (depth == 0) return i;
      } else {
        i++;
      }
    }
    return i;
  }

  int _charLiteral(int i) {
    var j = i + 1;
    while (j < s.length && s[j] != "'" && s[j] != '\n') {
      j += s[j] == r'\' ? 2 : 1;
    }
    return j + 1;
  }

  /// Liest eine Zeichenkette ab dem Anführungszeichen bei [i].
  int _string(int i, bool raw) {
    final q = s[i];
    final triple = _at(i, q * 3);
    final close = triple ? q * 3 : q;
    var j = i + close.length;
    // Kotlin: in """…""" gibt es keine Escapes, wohl aber `${…}`.
    final escapes = !raw && !(kotlin && triple);
    while (j < s.length) {
      if (_at(j, close)) return j + close.length;
      final c = s[j];
      if (!triple && c == '\n') return j; // kaputte Zeile: hier beenden
      if (escapes && c == r'\') {
        j += 2;
      } else if (!raw && _at(j, r'${')) {
        j = _code(j + 2, true);
      } else {
        j++;
      }
    }
    return j;
  }
}

final _classKeyword = RegExp(
  r'\b(class|mixin|enum|extension|object|interface)\b',
);
final _classNames = [
  RegExp(r'\bclass\s+(\w+)'),
  RegExp(r'\bmixin\s+(\w+)'),
  RegExp(r'\benum\s+(\w+)'),
  RegExp(r'\bextension\s+type\s+(\w+)'),
  RegExp(r'\bextension\s+(\w+)'),
  RegExp(r'\bobject\s+(\w+)'),
  RegExp(r'\binterface\s+(\w+)'),
];
final _dartFnEnd = RegExp(r'\)\s*(async\*?|sync\*)?\s*$');
final _getter = RegExp(r'\bget\s+(\w+)\s*$');

/// `( ) [ ] = ; { }` – nur diese Zeichen ändern den Zustand.
const _structural = {40, 41, 91, 93, 61, 59, 123, 125};
final _annotation = RegExp(r'@[\w.]+(\s*\([^()]*\))?');
const _control = {'if', 'for', 'while', 'switch', 'catch', 'when', 'return'};
final _nameBeforeParen = RegExp(r'([\w$]+)\s*\($');
final _firstCall = RegExp(r'([\w$]+)\s*\(');
final _typeArgs = RegExp(r'<[^<>]*>');

/// Entfernt Typargumente (`Future<List<T>>` → `Future`), damit der Name
/// vor der ersten `(` gefunden wird.
String _withoutTypeArgs(String head) {
  var h = head;
  while (true) {
    final next = h.replaceAll(_typeArgs, '');
    if (next == h) return h;
    h = next;
  }
}

final class _Frame {
  _Frame(this.kind, this.name, this.line, this.parens);
  final String kind; // top, class, fn, block
  final String name;
  final int line;
  final int parens;
  ({String name, int line})? arrow;
}

/// Misst Funktionen und Klassen in [src] (Dart oder Kotlin).
Structure measure(String src, {bool kotlin = false}) =>
    _Scanner(blankNonCode(src, kotlin: kotlin), kotlin).run();

final class _Scanner {
  _Scanner(this.t, this.kotlin)
    : breaks = [for (final m in '\n'.allMatches(t)) m.start];
  final String t;
  final bool kotlin;
  final List<int> breaks;
  final fns = <Measure>[], classes = <Measure>[];
  final stack = [_Frame('top', '', 0, 0)];
  var parens = 0, headStart = 0;

  Structure run() {
    for (var i = 0; i < t.length; i++) {
      final u = t.codeUnitAt(i);
      if (!_structural.contains(u)) continue;
      final top = stack.last;
      final atMember =
          (top.kind == 'top' || top.kind == 'class') && parens == top.parens;
      switch (t[i]) {
        case '(' || '[':
          parens++;
        case ')' || ']':
          parens--;
        case '=' when atMember && i + 1 < t.length && t[i + 1] == '>':
          if (top.arrow == null) _arrow(top, i);
        case ';':
          final a = top.arrow;
          if (atMember && a != null) {
            fns.add(Measure(a.name, a.line, lineAt(i) - a.line + 1));
            top.arrow = null;
          }
          if (parens == top.parens) headStart = i + 1;
        case '{':
          _open(top, i, atMember: atMember && top.arrow == null);
        case '}':
          if (stack.length > 1) {
            final f = stack.removeLast();
            final m = Measure(f.name, f.line, lineAt(i) - f.line + 1);
            if (f.kind == 'fn') fns.add(m);
            if (f.kind == 'class') classes.add(m);
          }
          if (parens == stack.last.parens) headStart = i + 1;
      }
    }
    return Structure(fns, classes);
  }

  /// Zeile (1-basiert) des Zeichens bei [index].
  int lineAt(int index) {
    var lo = 0, hi = breaks.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (breaks[mid] < index) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo + 1;
  }

  String qualify(String n) {
    final cls = stack.lastWhere(
      (f) => f.kind == 'class',
      orElse: () => stack.first,
    );
    return cls.kind == 'class' ? '${cls.name}.$n' : n;
  }

  /// Zeile von [name] im Kopf ab [headStart], sonst die von [fallback].
  int nameLine(String head, String name, int fallback) {
    final at = head.indexOf(RegExp('\\b${RegExp.escape(name)}\\b'));
    return lineAt(at < 0 ? fallback : headStart + at);
  }

  void _arrow(_Frame top, int i) {
    final head = t.substring(headStart, i);
    final clean = _withoutTypeArgs(head.replaceAll(_annotation, ' '));
    final n =
        _firstCall.firstMatch(clean)?.group(1) ??
        _getter.firstMatch(clean.trim())?.group(1);
    if (n != null) top.arrow = (name: qualify(n), line: nameLine(head, n, i));
  }

  void _open(_Frame top, int i, {required bool atMember}) {
    var kind = 'block', name = '';
    if (atMember) {
      final head = t.substring(headStart, i);
      final trimmed = head.replaceAll(_annotation, ' ').trim();
      final paren = trimmed.indexOf('(');
      final beforeParen = paren < 0 ? trimmed : trimmed.substring(0, paren);
      if (_classKeyword.hasMatch(beforeParen)) {
        kind = 'class';
        name =
            _classNames
                .map((r) => r.firstMatch(beforeParen)?.group(1))
                .nonNulls
                .firstOrNull ??
            (beforeParen.contains('object') ? 'object' : 'extension');
      } else if ((kotlin && RegExp(r'\bfun\b').hasMatch(trimmed)) ||
          (!kotlin && _dartFnEnd.hasMatch(trimmed)) ||
          _getter.hasMatch(trimmed)) {
        name = _getter.firstMatch(trimmed)?.group(1) ?? _fnName(trimmed) ?? '?';
        if (!_control.contains(name)) kind = 'fn';
      }
      if (kind != 'block') {
        final line = nameLine(head, name, i);
        if (kind == 'fn') name = qualify(name);
        stack.add(_Frame(kind, name, line, parens));
        headStart = i + 1;
        return;
      }
    }
    stack.add(_Frame('block', '', 0, parens));
    // `{` in Klammern (benannte Parameter, Map-Literale in Argumenten)
    // beendet keinen Kopf.
    if (parens == top.parens) headStart = i + 1;
  }
}

/// Name einer Funktion aus ihrem Kopf: Bezeichner vor der ersten `(` auf
/// oberster Klammerebene.
String? _fnName(String head) {
  if (RegExp(r'\boperator\b').hasMatch(head)) return 'operator';
  final h = _withoutTypeArgs(head);
  final paren = h.indexOf('(');
  if (paren < 0) return null;
  return _nameBeforeParen.firstMatch(h.substring(0, paren + 1))?.group(1);
}
