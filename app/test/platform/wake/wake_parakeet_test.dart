import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_settings_providers.dart';
import 'package:wendelin/platform/voice/nemo_sherpa.dart';
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
  int peak = 0;
  bool disposed = false;

  @override
  Future<WhisperResult> transcribe(
    Float32List samples, {
    String? language,
  }) async {
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
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(backend.disposed, isTrue);
    });

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
