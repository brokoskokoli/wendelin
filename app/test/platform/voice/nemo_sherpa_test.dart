import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/nemo_sherpa.dart';
import 'package:wendelin/platform/voice/stt_loader.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('nemo_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  const parakeet = SpeechModelCatalog.parakeetV3;
  const canary = SpeechModelCatalog.canary180m;

  String unpacked(SpeechModel m, List<String> names) {
    final base = m.files.first.name.replaceFirst('.tar.bz2', '');
    final d = Directory('${dir.path}/$base')..createSync(recursive: true);
    for (final n in names) {
      File('${d.path}/$n').writeAsStringSync('x');
    }
    return d.path;
  }

  const parakeetFiles = [
    'encoder.int8.onnx',
    'decoder.int8.onnx',
    'joiner.int8.onnx',
    'tokens.txt',
  ];

  group('NemoFiles.find', () {
    test('Parakeet: vier Dateien im entpackten Ordner', () {
      final d = unpacked(parakeet, parakeetFiles);
      final f = NemoFiles.find(parakeet, dir.path)!;
      expect(f.engine, SttEngine.nemoTransducer);
      expect(f.encoder, '$d/encoder.int8.onnx');
      expect(f.joiner, '$d/joiner.int8.onnx');
      expect(f.tokens, '$d/tokens.txt');
      expect(f.paths, hasLength(4));
    });

    test('Canary: kein Joiner nötig', () {
      unpacked(canary, [
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'tokens.txt',
      ]);
      final f = NemoFiles.find(canary, dir.path)!;
      expect(f.engine, SttEngine.canary);
      expect(f.joiner, isEmpty);
      expect(f.paths, hasLength(3));
    });

    test('fehlende Dateien oder Ordner: null; Whisper: null', () {
      expect(NemoFiles.find(parakeet, dir.path), isNull);
      unpacked(parakeet, ['encoder.int8.onnx', 'tokens.txt']);
      expect(NemoFiles.find(parakeet, dir.path), isNull);
      expect(NemoFiles.find(SpeechModelCatalog.whisperSmall, dir.path), isNull);
    });

    test('Hotwords nur beim Transducer', () {
      unpacked(parakeet, parakeetFiles);
      unpacked(canary, [
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'tokens.txt',
      ]);
      const hw = NemoHotwords(file: '/h.txt', bpeVocab: '/b.vocab');
      expect(
        NemoFiles.find(parakeet, dir.path, hotwords: hw)!.hotwords,
        same(hw),
      );
      expect(NemoFiles.find(canary, dir.path, hotwords: hw)!.hotwords, isNull);
    });
  });

  group('Erkenner-Konfiguration', () {
    NemoFiles files({NemoHotwords? hw}) => NemoFiles(
      engine: SttEngine.nemoTransducer,
      encoder: '/e',
      decoder: '/d',
      joiner: '/j',
      tokens: '/t',
      hotwords: hw,
    );

    test('Transducer ohne Hotwords: greedy, kein bpe (sonst Absturz)', () {
      final c = nemoRecognizerConfig(files(), language: 'de', threads: 2);
      expect(c.model.modelType, 'nemo_transducer');
      expect(c.model.transducer.joiner, '/j');
      expect(c.decodingMethod, 'greedy_search');
      expect(c.hotwordsFile, isEmpty);
      expect(c.model.modelingUnit, isEmpty);
      expect(c.model.bpeVocab, isEmpty);
      expect(c.model.numThreads, 2);
    });

    test('Transducer mit Hotwords: modified_beam_search, Score 1.0, bpe', () {
      final c = nemoRecognizerConfig(
        files(
          hw: const NemoHotwords(file: '/h', bpeVocab: '/v'),
        ),
        language: 'de',
        threads: 2,
      );
      expect(c.decodingMethod, 'modified_beam_search');
      expect(c.hotwordsFile, '/h');
      expect(c.hotwordsScore, 1.0);
      expect(c.model.modelingUnit, 'bpe');
      expect(c.model.bpeVocab, '/v');
    });

    test('Score ist einstellbar', () {
      final c = nemoRecognizerConfig(
        files(
          hw: const NemoHotwords(file: '/h', bpeVocab: '/v', score: 1.5),
        ),
        language: 'de',
        threads: 1,
      );
      expect(c.hotwordsScore, 1.5);
    });

    test('Canary: Sprache als Quelle und Ziel, keine Hotwords', () {
      final c = nemoRecognizerConfig(
        const NemoFiles(
          engine: SttEngine.canary,
          encoder: '/e',
          decoder: '/d',
          tokens: '/t',
        ),
        language: 'fr',
        threads: 1,
      );
      expect(c.model.canary.srcLang, 'fr');
      expect(c.model.canary.tgtLang, 'fr');
      expect(c.hotwordsFile, isEmpty);
    });
  });

  group('writeNemoHotwords', () {
    late String tokens;
    setUp(() {
      tokens = '${dir.path}/tokens.txt';
      File(tokens).writeAsStringSync(
        '<unk> 0\n<|pnc|> 1\n▁W 2\nend 3\nel 4\nin 5\n▁K 6\nü 7\nche 8\n'
        'e 9\nn 10\nd 11\nl 12\ni 13\nc 14\nh 15\n<blk> 16\n',
      );
    });

    test('schreibt Namen und bpe.vocab; nicht Buchstabierbares entfällt', () {
      final out = Directory('${dir.path}/hw');
      final hw = writeNemoHotwords(
        tokens: tokens,
        terms: ['Wendelin', 'Küche', 'Zorro'],
        directory: out,
      )!;
      expect(File(hw.file).readAsStringSync(), 'Wendelin\nKüche\n');
      expect(File(hw.bpeVocab).readAsStringSync(), startsWith('<unk>\t0\n'));
      expect(File(hw.bpeVocab).readAsStringSync(), isNot(contains('<blk>')));
      expect(hw.score, 1.0);
    });

    test('nichts Buchstabierbares: null, keine Dateien', () {
      final out = Directory('${dir.path}/hw');
      expect(
        writeNemoHotwords(tokens: tokens, terms: ['Zorro'], directory: out),
        isNull,
      );
      expect(out.existsSync(), isFalse);
    });
  });

  group('resolveNemoFiles', () {
    const tokensText =
        '<unk> 0\n<|pnc|> 1\n▁W 2\nend 3\nel 4\nin 5\n▁K 6\nü 7\nche 8\n'
        'e 9\nn 10\nd 11\nl 12\ni 13\nc 14\nh 15\n<blk> 16\n';

    String parakeetDir() {
      final d = unpacked(parakeet, parakeetFiles);
      File('$d/tokens.txt').writeAsStringSync(tokensText);
      return d;
    }

    test(
      'Standard-Bonus 1.0 für alle Hinweisbegriffe, auch Wendelin (WP146)',
      () {
        parakeetDir();
        expect(defaultHotwordsScore, 1.0);
        final f = resolveNemoFiles(
          parakeet,
          dir.path,
          hintTerms: ['Wendelin', 'Küche'],
        )!;
        expect(f.hotwords!.score, 1.0);
        expect(
          nemoRecognizerConfig(f, language: 'de', threads: 2).hotwordsScore,
          1.0,
        );
      },
    );

    test('Parakeet: die Namen kommen als Hotwords im Erkenner an', () {
      parakeetDir();
      final f = resolveNemoFiles(
        parakeet,
        dir.path,
        hintTerms: ['Wendelin', 'Küche'],
        hotwordsScore: 4.5,
      )!;
      final hw = f.hotwords!;
      expect(File(hw.file).readAsStringSync(), 'Wendelin\nKüche\n');
      expect(hw.score, 4.5);
      final c = nemoRecognizerConfig(f, language: 'de', threads: 2);
      expect(c.decodingMethod, 'modified_beam_search');
      expect(c.hotwordsFile, hw.file);
      expect(c.hotwordsScore, 4.5);
    });

    test('Canary bekommt keine Hotwords, aber die App-Sprache', () {
      unpacked(canary, [
        'encoder.int8.onnx',
        'decoder.int8.onnx',
        'tokens.txt',
      ]);
      final f = resolveNemoFiles(
        canary,
        dir.path,
        hintTerms: ['Wendelin'],
        fallbackLanguage: 'fr',
      )!;
      expect(f.hotwords, isNull);
      expect(f.fallbackLanguage, 'fr');
    });

    test('keine Namen: alte hotwords.txt wird gelöscht, Modell läuft', () {
      parakeetDir();
      expect(
        resolveNemoFiles(parakeet, dir.path, hintTerms: ['Wendelin'])!.hotwords,
        isNotNull,
      );
      final old = File('${dir.path}/hotwords/hotwords.txt');
      expect(old.existsSync(), isTrue);
      final f = resolveNemoFiles(parakeet, dir.path, hintTerms: ['Zorro'])!;
      expect(f.hotwords, isNull);
      expect(old.existsSync(), isFalse);
      // Auch ohne jeden Begriff.
      resolveNemoFiles(parakeet, dir.path, hintTerms: ['Wendelin']);
      expect(resolveNemoFiles(parakeet, dir.path)!.hotwords, isNull);
      expect(old.existsSync(), isFalse);
    });

    test('fehlendes Modell: null', () {
      expect(resolveNemoFiles(parakeet, dir.path), isNull);
    });
  });

  group('Hotword-Zählung fürs Log (WP146)', () {
    test('Treffer als ganze Wörter, nur die Anzahl', () {
      const terms = ['wendelin', 'küche'];
      expect(countHotwordHits('Hey Wendelin, mach die Küche an.', terms), 2);
      expect(countHotwordHits('Wendelinchen', terms), 0);
      expect(countHotwordHits('Wendelin Wendelin', terms), 1);
      expect(countHotwordHits('Wendelin', const []), 0);
    });

    test('Begriffe aus der Datei, ohne Hotwords oder Datei: leer', () {
      final f = File('${dir.path}/h.txt')
        ..writeAsStringSync('Wendelin\n\nKüche\n');
      expect(hotwordTermsOf(NemoHotwords(file: f.path, bpeVocab: '/v')), [
        'wendelin',
        'küche',
      ]);
      expect(hotwordTermsOf(null), isEmpty);
      expect(
        hotwordTermsOf(
          const NemoHotwords(file: '/gibt/es/nicht', bpeVocab: '/v'),
        ),
        isEmpty,
      );
    });
  });

  group('pickCanaryLanguage', () {
    test('bekannte Sprache gewinnt, sonst die App-Sprache, sonst de', () {
      expect(pickCanaryLanguage('fr', 'de'), 'fr');
      expect(pickCanaryLanguage('en-US', 'de'), 'en');
      expect(pickCanaryLanguage(null, 'fr'), 'fr');
      expect(pickCanaryLanguage('ja', 'es'), 'es');
      expect(pickCanaryLanguage('ja', 'ko'), 'de');
    });
  });

  group('startSttBackend', () {
    test('fehlendes NeMo-Modell: modelMissing', () {
      expect(
        startSttBackend(parakeet, dir.path),
        throwsA(
          isA<VoiceException>().having(
            (e) => e.kind,
            'kind',
            VoiceErrorKind.modelMissing,
          ),
        ),
      );
    });

    test('Whisper geht weiter über die Whisper-Dateien', () {
      expect(
        startSttBackend(SpeechModelCatalog.whisperBase, dir.path),
        throwsA(isA<VoiceException>()),
      );
    });
  });

  test('Engine-Namen', () {
    expect(sttEngineName(SttEngine.whisper), contains('Whisper'));
    expect(sttEngineName(SttEngine.nemoTransducer), contains('Parakeet'));
    expect(sttEngineName(SttEngine.canary), contains('Canary'));
  });
}
