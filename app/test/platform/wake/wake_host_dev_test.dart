// WP148/WP155: Tonaufnahmen, Archiv und Löschlauf des Weckwort-Dienstes im
// Entwicklermodus (aus wake_host_test.dart ausgelagert).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/pcm.dart';
import 'package:wendelin/platform/wake/service_audio_input.dart';
import 'package:wendelin/platform/wake/wake_host.dart';
import 'package:wendelin/voice/dev_archive.dart';
import 'package:wendelin/voice/dev_audio.dart';
import 'package:wendelin/voice/dev_log.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import 'wake_host_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<(String, Object?)> toKotlin;
  late List<String> logs;
  late ServiceAudioInput audio;
  late FakeParts parts;
  late WakeHost host;

  Future<void> fromKotlin(String method, [Object? args]) async {
    final done = Completer<void>();
    unawaited(
      messenger.handlePlatformMessage(
        wakeEngineChannelName,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)),
        (_) => done.complete(),
      ),
    );
    await done.future;
  }

  List<String> calls() => [for (final (m, _) in toKotlin) m];

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(condition(), isTrue, reason: '${calls()} $logs');
  }

  Future<void> start({
    bool verify = false,
    FakeParts? p,
    Map<String, Object?> extra = const {},
  }) async {
    parts = p ?? FakeParts();
    audio = ServiceAudioInput(channel);
    host = WakeHost(parts: parts, audio: audio);
    await host.attach();
    await fromKotlin('run', {'verify': verify, ...extra});
    await until(() => calls().contains('startMic'));
  }

  // The Kotlin service sends 100 ms chunks.
  Future<void> hear(Int16List frame) =>
      fromKotlin('audio', {'pcm': bytes(frame)});

  setUp(() {
    toKotlin = [];
    logs = [];
    final saved = voiceLogSink;
    final savedEngine = voiceLogEngine;
    voiceLogSink = logs.add;
    voiceLogEngine = 'wake';
    addTearDown(() {
      voiceLogSink = saved;
      voiceLogEngine = savedEngine;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      toKotlin.add((call.method, call.arguments));
      return null;
    });
  });

  tearDown(() async {
    await fromKotlin('shutdown');
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('Tonaufnahmen im Entwicklermodus (WP148)', () {
    late Directory out;
    late List<String> devLines;

    setUp(() {
      out = Directory.systemTemp.createTempSync('wakedev');
      devLines = [];
      devLogSink = devLines.add;
      devAudioDirectory = () async => out;
      addTearDown(() => out.deleteSync(recursive: true));
    });

    List<String> names() => [
      for (final f in out.listSync().whereType<File>()) f.uri.pathSegments.last,
    ]..sort();

    // Ein abgelehnter Kandidat mit 2,5 s Nachlauf: das Weckwort kommt nach
    // 0,3 s Rauschen, Stufe 2 sagt nein, der Dienst hört weiter.
    Future<void> rejectedCandidate() async {
      await hear(Int16List(1600));
      await hear(Int16List(1600));
      await hear(FakeWakeWordEngine.markerFrame(1600));
      for (var i = 0; i < 25; i++) {
        await hear(Int16List(1600));
      }
      await until(() => devLines.any((l) => l.contains('wake-cand')));
      await devAudioIdle;
    }

    test('dev=true im run: Kandidat und Prüf-Ausschnitt als WAV, Log nennt '
        'Datei und Offsets', () async {
      await start(
        verify: true,
        p: FakeParts(verdict: false),
        extra: {'dev': true},
      );
      await rejectedCandidate();
      final n = names();
      expect(n.where((x) => x.endsWith('_wake-cand.wav')), hasLength(1));
      expect(n.where((x) => x.endsWith('_wake-verify.wav')), hasLength(1));
      final cand = out.listSync().whereType<File>().singleWhere(
        (f) => f.path.endsWith('_wake-cand.wav'),
      );
      final wav = Wav.parse(cand.readAsBytesSync());
      final line = devLines.singleWhere((l) => l.contains('wake-cand.wav'));
      expect(line, contains('engine=wake'));
      expect(line, contains('file="${cand.uri.pathSegments.last}"'));
      // Länge in der Logzeile = Länge der Datei; Kandidat 200 ms (Anfang des
      // Stroms) vor dem Ende des Treffers, Nachlauf 2 s.
      final ms = wav.samples.length * 1000 ~/ 16000;
      expect(line, contains(' ms=$ms '));
      expect(line, contains('postMs=2000'));
      expect(line, contains('candMs=${ms - 2000}'));
    });

    test('ohne dev im run: nichts gespeichert, kein Ordner', () async {
      await start(verify: true, p: FakeParts(verdict: false));
      await hear(FakeWakeWordEngine.markerFrame(1600));
      for (var i = 0; i < 25; i++) {
        await hear(Int16List(1600));
      }
      await until(() => logs.any((l) => l.contains('wake-verify')));
      await devAudioIdle;
      expect(names(), isEmpty);
      expect(devLines.where((l) => l.contains('audio')), isEmpty);
    });

    test(
      'devMode-Aufruf schaltet ohne Neustart um; alles außer true ist aus',
      () async {
        await start(verify: true, p: FakeParts(verdict: false));
        expect(devLogEnabled, isFalse);
        await fromKotlin('devMode', {'on': true});
        expect(devLogEnabled, isTrue);
        await rejectedCandidate();
        expect(
          names().where((x) => x.endsWith('_wake-cand.wav')),
          hasLength(1),
        );
        await fromKotlin('devMode', {'on': 'yes'});
        expect(devLogEnabled, isFalse);
        await fromKotlin('devMode', {'on': true});
        await fromKotlin('devMode');
        expect(devLogEnabled, isFalse);
        // Ein neues run ohne Angabe (Kotlin kennt den Wert nicht): aus.
        await fromKotlin('devMode', {'on': true});
        await fromKotlin('run', {'verify': true});
        expect(devLogEnabled, isFalse);
      },
    );

    // WP155: the app deletes first; a write still under way may bring the
    // folder back, so the service deletes itself once its writes are over.
    DevClip clip(String event) => DevClip(
      event: event,
      pcm: Int16List(100),
      at: DateTime(2026, 10, 26),
      marksMs: const {},
    );

    Future<void> seedAfterAppDeleted() async {
      devLogEnabled = true;
      File('${out.path}/20261026-000000.000_wake-cand.wav')
          .writeAsBytesSync([1, 2, 3]);
      saveDevArchiveEntry(
        DevArchiveEntry(
          at: DateTime(2026, 10, 26, 12),
          source: 'idle',
          outcome: 'near-miss',
          meta: const {},
          cand: clip('x'),
        ),
      );
      await devArchiveIdle;
      expect(Directory('${out.path}/$devArchiveFolder').existsSync(), isTrue);
    }

    test('ausgeschaltet mit clear: der Dienst löscht Aufnahmen selbst, das '
        'Archiv bleibt', () async {
      await start();
      await seedAfterAppDeleted();
      await fromKotlin('devMode', {'on': false, 'clear': true});
      await until(
        () =>
            !File('${out.path}/20261026-000000.000_wake-cand.wav').existsSync(),
      );
      expect(Directory('${out.path}/$devArchiveFolder').existsSync(), isTrue);
    });

    test(
      'ausgeschaltet mit clear und archive: auch das Archiv ist weg',
      () async {
        await start();
        await seedAfterAppDeleted();
        await fromKotlin('devMode', {
          'on': false,
          'clear': true,
          'archive': true,
        });
        await until(
          () => !Directory('${out.path}/$devArchiveFolder').existsSync(),
        );
        expect(names(), isEmpty);
      },
    );

    // Holds the first access to the folder; meanwhile `then` arrives.
    // [pendingWrite]: the held access is a write of this isolate (the sweep
    // waits for it); else it is the sweep's own deletion of the recordings.
    Future<void> sweepRace(
      List<bool> then, {
      required bool pendingWrite,
    }) async {
      await start();
      await seedAfterAppDeleted();
      final held = Completer<void>();
      final release = Completer<void>();
      devAudioDirectory = () async {
        if (!held.isCompleted) {
          held.complete();
          await release.future;
        }
        return out;
      };
      if (pendingWrite) {
        saveDevClip(clip('late'));
        await held.future;
      }
      const off = {'on': false, 'clear': true, 'archive': true};
      await fromKotlin('devMode', off);
      await held.future;
      for (final on in then) {
        await fromKotlin('devMode', {'on': on});
      }
      release.complete();
      await host.sweepIdle;
      expect(Directory('${out.path}/$devArchiveFolder').existsSync(), isTrue);
    }

    for (final (name, then, write) in [
      ('aus (clear) und wieder an, während geschrieben wird', [true], true),
      (
        'aus (clear), an, wieder aus, während geschrieben wird',
        [true, false],
        true,
      ),
      (
        'an während des Löschens der Aufnahmen: das Archiv bleibt',
        [true],
        false,
      ),
    ]) {
      test(name, () async {
        await sweepRace(then, pendingWrite: write);
        // The recordings go in the third case only (the deletion was under way).
        expect(names().contains('20261026-000000.000_wake-cand.wav'), write);
      });
    }

    test(
      'ausgeschaltet ohne clear (alter Aufruf): nichts wird gelöscht',
      () async {
        await start();
        await seedAfterAppDeleted();
        // A sweep would reach the folder after microtasks only.
        var touched = false;
        devAudioDirectory = () async {
          touched = true;
          return out;
        };
        await fromKotlin('devMode', {'on': false});
        await pumpEventQueue();
        expect(touched, isFalse);
        expect(names(), isNotEmpty);
        expect(Directory('${out.path}/$devArchiveFolder').existsSync(), isTrue);
      },
    );
  });
}
