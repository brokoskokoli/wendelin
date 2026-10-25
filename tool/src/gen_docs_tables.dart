// Erzeugte Tabellen für `tool/gen_docs.dart`: Ports (aus dem Dart-Code) und
// Plattformkanäle (aus `app/channels.json`). Reine Funktionen auf Text, damit
// die Selbsttests sie mit kleinen Beispielen füttern können.
import 'dart:convert';

/// Namensendungen, an denen ein Port erkannt wird (`abstract interface class`).
final _portName = RegExp(r'(Port|Api|Secrets|Store)$');

final _interfaceDecl = RegExp(
  r'^abstract interface class (\w+)',
  multiLine: true,
);

final _classDecl = RegExp(
  r'^(?:(?:abstract|base|final|sealed|interface|mixin)\s+)*class\s+(\w+)([^{;=]*)\{',
  multiLine: true,
);

/// Ein Implementierer eines Ports.
typedef Implementer = ({String name, String path, bool fake});

/// Ein Port mit Fundort und Implementierern.
typedef PortRow = ({String name, String path, List<Implementer> impls});

/// Kurzname des Pakets: `packages/<pkg>/…` → `<pkg>`, `app/…` → `app`.
String portPackage(String path) {
  final m = RegExp(r'^packages/([^/]+)/').firstMatch(path);
  if (m != null) return m[1]!;
  return path.split('/').first;
}

/// Ob eine Datei oder Klasse ein Fake/Test-Double ist (eigene Spalte).
bool isFake(String className, String path) =>
    className.startsWith('Fake') ||
    className.startsWith('InMemory') ||
    className.startsWith('Recording') ||
    RegExp(r'(^|/)(fakes?|testing)(\.dart|/)|(^|/)fake_[^/]*$|_fakes?\.dart$')
        .hasMatch(path);

/// Klassen, die in [header] (der Text zwischen Klassenname und `{`) erben
/// oder implementieren.
Set<String> supertypes(String header) {
  var h = header;
  // Generics samt Verschachtelung entfernen: `Foo<T extends X<Y>>`.
  for (var prev = ''; prev != h;) {
    prev = h;
    h = h.replaceAll(RegExp(r'<[^<>]*>'), '');
  }
  final out = <String>{};
  final m = RegExp(
    r'\b(?:extends|implements|with)\b(.*)$',
    dotAll: true,
  ).firstMatch(h);
  if (m == null) return out;
  for (final w in RegExp(r'\b([A-Z]\w*)\b').allMatches(m[1]!)) {
    out.add(w[1]!);
  }
  return out;
}

/// Alle Ports und ihre Implementierer aus [sources] (Pfad → Text).
List<PortRow> scanPorts(Map<String, String> sources) {
  final ports = <String, String>{}; // Name → Pfad
  for (final e in sources.entries) {
    for (final m in _interfaceDecl.allMatches(e.value)) {
      final n = m[1]!;
      if (_portName.hasMatch(n) && !n.startsWith('_'))
        ports.putIfAbsent(n, () => e.key);
    }
  }
  final impls = {for (final n in ports.keys) n: <Implementer>[]};
  for (final e in sources.entries) {
    for (final m in _classDecl.allMatches(e.value)) {
      final cls = m[1]!;
      if (cls.startsWith('_')) continue;
      for (final s in supertypes(m[2]!)) {
        if (s != cls && impls.containsKey(s)) {
          impls[s]!.add((name: cls, path: e.key, fake: isFake(cls, e.key)));
        }
      }
    }
  }
  final rows =
      [
        for (final n in ports.keys)
          (
            name: n,
            path: ports[n]!,
            impls: impls[n]!..sort((a, b) => a.name.compareTo(b.name)),
          ),
      ]..sort((a, b) {
        final p = portPackage(a.path).compareTo(portPackage(b.path));
        return p != 0 ? p : a.name.compareTo(b.name);
      });
  return rows;
}

/// Markdown der Ports-Tabelle (ohne Kopfkommentar).
String portsTable(List<PortRow> rows) {
  final b = StringBuffer()
    ..writeln('| Port | Paket | Datei | Implementierer | Fakes |')
    ..writeln('| --- | --- | --- | --- | --- |');
  String cell(List<Implementer> l) =>
      l.isEmpty ? '–' : l.map((i) => '`${i.name}` (`${i.path}`)').join('<br>');
  for (final r in rows) {
    b.writeln(
      '| `${r.name}` | `${portPackage(r.path)}` | `${r.path}` | '
      '${cell([for (final i in r.impls)
        if (!i.fake) i])} | '
      '${cell([for (final i in r.impls)
        if (i.fake) i])} |',
    );
  }
  return b.toString();
}

/// Markdown der Kanal-Tabelle aus dem Inhalt von `app/channels.json`.
String channelsTable(String manifestText) {
  final json = jsonDecode(manifestText) as Map<String, Object?>;
  final channels = (json['channels'] as Map<String, Object?>?) ?? const {};
  final b = StringBuffer()
    ..writeln(
      '| Kanal (`app.wendelin/…` ohne Präfix) | Dart | Kotlin | Dart → Kotlin | Kotlin → Dart |',
    )
    ..writeln('| --- | --- | --- | --- | --- |');
  String files(Object? l) =>
      [for (final f in (l as List<Object?>? ?? const [])) '`$f`'].join('<br>');
  String methods(Object? m) {
    final map = (m as Map<String, Object?>? ?? const {});
    if (map.isEmpty) return '–';
    return [
      for (final e in map.entries)
        '`${e.key}(${(((e.value as Map<String, Object?>)['args'] as List<Object?>?) ?? const []).join(', ')})`',
    ].join('<br>');
  }

  for (final e in channels.entries) {
    final c = e.value as Map<String, Object?>;
    b.writeln(
      '| `${e.key.replaceFirst('app.wendelin/', '')}` | ${files(c['dart'])} | ${files(c['kotlin'])} | '
      '${methods(c['toKotlin'])} | ${methods(c['toDart'])} |',
    );
  }
  return b.toString();
}
