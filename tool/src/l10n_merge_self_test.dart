// Selbsttests von tool/l10n_merge.dart (Kern in src/l10n_merge.dart und CLI
// in einem temporären Projekt).
import 'dart:convert';
import 'dart:io';

import 'l10n_merge.dart';
import 'self_check.dart';

void l10nMergeChecks(SelfCheck t) {
  t.group('l10n_merge');
  t.eq(areaFor('attGpuFailedText'), 'attest', 'Präfix att');
  t.eq(areaFor('@spotifyTitle'), 'spotify', 'Metadaten folgen dem Schlüssel');
  t.eq(areaFor('cancel'), 'common', 'unbekanntes Präfix → common');

  final fr = <String, Map<String, Map<String, Object?>>>{
    'b': {
      for (final l in langs)
        l: {
          'bZ': 'z',
          '@bZ': {'description': 'd'},
          'bA': 'a',
        },
    },
    'a': {
      for (final l in langs) l: {'aX': 'x'},
    },
  };
  final de = mergeLang(fr, 'de');
  t.eq(de.keys.toList(), [
    '@@locale',
    'aX',
    'bA',
    'bZ',
    '@bZ',
  ], 'Bereiche und Schlüssel alphabetisch, @key hinter key');
  t.eq(problems(fr), <String>[], 'konsistente Fragmente ohne Befund');

  // Mutation: doppelter Schlüssel in zwei Bereichen.
  final dup = {
    for (final e in fr.entries)
      e.key: {
        for (final l in e.value.entries) l.key: {...l.value},
      },
  };
  dup['a']!['de']!['bA'] = 'doppelt';
  t.isTrue(
    problems(dup).any((p) => p.contains('doppelter Schlüssel bA')),
    'doppelter Schlüssel über Fragmente wird gemeldet',
  );
  // Mutation: Schlüssel fehlt in fr.
  final miss = {
    for (final e in fr.entries)
      e.key: {
        for (final l in e.value.entries) l.key: {...l.value},
      },
  };
  miss['a']!['fr']!.remove('aX');
  t.isTrue(
    problems(miss).contains('Schlüssel aX fehlt in fr'),
    'unterschiedliche Schlüsselmengen werden gemeldet',
  );

  // adopt: nur unbekannte Schlüssel, Bereich per Präfix oder erzwungen.
  final ad = {
    'a': {
      'de': <String, Object?>{'aX': 'x'},
    },
  };
  final taken = adopt(ad, 'de', {
    '@@locale': 'de',
    'aX': 'x',
    'weatherNew': 'w',
    '@weatherNew': {'description': 'd'},
  });
  t.eq(taken, {'weatherNew'}, 'adopt übernimmt nur Neues');
  t.eq(ad['weather']!['de']!.keys.toList(), [
    'weatherNew',
    '@weatherNew',
  ], 'adopt in Präfix-Bereich');

  _cli(t);
}

/// CLI im temporären Projekt: --check ist rot bei veralteter Gesamt-ARB und
/// bei doppelten Schlüsseln (bricht vor `flutter gen-l10n` ab).
void _cli(SelfCheck t) {
  final tmp = Directory.systemTemp.createTempSync('l10n_merge_');
  try {
    final script = File('tool/l10n_merge.dart').absolute.path;
    void write(String p, Object? json) {
      final f = File('${tmp.path}/$p')..parent.createSync(recursive: true);
      f.writeAsStringSync('${jsonEncode(json)}\n');
    }

    ProcessResult run(List<String> a) => Process.runSync('dart', [
      'run',
      script,
      ...a,
    ], workingDirectory: tmp.path);

    for (final l in langs) {
      write('app/lib/l10n/src/weather/weather_$l.arb', {'weatherA': l});
      write('app/lib/l10n/app_$l.arb', {'@@locale': l, 'weatherA': l});
    }
    var r = run(['--check']);
    t.eq(r.exitCode, 1, '--check: Gesamt-ARB nicht kanonisch/veraltet → rot');
    t.isTrue('${r.stderr}'.contains('veraltet'), '--check nennt "veraltet"');

    for (final l in langs) {
      write('app/lib/l10n/src/common/common_$l.arb', {'weatherA': l});
    }
    r = run(['--check']);
    t.eq(r.exitCode, 1, '--check: doppelter Schlüssel → rot');
    t.isTrue(
      '${r.stderr}'.contains('doppelter Schlüssel weatherA'),
      '--check nennt den Schlüssel',
    );

    // adopt legt Fragmente an, die Schlüsselmenge bleibt konsistent.
    Directory('${tmp.path}/app/lib/l10n/src').deleteSync(recursive: true);
    r = run(['--adopt']);
    t.eq(r.exitCode, 0, '--adopt läuft');
    t.isTrue(
      File('${tmp.path}/app/lib/l10n/src/weather/weather_fr.arb').existsSync(),
      '--adopt schreibt Fragment je Sprache',
    );
  } finally {
    tmp.deleteSync(recursive: true);
  }
}
