// ARB-Fragmente (app/lib/l10n/src/<bereich>/<bereich>_<lang>.arb) zur
// Gesamt-ARB zusammenführen und `flutter gen-l10n` laufen lassen.
//   dart run tool/l10n_merge.dart                 erzeugt app_<lang>.arb und gen/
//   dart run tool/l10n_merge.dart --check         meldet Veraltetes/Doppeltes (Gate)
//   dart run tool/l10n_merge.dart --adopt [bereich]  übernimmt Schlüssel aus
//                                                 app_*.arb, die in keinem Fragment stehen
// Zuordnung Präfix → Bereich: tool/src/l10n_merge.dart (`prefixAreas`).
import 'dart:convert';
import 'dart:io';

import 'src/l10n_merge.dart';

final _src = Directory('app/lib/l10n/src');
final _gen = Directory('app/lib/l10n/gen');

File _arb(String lang) => File('app/lib/l10n/app_$lang.arb');

Fragments _load() {
  final fr = <String, Map<String, Map<String, Object?>>>{};
  if (!_src.existsSync()) return fr;
  for (final f in _src.listSync(recursive: true).whereType<File>()) {
    final m = RegExp(r'([a-z0-9]+)_(de|en|fr)\.arb$').firstMatch(f.path);
    if (m == null) continue;
    final map = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    (fr[m[1]!] ??= {})[m[2]!] = map;
  }
  return fr;
}

void _write(Fragments fr) {
  for (final area in fr.keys) {
    for (final lang in langs) {
      final entries = fr[area]![lang];
      if (entries == null || entries.isEmpty) continue;
      final f = File('${_src.path}/$area/${area}_$lang.arb');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(render(canonical(entries)));
    }
  }
}

Future<int> _genL10n({String? outDir}) async {
  final r = await Process.run('flutter', [
    'gen-l10n',
    if (outDir != null) ...['--output-dir', outDir],
  ], workingDirectory: 'app');
  if (r.exitCode != 0) stderr.write('${r.stdout}${r.stderr}');
  return r.exitCode;
}

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

Future<int> _run(List<String> args) async {
  final fr = _load();
  if (args.contains('--adopt')) {
    final i = args.indexOf('--adopt');
    final area = i + 1 < args.length ? args[i + 1] : null;
    var n = 0;
    for (final lang in langs) {
      if (!_arb(lang).existsSync()) continue;
      final arb = jsonDecode(_arb(lang).readAsStringSync());
      n += adopt(fr, lang, arb as Map<String, Object?>, area: area).length;
    }
    _write(fr);
    stdout.writeln('l10n_merge: $n Schlüssel in Fragmente übernommen');
    return 0;
  }
  if (args.contains('--check')) return _check(fr);
  final bad = problems(fr);
  if (bad.isNotEmpty) {
    stderr.writeln(bad.join('\n'));
    return 1;
  }
  for (final lang in langs) {
    _arb(lang).writeAsStringSync(render(mergeLang(fr, lang)));
  }
  return _genL10n();
}

Future<int> _check(Fragments fr) async {
  final bad = problems(fr);
  for (final lang in langs) {
    final want = render(mergeLang(fr, lang));
    if (!_arb(lang).existsSync() || _arb(lang).readAsStringSync() != want) {
      bad.add('app_$lang.arb ist veraltet (dart run tool/l10n_merge.dart)');
    }
  }
  if (bad.isEmpty) {
    // gen/ gegen eine frische Erzeugung prüfen (danach Zustand wiederherstellen,
    // gen-l10n ignoriert --output-dir, wenn l10n.yaml existiert).
    Map<String, String> snapshot() => {
      if (_gen.existsSync())
        for (final f in _gen.listSync(recursive: true).whereType<File>())
          f.path: f.readAsStringSync(),
    };
    final before = snapshot();
    final rc = await _genL10n();
    for (final f
        in _gen.existsSync()
            ? _gen.listSync(recursive: true).whereType<File>().toList()
            : <File>[]) {
      if (!before.containsKey(f.path)) {
        bad.add('${f.path} fehlt im Repo (dart run tool/l10n_merge.dart)');
        f.deleteSync();
      }
    }
    for (final e in before.entries) {
      final f = File(e.key);
      if (!f.existsSync() || f.readAsStringSync() != e.value) {
        bad.add('${e.key} ist veraltet (dart run tool/l10n_merge.dart)');
      }
      f.writeAsStringSync(e.value);
    }
    if (rc != 0) return rc;
  }
  if (bad.isEmpty) {
    stdout.writeln('l10n: Fragmente und Erzeugtes aktuell');
    return 0;
  }
  stderr.writeln(bad.take(40).join('\n'));
  return 1;
}
