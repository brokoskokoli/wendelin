// WP155: Weckwort-Archiv, App-Seite: Schreiber, Indexzeile, Neustart (kein
// Löschen nach einem Tag), Deckel mit Vorrang für near-miss, Schreibfehler,
// Entwicklermodus aus und die Nebenläufigkeit mit dem Wake-Dienst. Alle
// Audiodaten sind synthetisch; keine Wanduhr (Dateizeiten werden gesetzt).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/voice/dev_archive.dart';
import 'package:wendelin/voice/dev_audio.dart';
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

DevClip clip({
  int samples = 1000,
  Map<String, int> marks = const {'cand': 10},
}) => DevClip(
  event: 'x',
  pcm: Int16List.fromList([for (var i = 0; i < samples; i++) i % 500]),
  at: DateTime(2026, 10, 26),
  marksMs: marks,
);

/// A clip of 1000 samples is a 2044 byte WAV.
const wavBytes = 2044;

DevArchiveEntry entry(
  String outcome, {
  int second = 0,
  String source = 'idle',
  Map<String, Object?> meta = const {'score': 0.91},
  DevClip? verify,
  bool withClip = true,
}) => DevArchiveEntry(
  at: DateTime(2026, 10, 26, 12, 0, second, 5),
  source: source,
  outcome: outcome,
  meta: meta,
  cand: withClip ? clip() : null,
  verify: verify,
);

void main() {
  late Directory root;
  late Directory archive;
  late List<String> logs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('devarchive');
    archive = Directory('${root.path}/dev-audio/$devArchiveFolder');
    logs = [];
    devLogSink = logs.add;
    devLogEnabled = true;
    devAudioDirectory = () async => Directory('${root.path}/dev-audio');
    devArchiveResetInfo();
    addTearDown(() {
      devLogEnabled = false;
      root.deleteSync(recursive: true);
    });
  });

  Future<void> save(DevArchiveEntry e) async {
    saveDevArchiveEntry(e);
    await devArchiveIdle;
  }

  List<String> wavs() => archive.existsSync()
      ? (archive
            .listSync()
            .whereType<File>()
            .map((f) => f.uri.pathSegments.last)
            .where((n) => n.endsWith('.wav'))
            .toList()
          ..sort())
      : [];

  List<Map<String, dynamic>> lines() {
    final f = File('${archive.path}/$devArchiveIndexName');
    if (!f.existsSync()) return [];
    return [
      for (final l in f.readAsLinesSync())
        if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
    ];
  }

  int indexBytes() => File('${archive.path}/$devArchiveIndexName').lengthSync();

  /// Marks every file as old (as after weeks), so nothing counts as "just
  /// written".
  void age() {
    for (final f in archive.listSync().whereType<File>()) {
      f.setLastModifiedSync(DateTime(2026, 9, 1));
    }
  }

  group('Schreiber', () {
    test('je Eintrag eine WAV und eine Indexzeile mit allen Feldern', () async {
      devArchiveSetInfo('idle', {'thr': 0.85, 'mode': 'model'});
      // The package joins the facts of the engine to the case (DevArchive).
      final facts = devArchive.context('idle');
      await save(
        entry(
          'accepted',
          meta: {...facts, 'score': 0.99, 'text': 'hallo wendelin'},
          verify: clip(samples: 2000, marks: {'cand': 5}),
        ),
      );
      expect(wavs(), [
        '20261026-120000.005_idle-accepted-verify.wav',
        '20261026-120000.005_idle-accepted.wav',
      ]);
      final f = File('${archive.path}/20261026-120000.005_idle-accepted.wav');
      expect(Wav.parse(f.readAsBytesSync()).samples, clip().pcm);
      final l = lines().single;
      expect(l['file'], '20261026-120000.005_idle-accepted.wav');
      expect(l['verify_file'], '20261026-120000.005_idle-accepted-verify.wav');
      expect(l['source'], 'idle');
      expect(l['outcome'], 'accepted');
      expect(l['score'], 0.99);
      expect(l['text'], 'hallo wendelin');
      expect(l['thr'], 0.85);
      expect(l['mode'], 'model');
      expect(l['app'], devArchiveAppVersion);
      expect(l['ms'], 62); // 1000 samples at 16 kHz
      expect(l['verify_ms'], 125);
      expect(l['cand_ms'], 10);
      expect(l['verify_cand_ms'], 5);
      expect(l['t'], isA<String>());
      expect(l['label'], '');
      expect(logs.where((x) => x.contains(' archive ')), hasLength(1));
    });

    test(
      'gleicher Zeitpunkt: zweite Datei bekommt -2, nichts überschrieben',
      () async {
        await save(entry('rejected'));
        await save(entry('rejected'));
        expect(wavs(), [
          '20261026-120000.005_idle-rejected-2.wav',
          '20261026-120000.005_idle-rejected.wav',
        ]);
        expect(lines().map((l) => l['file']).toSet(), hasLength(2));
      },
    );

    test('Eintrag ohne Clip: nur die Zeile, ohne Datei', () async {
      await save(entry('dropped', withClip: false, meta: {'reason': 'busy'}));
      expect(wavs(), isEmpty);
      final l = lines().single;
      expect(l.containsKey('file'), isFalse);
      expect(l['reason'], 'busy');
    });

    test('Schwärzung: PIN im Text wird nicht gespeichert', () async {
      await save(entry('accepted', meta: {'pin': '4711', 'text': 'ok'}));
      expect(
        File('${archive.path}/$devArchiveIndexName').readAsStringSync(),
        isNot(contains('4711')),
      );
      expect(lines().single['text'], 'ok');
    });

    test(
      'Schwärzung: erkannter Text mit PIN oder Karte wird geschwärzt',
      () async {
        await save(
          entry(
            'accepted',
            meta: {'text': 'meine pin ist 1234 danke', 'lp': -0.2},
          ),
        );
        await save(
          entry(
            'rejected',
            second: 1,
            meta: {'text': 'karte 4111 1111 1111 1111 bitte'},
          ),
        );
        final raw = File('${archive.path}/$devArchiveIndexName')
            .readAsStringSync();
        expect(raw, isNot(contains('1234')));
        expect(raw, isNot(contains('4111')));
        expect(lines().first['text'], contains('***'));
        // The rest stays readable.
        expect(lines().first['lp'], -0.2);
      },
    );

    test('Neustart: cleanDevAudio löscht das Archiv nicht, auch nicht nach '
        'Wochen; kurzlebige Aufnahmen schon', () async {
      await save(entry('accepted'));
      age();
      final old = File('${root.path}/dev-audio/20260901-000000.000_x.wav')
        ..writeAsBytesSync([0]);
      old.setLastModifiedSync(DateTime(2026, 9, 1));
      await cleanDevAudio();
      expect(old.existsSync(), isFalse);
      expect(wavs(), hasLength(1));
      expect(lines(), hasLength(1));
      // Und ein zweiter Lauf (zweiter Neustart) ändert nichts.
      await cleanDevAudio();
      expect(wavs(), hasLength(1));
    });

    test('Statistik zählt Einträge mit Audio und deren Größe', () async {
      await save(entry('accepted'));
      await save(entry('rejected', second: 1));
      final s = await devArchiveStats();
      expect(s.cases, 2);
      expect(s.bytes, greaterThan(2 * wavBytes));
      await clearDevArchive();
      expect((await devArchiveStats()).cases, 0);
      expect(archive.existsSync(), isFalse);
    });

    test('Statistik liest den Index nicht (nur den Ordner)', () async {
      await save(entry('accepted'));
      // A foreign or broken index changes nothing about the count.
      File('${archive.path}/$devArchiveIndexName')
          .writeAsStringSync('kein json\n' * 1000);
      expect((await devArchiveStats()).cases, 1);
    });

    test('Version der App entspricht der pubspec', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final v = RegExp(
        r'^version:\s*(\S+)',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1);
      expect(devArchiveAppVersion, v);
    });
  });

  group('Entwicklermodus aus', () {
    test('nichts wird geschrieben, auch kein Ordner', () async {
      devLogEnabled = false;
      await save(entry('accepted'));
      expect(archive.existsSync(), isFalse);
      expect(logs, isEmpty);
    });

    test('ausgeschaltet, während der Eintrag wartet: nichts landet', () async {
      saveDevArchiveEntry(entry('accepted'));
      devLogEnabled = false; // Wake-Dienst bekommt das Flag per Kotlin
      await devArchiveIdle;
      expect(archive.existsSync(), isFalse);
    });

    test('ausgeschaltet nach dem Audio, vor der Zeile: keine Zeile, die WAV '
        'wird entfernt', () async {
      final put = devArchivePut;
      addTearDown(() => devArchivePut = put);
      devArchivePut = (f, bytes) async {
        final n = await put(f, bytes);
        devLogEnabled = false; // the wake service learns it just now
        return n;
      };
      await save(entry('accepted')); // one file: the flag falls after it
      expect(lines(), isEmpty);
      expect(wavs(), isEmpty);
    });

    test(
      'ausgeschaltet mitten im Schreiben: keine Datei, keine Zeile',
      () async {
        // The flag falls right after the folder was looked up.
        devAudioDirectory = () async {
          devLogEnabled = false;
          return Directory('${root.path}/dev-audio');
        };
        await save(entry('accepted', verify: clip()));
        expect(wavs(), isEmpty);
        expect(lines(), isEmpty);
      },
    );
  });

  group('Schreibfehler', () {
    test(
      'Ordner nicht anlegbar: Fehler geloggt, Schlange läuft weiter',
      () async {
        File('${root.path}/blocked').writeAsStringSync('x'); // a file
        devAudioDirectory = () async => Directory('${root.path}/blocked');
        await save(entry('accepted'));
        expect(logs.where((l) => l.contains('archive-error')), hasLength(1));
        // The voice path never noticed; the next entry works.
        devAudioDirectory = () async => Directory('${root.path}/dev-audio');
        await save(entry('rejected', second: 2));
        expect(lines().single['outcome'], 'rejected');
        expect(wavs(), hasLength(1));
      },
    );

    test('mehr als 16 wartende Einträge: weitere werden verworfen und '
        'geloggt', () async {
      for (var i = 0; i < 20; i++) {
        saveDevArchiveEntry(entry('rejected', second: i));
      }
      await devArchiveIdle;
      expect(logs.where((l) => l.contains('archive-dropped')), hasLength(4));
      expect(lines(), hasLength(16));
    });
  });

  group('Deckel', () {
    /// Writes the cases into the folder (with index lines) and ages them.
    Future<void> fill(List<(String outcome, int second)> cases) async {
      for (final (o, s) in cases) {
        await save(entry(o, second: s));
      }
      age();
    }

    List<String> outcomes() =>
        wavs().map((n) => n.split('_').last.replaceAll('.wav', '')).toList();

    test('älteste zuerst; accepted/rejected/dropped bleiben', () async {
      await fill([
        ('accepted', 1),
        ('rejected', 2),
        ('dropped', 3),
        ('accepted', 4),
      ]);
      final n = await pruneDevArchive(
        archive,
        maxBytes: 2 * wavBytes + indexBytes(),
        minAge: Duration.zero,
      );
      expect(n, 2);
      expect(wavs(), [
        '20261026-120003.005_idle-dropped.wav',
        '20261026-120004.005_idle-accepted.wav',
      ]);
    });

    test('near-miss geht zuerst, auch wenn er der neueste ist', () async {
      await fill([
        ('accepted', 1),
        ('near-miss', 2),
        ('rejected', 3),
        ('near-miss', 4),
      ]);
      await pruneDevArchive(
        archive,
        maxBytes: 2 * wavBytes + indexBytes(),
        minAge: Duration.zero,
      );
      expect(outcomes(), ['idle-accepted', 'idle-rejected']);
    });

    test(
      'near-miss belegt höchstens die Hälfte, auch wenn noch Platz ist',
      () async {
        await fill([
          ('accepted', 1),
          ('near-miss', 2),
          ('near-miss', 3),
          ('near-miss', 4),
          ('near-miss', 5),
        ]);
        // The total (5 WAVs and the index) fits, the near misses (4 WAVs) are
        // more than half of 12000 bytes.
        await pruneDevArchive(archive, maxBytes: 12000, minAge: Duration.zero);
        expect(wavs(), [
          '20261026-120001.005_idle-accepted.wav',
          '20261026-120004.005_idle-near-miss.wav',
          '20261026-120005.005_idle-near-miss.wav',
        ]);
      },
    );

    test('der Index wird nie umgeschrieben; Zeilen ohne Audio bleiben und '
        'zählen nicht', () async {
      await fill([('accepted', 1), ('rejected', 2), ('accepted', 3)]);
      final before = File('${archive.path}/$devArchiveIndexName')
          .readAsStringSync();
      await pruneDevArchive(
        archive,
        maxBytes: wavBytes + indexBytes() + 50,
        minAge: Duration.zero,
      );
      expect(
        File('${archive.path}/$devArchiveIndexName').readAsStringSync(),
        before,
      );
      expect((await devArchiveStats()).cases, 1);
    });

    test(
      'verwaiste WAV (keine Zeile): alt wird gelöscht, jung bleibt',
      () async {
        await save(entry('accepted'));
        final oldOrphan = File('${archive.path}/20260101-000000.000_idle-x.wav')
          ..writeAsBytesSync([1, 2]);
        final youngOrphan = File(
          '${archive.path}/20261026-000000.000_idle-y.wav',
        )..writeAsBytesSync([1, 2]);
        age();
        youngOrphan.setLastModifiedSync(DateTime.now());
        await pruneDevArchive(archive);
        expect(oldOrphan.existsSync(), isFalse);
        expect(youngOrphan.existsSync(), isTrue);
        expect(wavs(), hasLength(2)); // the case itself and the young one
      },
    );

    test('periodisches Beschneiden fegt keine Waisen (liest den Index nicht); '
        'der Start (cleanDevAudio) schon', () async {
      archive.createSync(recursive: true);
      File('${archive.path}/$devArchiveIndexName')
          .writeAsStringSync('${jsonEncode({'file': 'other.wav'})}\n');
      final orphan = File('${archive.path}/20260101-000000.000_idle-x.wav')
        ..writeAsBytesSync([1, 2]);
      orphan.setLastModifiedSync(DateTime(2026, 1, 1));
      // Every 25th write scans and prunes: 25 writes hit it, wherever the
      // counter stood.
      for (var i = 0; i < 25; i++) {
        await save(entry('accepted', second: i));
      }
      expect(orphan.existsSync(), isTrue);
      await cleanDevAudio();
      expect(orphan.existsSync(), isFalse);
      expect(wavs(), hasLength(25));
    });

    test('Waisen-Sweep mit langem Index (mehrere Takte): lebende bleiben, '
        'Waisen gehen', () async {
      archive.createSync(recursive: true);
      final live = File('${archive.path}/20260101-000001.000_idle-live.wav')
        ..writeAsBytesSync([1]);
      final orphan = File('${archive.path}/20260101-000002.000_idle-orph.wav')
        ..writeAsBytesSync([1]);
      for (final f in [live, orphan]) {
        f.setLastModifiedSync(DateTime(2026, 1, 1));
      }
      final sb = StringBuffer();
      for (var i = 0; i < 1300; i++) {
        sb.writeln(jsonEncode({'file': 'gone-$i.wav'}));
      }
      sb
        ..writeln('{torn')
        ..writeln(jsonEncode({'file': '20260101-000001.000_idle-live.wav'}));
      File('${archive.path}/$devArchiveIndexName')
          .writeAsStringSync(sb.toString());
      await pruneDevArchive(archive);
      expect(live.existsSync(), isTrue);
      expect(orphan.existsSync(), isFalse);
    });

    test('ohne Index gilt nichts als verwaist', () async {
      archive.createSync(recursive: true);
      final f = File('${archive.path}/20260101-000000.000_idle-x.wav')
        ..writeAsBytesSync([1]);
      f.setLastModifiedSync(DateTime(2026, 1, 1));
      await pruneDevArchive(archive);
      expect(f.existsSync(), isTrue);
    });
  });

  group('Nebenläufigkeit mit dem Wake-Dienst', () {
    test('Beschneiden während des Schreibens: keine verwaiste WAV, keine '
        'verlorene Zeile', () async {
      // Jung = gerade geschrieben: das Beschneiden fasst es nicht an, selbst
      // bei Deckel 0 (hier steht der Fall des anderen Isolates).
      final futures = <Future<void>>[];
      for (var i = 0; i < 6; i++) {
        saveDevArchiveEntry(entry('rejected', second: i, verify: clip()));
        futures.add(
          pruneDevArchive(
            archive,
            maxBytes: 0,
            nearMissMaxBytes: 0,
          ).then((_) {}),
        );
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(futures);
      await devArchiveIdle;
      expect(lines(), hasLength(6));
      final named = {
        for (final l in lines()) ...[l['file'], l['verify_file']],
      };
      expect(wavs().toSet(), named);
      expect(wavs(), hasLength(12));
    });

    test('Beschneiden trifft einen frischen Fall nicht (Deckel 0)', () async {
      await save(entry('accepted', verify: clip()));
      await save(entry('rejected', second: 1));
      final near = entry('rejected', second: 2);
      await save(
        DevArchiveEntry(
          at: near.at,
          source: 'idle',
          outcome: 'near-miss',
          meta: const {},
          cand: clip(),
        ),
      );
      final before = wavs();
      expect(before, hasLength(4));
      // Just written (younger than a minute): not even a cap of 0 cuts it.
      final n = await pruneDevArchive(
        archive,
        maxBytes: 0,
        nearMissMaxBytes: 0,
      );
      expect(n, 0);
      expect(wavs(), before);
      // The same cases once they are old: gone.
      age();
      expect(
        await pruneDevArchive(archive, maxBytes: 0, nearMissMaxBytes: 0),
        3,
      );
    });

    test('zweiter Schreiber im selben Ordner (anderes Isolat): gleicher '
        'Name wird nie doppelt vergeben', () async {
      // Another isolate took the name already.
      archive.createSync(recursive: true);
      File('${archive.path}/20261026-120000.005_idle-accepted.wav')
          .writeAsBytesSync([9, 9]);
      await save(entry('accepted'));
      expect(wavs(), [
        '20261026-120000.005_idle-accepted-2.wav',
        '20261026-120000.005_idle-accepted.wav',
      ]);
      expect(
        File('${archive.path}/20261026-120000.005_idle-accepted.wav')
            .readAsBytesSync(),
        [9, 9],
      );
    });

    test('Anhängen läuft an einem Beschneiden vorbei: Zeile bleibt', () async {
      await save(entry('accepted', second: 1));
      age();
      // Prune runs, then a line arrives "from the other isolate".
      await pruneDevArchive(archive, maxBytes: 0, minAge: Duration.zero);
      await save(entry('accepted', second: 2));
      expect(lines().map((l) => l['outcome']), ['accepted', 'accepted']);
      expect((await devArchiveStats()).cases, 1);
    });
  });
}
