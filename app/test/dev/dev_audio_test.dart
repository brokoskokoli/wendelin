// WP148: Tonaufnahmen im Entwicklermodus, App-Seite: WAV-Dateien, Logzeile,
// Aufräumen. Alle Audiodaten sind synthetisch.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/voice/dev_audio.dart';
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

DevClip clip(
  String event, {
  int samples = 32000,
  DateTime? at,
  Map<String, int> marks = const {'cand': 1000},
}) => DevClip(
  event: event,
  pcm: Int16List.fromList([
    for (var i = 0; i < samples; i++) i % 20000 - 10000,
  ]),
  at: at ?? DateTime(2026, 10, 26, 0, 23, 49, 507),
  marksMs: marks,
);

void main() {
  late Directory dir;
  late List<String> logs;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('devaudio');
    logs = [];
    devLogSink = logs.add;
    devAudioDirectory = () async => Directory('${dir.path}/dev-audio');
    addTearDown(() {
      devAudioDirectory = devAudioDirectory;
      dir.deleteSync(recursive: true);
    });
  });

  List<File> files() => Directory('${dir.path}/dev-audio').existsSync()
      ? Directory('${dir.path}/dev-audio').listSync().whereType<File>().toList()
      : [];

  test('Name: Zeitstempel + Ereignis; Datei ist WAV 16 kHz mono PCM16 mit '
      'genau den Samples; Logzeile nennt Datei und Offsets', () async {
    devLogEnabled = true;
    final c = clip('barge-cand');
    saveDevClip(c);
    await devAudioIdle;
    final f = files().single;
    final name = f.uri.pathSegments.last;
    expect(name, '20261026-002349.507_barge-cand.wav');
    final wav = Wav.parse(f.readAsBytesSync());
    expect(wav.sampleRate, 16000);
    expect(wav.samples, c.pcm);
    // 44 Byte Kopf + 2 Byte je Sample.
    expect(f.lengthSync(), 44 + 2 * 32000);
    final line = logs.singleWhere((l) => l.contains(' audio '));
    expect(line, startsWith('Wendelin/dev: audio '));
    expect(line, contains('file="20261026-002349.507_barge-cand.wav"'));
    expect(line, contains('event="barge-cand"'));
    expect(line, contains(' ms=2000 '), reason: '32000 Samples = 2000 ms');
    expect(line, contains('candMs=1000'));
  });

  test(
    'ohne Entwicklermodus wird nichts geschrieben und nichts geloggt',
    () async {
      devLogEnabled = false;
      saveDevClip(clip('barge-cand'));
      saveDevClip(clip('rec'));
      await devAudioIdle;
      expect(files(), isEmpty);
      expect(Directory('${dir.path}/dev-audio').existsSync(), isFalse);
      expect(logs, isEmpty);
    },
  );

  test('der Haken der Sprachlogik folgt dem Flag (an/aus ohne Neustart)', () {
    devLogEnabled = false;
    expect(devAudioClips.on, isFalse);
    devLogEnabled = true;
    expect(devAudioClips.on, isTrue);
  });

  test('Flag nach dem Einreihen aus: nichts wird geschrieben', () async {
    devLogEnabled = true;
    saveDevClip(clip('rec'));
    devLogEnabled = false;
    await devAudioIdle;
    expect(files(), isEmpty);
    expect(logs, isEmpty);
  });

  test(
    'gleicher Zeitstempel und Ereignis: Zähler statt Überschreiben',
    () async {
      devLogEnabled = true;
      saveDevClip(clip('rec'));
      saveDevClip(clip('rec'));
      await devAudioIdle;
      expect(files().map((f) => f.uri.pathSegments.last).toList()..sort(), [
        '20261026-002349.507_rec-2.wav',
        '20261026-002349.507_rec.wav',
      ]);
    },
  );

  test(
    'kein Ordner (Gerät ohne externen Speicher): nichts, kein Fehler',
    () async {
      devLogEnabled = true;
      devAudioDirectory = () async => null;
      saveDevClip(clip('rec'));
      await devAudioIdle;
      expect(logs, isEmpty);
    },
  );

  test(
    'Schreibfehler stört nicht und blockiert die Warteschlange nicht',
    () async {
      devLogEnabled = true;
      // Ein Datei statt Ordner: create schlägt fehl.
      File('${dir.path}/blocker').writeAsStringSync('x');
      devAudioDirectory = () async => Directory('${dir.path}/blocker/sub');
      saveDevClip(clip('rec'));
      await devAudioIdle;
      devAudioDirectory = () async => Directory('${dir.path}/dev-audio');
      saveDevClip(clip('rec'));
      await devAudioIdle;
      expect(files(), hasLength(1));
    },
  );

  test(
    'zu viele wartende Clips werden verworfen und im Log vermerkt',
    () async {
      devLogEnabled = true;
      for (var i = 0; i < devAudioMaxPending + 3; i++) {
        saveDevClip(clip('rec', at: DateTime(2026, 10, 26, 1, 0, i)));
      }
      await devAudioIdle;
      expect(files(), hasLength(devAudioMaxPending));
      expect(logs.where((l) => l.contains('audio-dropped')), hasLength(3));
    },
  );

  group('Aufräumen', () {
    File make(String name, DateTime modified, {int bytes = 1000}) {
      final d = Directory('${dir.path}/dev-audio')..createSync(recursive: true);
      return File('${d.path}/$name')
        ..writeAsBytesSync(Uint8List(bytes))
        ..setLastModifiedSync(modified);
    }

    final now = DateTime(2026, 10, 26, 12);

    test(
      'älter als 1 Tag wird gelöscht, jünger bleibt, fremde Dateien auch',
      () async {
        make('old.wav', now.subtract(const Duration(hours: 25)));
        make('new.wav', now.subtract(const Duration(hours: 23)));
        make('note.txt', now.subtract(const Duration(days: 9)));
        final n = await pruneDevAudio(
          Directory('${dir.path}/dev-audio'),
          now: now,
        );
        expect(n, 1);
        expect(files().map((f) => f.uri.pathSegments.last).toList()..sort(), [
          'new.wav',
          'note.txt',
        ]);
      },
    );

    test('Obergrenze: die ältesten gehen zuerst, bis der Rest passt', () async {
      for (var i = 0; i < 5; i++) {
        make('f$i.wav', now.subtract(Duration(minutes: 50 - i)), bytes: 1000);
      }
      final n = await pruneDevAudio(
        Directory('${dir.path}/dev-audio'),
        now: now,
        maxBytes: 2500,
      );
      expect(n, 3);
      expect(files().map((f) => f.uri.pathSegments.last).toList()..sort(), [
        'f3.wav',
        'f4.wav',
      ]);
    });

    test('Ordner fehlt oder ist unlesbar: 0, kein Fehler', () async {
      expect(await pruneDevAudio(Directory('${dir.path}/none')), 0);
    });

    test('cleanDevAudio löscht auch bei ausgeschaltetem Modus', () async {
      devLogEnabled = false;
      make('old.wav', DateTime.now().subtract(const Duration(days: 3)));
      make('fresh.wav', DateTime.now());
      await cleanDevAudio();
      expect(files().map((f) => f.uri.pathSegments.last), ['fresh.wav']);
    });

    test(
      'nach dem Schreiben wird aufgeräumt (Obergrenze gilt laufend)',
      () async {
        devLogEnabled = true;
        make('old.wav', DateTime.now().subtract(const Duration(days: 3)));
        saveDevClip(clip('rec'));
        await devAudioIdle;
        expect(files().map((f) => f.uri.pathSegments.last), [
          '20261026-002349.507_rec.wav',
        ]);
      },
    );
  });

  test('Stempel mit führenden Nullen', () {
    expect(
      devAudioStamp(DateTime(2026, 1, 2, 3, 4, 5, 6)),
      '20260102-030405.006',
    );
  });
}
