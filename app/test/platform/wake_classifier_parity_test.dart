// WP129: Parität der App-Kette (mel, embedding, Klassifikator auf der
// ONNX-Runtime) mit dem Messskript. Erwartete Scores: tool/kws_parity_fixture.py
// (Fensterbildung wie tool/kws_measure.py), Fixture synthetisch.
//
// Das Modell liegt nicht im Repo: der Test läuft nur lokal mit
//   WENDELIN_WAKE_MODELS=<Ordner mit melspectrogram.onnx, embedding_model.onnx>
//   WENDELIN_WAKE_CLASSIFIER=<wendelin_wp130_a.onnx>
//   WENDELIN_ORT_LIB=<libonnxruntime.dylib/.so>
// und prüft zusätzlich die SHA-256 des Modells gegen den Katalog.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/onnx_wake_models.dart';
import 'package:wendelin/platform/voice/ort_session.dart';
import 'package:wendelin/platform/voice/wake_feature_chain.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// Gemessene Abweichung: unter 3e-7 (float32, andere Laufzeit-Version und
/// Summationsreihenfolge). 1e-4 lässt zwei Größenordnungen Luft und ist
/// klein gegen das Band der Schwellen (0,98 bis 0,995, Breite 0,015); ein
/// Layout-, Raster- oder Skalierungsfehler liegt weit darüber (0,03 und mehr).
const tolerance = 1e-4;

void main() {
  final env = Platform.environment;
  final models = env['WENDELIN_WAKE_MODELS'];
  final classifier = env['WENDELIN_WAKE_CLASSIFIER'];
  final lib = env['WENDELIN_ORT_LIB'];
  final missing = models == null || classifier == null || lib == null;

  test(
    'Scores der App-Kette = Scores des Messskripts auf dem Fixture',
    () {
      final expected = jsonDecode(
        File('test/fixtures/wake/parity.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final wav = File('test/fixtures/wake/parity.wav').readAsBytesSync();
      final ends = (expected['ends'] as List).cast<int>();
      final scores = (expected['scores'] as List).cast<num>();
      final pcm = Int16List.sublistView(Uint8List.fromList(wav.sublist(44)));
      final sha = sha256.convert(File(classifier!).readAsBytesSync());
      expect(
        sha.toString(),
        SpeechModelCatalog.wakeClassifierWendelin.files.single.sha256,
      );

      final m = OnnxWakeModels.open(
        models!,
        runtime: OrtRuntime.open(DynamicLibrary.open(lib!)),
        classifierPath: classifier,
      );
      final chain = WakeFeatureChain(m);
      final windows = <WakeWindow>[];
      for (var i = 0; i < pcm.length; i += 480) {
        windows.addAll(
          chain.accept(
            Int16List.sublistView(pcm, i, (i + 480).clamp(0, pcm.length)),
          ),
        );
      }
      m.close();

      expect(windows.map((w) => w.endSample), ends);
      for (var i = 0; i < scores.length; i++) {
        expect(
          windows[i].modelScore,
          closeTo(scores[i].toDouble(), tolerance),
          reason: 'Fenster $i',
        );
      }
    },
    skip: missing
        ? 'lokal: WENDELIN_WAKE_MODELS, WENDELIN_WAKE_CLASSIFIER, '
              'WENDELIN_ORT_LIB setzen (Modell nicht im Repo)'
        : null,
  );
}
