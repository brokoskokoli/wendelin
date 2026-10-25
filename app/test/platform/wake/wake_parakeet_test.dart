import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_settings_providers.dart';
import 'package:wendelin/platform/voice/nemo_sherpa.dart';
import 'package:wendelin/platform/voice/whisper_registry.dart';
import 'package:wendelin/platform/voice/whisper_sherpa.dart';
import 'package:wendelin/platform/voice/whisper_stt.dart';
import 'package:wendelin/platform/wake/device_wake_parts.dart';
import 'package:wendelin/platform/wake/wake_detector.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const _tokens =
    '<unk> 0\n<|pnc|> 1\n▁W 2\nend 3\nel 4\nin 5\ne 9\nn 10\nd 11\nl 12\n'
    'i 13\n<blk> 16\n';

final class _Svc implements SpeechModelService {
  _Svc(this.root, {this.installed = true});
  final Directory root;
  final bool installed;

  @override
  Future<bool> isInstalled(SpeechModel model) async =>
      installed && model.id == SpeechModelCatalog.parakeetV3.id;

  @override
  Directory directoryOf(SpeechModel model) => root;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

final class _Backend implements WhisperBackend {
  _Backend(this.text);
  final String text;
  Object? error;
  int peak = 0;
  bool disposed = false;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
    if (error != null) throw error!;
    peak = samples.fold(
      0,
      (p, s) => (s * 32768).abs() > p ? (s * 32768).abs().round() : p,
    );
    return WhisperResult(text: text, language: 'de');
  }

  @override
  Future<void> dispose() async => disposed = true;
}

Int16List _tone(int amp) => Int16List.fromList([
  for (var i = 0; i < 16000; i++) (amp * (i.isEven ? 1 : -1) * 0.7).round(),
]);

const _files = NemoFiles(
  engine: SttEngine.nemoTransducer,
  encoder: 'e',
  decoder: 'd',
  joiner: 'j',
  tokens: 't',
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('wake_parakeet'));
  tearDown(() => dir.deleteSync(recursive: true));

  Directory install() {
    const m = SpeechModelCatalog.parakeetV3;
    final base = m.files.first.name.replaceFirst('.tar.bz2', '');
    final d = Directory('${dir.path}/$base')..createSync(recursive: true);
    for (final n in const [
      'encoder.int8.onnx',
      'decoder.int8.onnx',
      'joiner.int8.onnx',
    ]) {
      File('${d.path}/$n').writeAsStringSync('x');
    }
    File('${d.path}/tokens.txt').writeAsStringSync(_tokens);
    return Directory('${dir.path}/hw');
  }

  group('wakeParakeetFiles', () {
    test('Hotword „Wendelin“ mit Boost 2,0 aus dem Katalog', () async {
      final hw = install();
      final f = await wakeParakeetFiles(
        service: _Svc(dir),
        hotwordsDirectory: hw,
      );
      expect(WakeClassifierRules.parakeetHotwords, ['Wendelin']);
      expect(f, isNotNull);
      expect(File(f!.hotwords!.file).readAsStringSync(), 'Wendelin\n');
      expect(f.hotwords!.score, 2.0);
      expect(f.hotwords!.score, WakeClassifierRules.parakeetHotwordsScore);
      final c = nemoRecognizerConfig(f, language: 'de', threads: 1);
      expect(c.decodingMethod, 'modified_beam_search');
      expect(c.hotwordsScore, 2.0);
      expect(c.model.modelingUnit, 'bpe');
    });

    test('nicht installiert: null (Rückfall auf Whisper)', () async {
      install();
      expect(
        await wakeParakeetFiles(
          service: _Svc(dir, installed: false),
          hotwordsDirectory: Directory('${dir.path}/hw'),
        ),
        isNull,
      );
    });

    test('Hotword nicht buchstabierbar: null, kein Parakeet ohne Hotword', () async {
      final hw = install();
      File(
        '${dir.path}/${SpeechModelCatalog.parakeetV3.files.first.name.replaceFirst('.tar.bz2', '')}/tokens.txt',
      ).writeAsStringSync('<unk> 0\n<blk> 1\n');
      expect(
        await wakeParakeetFiles(service: _Svc(dir), hotwordsDirectory: hw),
        isNull,
      );
    });

    test('Dateien fehlen: null', () async {
      final base = SpeechModelCatalog.parakeetV3.files.first.name.replaceFirst(
        '.tar.bz2',
        '',
      );
      Directory('${dir.path}/$base').createSync();
      expect(
        await wakeParakeetFiles(
          service: _Svc(dir),
          hotwordsDirectory: Directory('${dir.path}/hw'),
        ),
        isNull,
      );
    });
  });

  group('LazyParakeetVerifier', () {
    test('Ausschnitt wird normalisiert, Modell danach freigegeben', () async {
      final backend = _Backend('Wendelin');
      var starts = 0;
      final v = LazyParakeetVerifier(
        files: () async => const NemoFiles(
          engine: SttEngine.nemoTransducer,
          encoder: 'e',
          decoder: 'd',
          joiner: 'j',
          tokens: 't',
        ),
        idleRelease: const Duration(milliseconds: 10),
        start: (_) async {
          starts++;
          return backend;
        },
      );
      expect(v.kind, 'parakeet');
      expect(await v.confirm(_tone(900)), isTrue);
      expect(await v.confirm(_tone(900)), isTrue);
      expect(starts, 1);
      expect(backend.peak, inInclusiveRange(16300, 16400));
    });

    test('eigene Instanz: nichts wird mit der Befehlserkennung geteilt (WP146)', () async {
      // The command recognizer shares its Parakeet through the registry
      // (hotwords of the user, other engines borrow it); the verifier loads
      // an own one with the wake word as hotword and neither publishes nor
      // borrows, so check and command recognition cannot influence each other.
      final backend = _Backend('Wendelin');
      final v = LazyParakeetVerifier(
        files: () async => _files,
        idleRelease: const Duration(milliseconds: 10),
        start: (_) async => backend,
      );
      expect(await v.confirm(_tone(900)), isTrue);
      final id = SpeechModelCatalog.parakeetV3.id;
      expect(await lookupSharedWhisper(id), isNull);
      expect(await whisperUsers(id, 'none'), 0);
    });

    test('Freigabe nach der Haltezeit (fakeAsync)', () {
      fakeAsync((async) {
        final backend = _Backend('Wendelin');
        final v = LazyParakeetVerifier(
          files: () async => _files,
          idleRelease: const Duration(seconds: 60),
          start: (_) async => backend,
        );
        v.confirm(_tone(900));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 59));
        expect(backend.disposed, isFalse);
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(backend.disposed, isTrue);
      });
    });

    test('Prüfung wirft nach dem Laden: Isolat wird freigegeben', () async {
      final backend = _Backend('x')..error = StateError('boom');
      final v = LazyParakeetVerifier(
        files: () async => _files,
        start: (_) async => backend,
      );
      await expectLater(v.confirm(_tone(900)), throwsA(isA<VoiceException>()));
      expect(backend.disposed, isTrue);
      await v.release();
    });

    test('Ladefehler: Signal für den Rückfall, nicht verfügbar', () async {
      var starts = 0;
      final v = LazyParakeetVerifier(
        files: () async => _files,
        start: (_) async {
          starts++;
          throw StateError('defekt');
        },
      );
      await expectLater(
        v.confirm(_tone(900)),
        throwsA(isA<WakeVerifierUnavailable>()),
      );
      expect(await v.isAvailable(), isFalse);
      expect(starts, 1);
    });

    test('Ladefehler: kein zweiter Versuch nach 60 s (fakeAsync)', () {
      fakeAsync((async) {
        var starts = 0;
        final v = LazyParakeetVerifier(
          files: () async => _files,
          idleRelease: const Duration(seconds: 60),
          start: (_) async {
            starts++;
            throw StateError('defekt');
          },
        );
        v.confirm(_tone(900)).then((_) {}, onError: (_) {});
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 120));
        async.flushMicrotasks();
        var available = true;
        v.isAvailable().then((a) => available = a);
        async.flushMicrotasks();
        expect(available, isFalse);
        expect(starts, 1);
      });
    });

    test(
      'Ladefehler: geänderte Modelldateien geben eine neue Chance',
      () async {
        final f = File('${dir.path}/enc')..writeAsStringSync('a');
        final files = NemoFiles(
          engine: SttEngine.nemoTransducer,
          encoder: f.path,
          decoder: 'd',
          joiner: 'j',
          tokens: 't',
        );
        var fail = true;
        final v = LazyParakeetVerifier(
          files: () async => files,
          start: (_) async {
            if (fail) throw StateError('defekt');
            return _Backend('Wendelin');
          },
        );
        await expectLater(
          v.confirm(_tone(900)),
          throwsA(isA<WakeVerifierUnavailable>()),
        );
        await v.release();
        expect(await v.isAvailable(), isFalse); // release setzt nicht zurück
        f.writeAsStringSync('neue Datei, anderer Inhalt');
        expect(await v.isAvailable(), isTrue);
        fail = false;
        expect(await v.confirm(_tone(900)), isTrue);
        await v.release();
      },
    );

    test('anderes Wort wird abgelehnt', () async {
      final v = LazyParakeetVerifier(
        files: () async => const NemoFiles(
          engine: SttEngine.nemoTransducer,
          encoder: 'e',
          decoder: 'd',
          joiner: 'j',
          tokens: 't',
        ),
        start: (_) async => _Backend('Guten Tag'),
      );
      expect(await v.confirm(_tone(900)), isFalse);
      await v.release();
    });

    test('nicht installiert: modelMissing, verfügbar false', () async {
      final v = LazyParakeetVerifier(files: () async => null);
      expect(await v.isAvailable(), isFalse);
      await expectLater(v.confirm(_tone(900)), throwsA(isA<VoiceException>()));
      await v.release();
    });
  });

  group('DeviceWakeParts.verifier', () {
    ProviderContainer container(bool installed) => ProviderContainer(
      overrides: [
        speechModelServiceProvider.overrideWith(
          (_) async => _Svc(dir, installed: installed),
        ),
      ],
    );

    test('Vorlagen-Weg: Whisper', () {
      final parts = DeviceWakeParts(container(true));
      expect(parts.verifier(), isA<LazyWhisperVerifier>());
      expect(
        parts.verifier(detector: WakeDetector.templates),
        isA<LazyWhisperVerifier>(),
      );
    });

    test(
      'Modell-Modus mit Parakeet: Parakeet, Hotword aus dem Katalog',
      () async {
        final hw = install();
        final backend = _Backend('Wendelin');
        SttSpec? seen;
        final parts = DeviceWakeParts(
          container(true),
          hotwordsDirectory: () async => hw,
          parakeetStart: (spec) async {
            seen = spec;
            return backend;
          },
        );
        final v = parts.verifier(detector: WakeDetector.model);
        expect(await v.confirm(_tone(900)), isTrue);
        expect(v.kind, 'parakeet');
        expect((seen! as NemoFiles).hotwords!.score, 2.0);
        expect(backend.peak, greaterThan(16000));
        await parts.dispose();
        expect(backend.disposed, isTrue);
      },
    );

    test('Modell-Modus, Hotword nicht buchstabierbar: Whisper, kein Parakeet', () async {
      final hw = install();
      File(
        '${dir.path}/${SpeechModelCatalog.parakeetV3.files.first.name.replaceFirst('.tar.bz2', '')}/tokens.txt',
      ).writeAsStringSync('<unk> 0\n<blk> 1\n');
      final parts = DeviceWakeParts(
        container(true),
        hotwordsDirectory: () async => hw,
        parakeetStart: (_) async => fail('Parakeet darf nicht starten'),
      );
      final v = parts.verifier(detector: WakeDetector.model);
      await expectLater(v.confirm(_tone(900)), throwsA(isA<Object>()));
      expect(v.kind, 'whisper');
    });

    test(
      'Modell-Modus, Parakeet-Ladefehler: derselbe Treffer an Whisper',
      () async {
        final hw = install();
        var starts = 0;
        final parts = DeviceWakeParts(
          container(true),
          hotwordsDirectory: () async => hw,
          parakeetStart: (_) async {
            starts++;
            throw StateError('defekt');
          },
        );
        final v = parts.verifier(detector: WakeDetector.model);
        // Whisper is not installed in this test: its error (not the one of
        // Parakeet) reaches the caller, so the same hit went to Whisper.
        await expectLater(
          v.confirm(_tone(900)),
          throwsA(isNot(isA<WakeVerifierUnavailable>())),
        );
        expect(v.kind, 'whisper');
        await expectLater(v.confirm(_tone(900)), throwsA(isA<Object>()));
        expect(starts, 1);
        await parts.dispose();
      },
    );

    test('Modell-Modus ohne Parakeet: still Whisper (Rückfall)', () async {
      final parts = DeviceWakeParts(
        container(false),
        hotwordsDirectory: () async => Directory('${dir.path}/hw'),
        parakeetStart: (_) async => fail('Parakeet darf nicht starten'),
      );
      final v = parts.verifier(detector: WakeDetector.model);
      // Whisper is not installed either in this test: the call fails, but
      // the recognizer that was asked is Whisper.
      await expectLater(v.confirm(_tone(900)), throwsA(isA<Object>()));
      expect(v.kind, 'whisper');
    });
  });
}
