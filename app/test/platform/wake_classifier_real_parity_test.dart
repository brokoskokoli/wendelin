// WP129 „Parität echt“: die echte App-Rechnung (Strom, Merkmalskette plus
// Klassifikator, dazu die echte CandidateWakeEngine mit dem Band des Handys)
// auf den echten Prüf-Aufnahmen. Schreibt je Quelle die Fensterwerte und die
// Engine-Treffer als Rohdaten in einen Ordner AUSSERHALB des Repos; den
// Vergleich mit dem Messskript macht tool/wake_parity_real.py. Aufnahmen und
// Rohdaten liegen nie im Repo.
//
//   WENDELIN_PARITY_AUDIO=<Ordner mit all_<gerät>.wav, neg_<gerät>.wav>
//   WENDELIN_PARITY_OUT=<Ausgabeordner>
//   WENDELIN_WAKE_MODELS / WENDELIN_WAKE_CLASSIFIER / WENDELIN_ORT_LIB
//   WENDELIN_PARITY_FRAME=320   (Samples je Block; Gerät: 20 ms)
//   WENDELIN_PARITY_SRC=pos_huawei,...  (optional, sonst alle vier)
//   WENDELIN_PARITY_DROPS=1,2,99,2g1200,2goff  (dropsToEnd je Engine, optional
//                                  Gate-Gedächtnis ms bzw. off; ein Strom der Kette,
//                                  je Wert ein Unterordner d<N> im Ausgabeordner;
//                                  99 = Halten bis holdWindows)
//   WENDELIN_PARITY_SKIP=0      (führende Samples weglassen: verschiebt das
//                                Raster gegenüber der Sprache, Phasenstreuung)
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/onnx_wake_models.dart';
import 'package:wendelin/platform/voice/ort_session.dart';
import 'package:wendelin/platform/voice/wake_feature_chain.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Gibt die Fenster der Kette weiter und merkt sich Ende und Wert.
final class _Recorder implements WakeFeatureExtractor {
  _Recorder(this.inner);
  final WakeFeatureExtractor inner;
  final ends = <int>[];
  final scores = <double>[];

  @override
  String get featureVersion => inner.featureVersion;
  @override
  Future<void> open() => inner.open();
  @override
  Future<List<WakeWindow>> accept(Int16List frame) async {
    final out = await inner.accept(frame);
    for (final w in out) {
      ends.add(w.endSample);
      scores.add(w.modelScore ?? double.nan);
    }
    return out;
  }

  @override
  void reset() => inner.reset();
  @override
  Future<void> close() => inner.close();
}

/// Spielt die einmal gerechneten Fenster je Block wieder ab (mehrere Engines
/// mit verschiedenen Regeln sehen exakt denselben Strom der Kette).
final class _Replay implements WakeFeatureExtractor {
  _Replay(this.blocks);
  final List<List<WakeWindow>> blocks;
  var _i = 0;
  @override
  String get featureVersion => 'replay';
  @override
  Future<void> open() async {}
  @override
  Future<List<WakeWindow>> accept(Int16List frame) async => blocks[_i++];
  @override
  void reset() => _i = 0;
  @override
  Future<void> close() async {}
}

/// PCM16 aus einer WAV-Datei (Chunks durchlaufen: manche Dateien tragen
/// vor `data` einen Füll-Chunk).
Int16List readWav(String path) {
  final b = File(path).readAsBytesSync();
  var p = 12;
  while (p + 8 <= b.length) {
    final id = ascii.decode(b.sublist(p, p + 4));
    final n = ByteData.sublistView(b, p + 4, p + 8).getUint32(0, Endian.little);
    if (id == 'data') {
      final len = (b.length - p - 8 < n ? b.length - p - 8 : n) & ~1;
      return Int16List.sublistView(
        Uint8List.fromList(b.sublist(p + 8, p + 8 + len)),
      );
    }
    p += 8 + n + (n & 1);
  }
  throw StateError('kein data-Chunk in $path');
}

void main() {
  final env = Platform.environment;
  final audio = env['WENDELIN_PARITY_AUDIO'];
  final out = env['WENDELIN_PARITY_OUT'];
  final models = env['WENDELIN_WAKE_MODELS'];
  final classifier = env['WENDELIN_WAKE_CLASSIFIER'];
  final lib = env['WENDELIN_ORT_LIB'];
  final missing = [audio, out, models, classifier, lib].contains(null);
  final frameLen = int.tryParse(env['WENDELIN_PARITY_FRAME'] ?? '') ?? 320;
  final skip = int.tryParse(env['WENDELIN_PARITY_SKIP'] ?? '') ?? 0;
  final all = ['pos_huawei', 'pos_handy2', 'neg_huawei', 'neg_handy2'];
  final srcs = env['WENDELIN_PARITY_SRC']?.split(',') ?? all;
  final band = WakeClassifierRules.phone;
  // Varianten: <N> oder <N>g<ms> / <N>goff (anderes Pegel-Gate: Gedächtnis in ms
  // bzw. ohne Gate), nur für die Messung der Fix-Optionen.
  final variants = [
    for (final d in (env['WENDELIN_PARITY_DROPS'] ?? '').split(','))
      if (RegExp(r'^\d+(g(off|\d+))?$').hasMatch(d)) d,
  ];
  SpeechGate? gateFor(String v) {
    final g = RegExp(r'g(off|\d+)$').firstMatch(v)?.group(1);
    if (g == null) return SpeechGate();
    return g == 'off'
        ? null
        : SpeechGate(memory: Duration(milliseconds: int.parse(g)));
  }

  test(
    'App-Strom auf den Prüf-Aufnahmen (Rohdaten für den Abgleich)',
    () async {
      Directory(out!).createSync(recursive: true);
      final m = OnnxWakeModels.open(
        models!,
        runtime: OrtRuntime.open(DynamicLibrary.open(lib!)),
        classifierPath: classifier,
      );
      for (final src in srcs) {
        final dev = src.split('_')[1];
        final file = src.startsWith('pos_') ? 'all_$dev.wav' : 'neg_$dev.wav';
        final pcm = Int16List.sublistView(readWav('$audio/$file'), skip);
        final rec = _Recorder(ChainWakeFeatureExtractor(() async => m));
        final blocks = <List<WakeWindow>>[];
        await rec.open();
        for (var i = 0; i < pcm.length; i += frameLen) {
          final end = i + frameLen < pcm.length ? i + frameLen : pcm.length;
          blocks.add(await rec.accept(Int16List.sublistView(pcm, i, end)));
        }
        for (final n in variants.isEmpty ? [null] : variants) {
          final engine = CandidateWakeEngine(
            features: _Replay(blocks),
            modelThreshold: band.verifyFrom,
            directThreshold: band.acceptFrom,
            holdWindows: WakeClassifierRules.holdWindows,
            dropsToEnd: n == null
                ? WakeClassifierRules.dropsToEnd
                : int.parse(RegExp(r'^\d+').firstMatch(n)![0]!),
            mainGate: n == null ? SpeechGate() : gateFor(n),
          );
          await engine.open(const [KeywordSpec.wendelin]);
          final hits = <Map<String, Object?>>[];
          for (var i = 0; i < pcm.length; i += frameLen) {
            final end = i + frameLen < pcm.length ? i + frameLen : pcm.length;
            for (final h in await engine.accept(
              Int16List.sublistView(pcm, i, end),
            )) {
              hits.add({
                'end': h.endSample,
                'score': h.score,
                'direct': h.direct,
              });
            }
          }
          final dir = n == null ? out : '$out/d$n';
          Directory(dir).createSync(recursive: true);
          File(
            '$dir/$src.ends.i32',
          ).writeAsBytesSync(Int32List.fromList(rec.ends).buffer.asUint8List());
          File('$dir/$src.scores.f32').writeAsBytesSync(
            Float32List.fromList(rec.scores).buffer.asUint8List(),
          );
          File('$dir/$src.hits.json').writeAsStringSync(
            jsonEncode({
              'frame': frameLen,
              'skip': skip,
              'samples': pcm.length,
              'hits': hits,
            }),
          );
        }
        // Die Kette gehört der Engine nicht: nur den Wrapper-Zustand lösen.
        rec.reset();
      }
      m.close();
    },
    timeout: const Timeout(Duration(hours: 3)),
    skip: missing
        ? 'lokal: WENDELIN_PARITY_AUDIO, WENDELIN_PARITY_OUT und die Modell-Variablen setzen'
        : null,
  );
}
