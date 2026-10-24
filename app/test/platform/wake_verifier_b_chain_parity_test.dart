// WP143: Kette von Prüfer B (Zuschnitt, batchSequence mit Mel- und
// Embedding-Modell der ONNX-Runtime, Zentrieren, Wert je Kopf) gegen den
// Kettenfall der Lieferung WP137 (test/fixtures/wake/verifier_b_chain_parity.json,
// synthetisch, mit echten openWakeWord-Embeddings erzeugt).
//
// Die Modelle liegen nicht im Repo: der Test läuft nur lokal mit
//   WENDELIN_WAKE_MODELS=<Ordner mit melspectrogram.onnx, embedding_model.onnx>
//   WENDELIN_ORT_LIB=<libonnxruntime.dylib/.so>
// Toleranzen aus der Datei: Embeddings 1e-3, Werte 1e-4.
//
// Zuschnitt der Vorlagen: Die Lieferung rechnet mit Trim -40 dB, die App
// ohne Trim (Probe WP137). Der Test bildet den Trim der Lieferung hier nach
// (nur für diesen Vergleich), damit die Kette ab dem Clip vergleichbar ist;
// die Clip-Länge der Datei (`clip_len`) prüft, dass es derselbe Clip ist.
//
// Zwei Läufe: (1) Clips wie in Python (Gleitkomma, Spitze 0,5, ganzzahlig
// `trunc(x * 32767)`): prüft Mel, Embedding, Phase der Frames auf 1e-3.
// (2) Clips der App (int16 der Quelle, `normalizePeak` rundet): die
// Quantisierung um 1 LSB verschiebt die Embeddings um bis zu etwa 0,004 (bei
// Werten von ±5 bis ±30), die Kopfwerte um unter 6e-5; geprüft werden hier
// die Kopfwerte auf 1e-4 und die Embeddings auf 0,01.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/platform/voice/onnx_wake_models.dart';
import 'package:wendelin/platform/voice/ort_session.dart';
import 'package:wendelin/platform/voice/wake_feature_chain.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

enum Mode { python, app }

const _appEmbeddingTolerance = 0.01;

/// Trim der Lieferung (`real_split.trim`) auf Gleitkomma-Samples: Grenzen.
(int, int) trimBounds(List<double> part) {
  const frame = 160;
  final n = part.length ~/ frame;
  final rms = [
    for (var f = 0; f < n; f++)
      math.sqrt(
        [for (var i = f * frame; i < (f + 1) * frame; i++) part[i] * part[i]]
                .reduce((a, b) => a + b) /
            frame,
      ),
  ];
  final top = rms.reduce(math.max);
  final on = [
    for (var f = 0; f < n; f++)
      if (20 * math.log(rms[f] / (top + 1e-9)) / math.ln10 > -40) f,
  ];
  if (on.isEmpty) return (0, part.length);
  return (
    math.max(0, on.first * frame - 800),
    math.min(part.length, (on.last + 1) * frame + 800),
  );
}

/// Clip für die Kette: Spitze 0,5 wie `normalize` der Lieferung (Python) bzw.
/// wie die App (int16 der Quelle, dann `normalizePeak`).
Int16List toClip(List<double> x, Mode mode) {
  if (mode == Mode.python) {
    final peak = x.map((v) => v.abs()).reduce(math.max);
    return Int16List.fromList([
      for (final v in x) (v * 0.5 / peak * 32767).truncate(),
    ]);
  }
  return normalizePeak(
    Int16List.fromList([for (final v in x) (v * 32768).round()]),
    target: 0.5,
    minPeak: 1,
  );
}

double maxDiff(Float32List a, List<dynamic> rows) {
  var worst = 0.0;
  final want = [
    for (final r in rows) ...[for (final v in r as List) (v as num).toDouble()],
  ];
  expect(a.length, want.length);
  for (var i = 0; i < want.length; i++) {
    worst = math.max(worst, (a[i] - want[i]).abs());
  }
  return worst;
}

void main() {
  final env = Platform.environment;
  final models = env['WENDELIN_WAKE_MODELS'];
  final lib = env['WENDELIN_ORT_LIB'];
  final missing = models == null || lib == null;

  for (final mode in Mode.values) {
    test(
      'Kette von Prüfer B = Kettenfall der Lieferung (${mode.name}: '
      'Embeddings, Kopfwerte)',
      () {
        final fx = jsonDecode(
          File('test/fixtures/wake/verifier_b_chain_parity.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        final tol = fx['tolerance'] as Map<String, dynamic>;
        final embTol = mode == Mode.python
            ? (tol['embeddings'] as num).toDouble()
            : _appEmbeddingTolerance;
        final m = OnnxWakeModels.open(
          models!,
          runtime: OrtRuntime.open(DynamicLibrary.open(lib!)),
        );
        try {
          // Live: x[i] = 0.4 * ((i*37 % 2001) - 1000) / 2000, 64000 Samples.
          final liveInfo = fx['live'] as Map<String, dynamic>;
          final x = [
            for (var i = 0; i < 64000; i++)
              0.4 * ((i * 37 % 2001) - 1000) / 2000,
          ];
          final end = liveInfo['decision_end_sample'] as int;
          final bounds = verifierBLiveBounds(end);
          final clip = toClip(x.sublist(bounds.from, bounds.to), mode);
          expect(clip.length, liveInfo['segment_len']);
          if (mode == Mode.app) {
            // Der Weg der App selbst (Ausschnitt + Spitze) ergibt denselben Clip.
            final viaApp = verifierBLiveClip(
              Int16List.fromList([for (final v in x) (v * 32768).round()]),
              end,
            );
            expect(viaApp, clip);
          }
          final liveSeq = WakeFeatureChain.batchSequence(m, clip)!;
          expect(liveSeq.length ~/ 96, liveInfo['frames_F']);
          final liveDiff = maxDiff(liveSeq, liveInfo['embeddings'] as List);
          stdout.writeln('WP143 ${mode.name} live max |dEmb| = $liveDiff');
          expect(liveDiff, lessThan(embTol));

          // Einlernen: y[i] = ((i*k % 2001) - 1000) / 2000 * (0.4 im Wort,
          // sonst 0.001 mit k = 37), 144000 Samples.
          final templates = <VerifierBSequence>[];
          for (final t
              in (fx['templates'] as List).cast<Map<String, dynamic>>()) {
            final k = t['step'] as int;
            final start = (t['start_s'] as num).toDouble();
            final end = (t['end_s'] as num).toDouble();
            final y = [
              for (var i = 0; i < 144000; i++)
                (((i >= (start * 16000).toInt() && i < (end * 16000).toInt()
                                ? i * k
                                : i * 37) %
                            2001) -
                        1000) /
                    2000 *
                    (i >= (start * 16000).toInt() && i < (end * 16000).toInt()
                        ? 0.4
                        : 0.001),
            ];
            final b = verifierBTemplateBounds(y.length, start, end);
            final part = y.sublist(b.from, b.to);
            final (lo, hi) = trimBounds(part);
            expect(hi - lo, t['clip_len']);
            final seq = WakeFeatureChain.batchSequence(
              m,
              toClip(part.sublist(lo, hi), mode),
            )!;
            expect(seq.length ~/ 96, t['frames_m']);
            final d = maxDiff(seq, t['embeddings'] as List);
            stdout.writeln('WP143 ${mode.name} template k=$k max |dEmb| = $d');
            expect(d, lessThan(embTol));
            templates.add(VerifierBSequence.prepare(seq, wakeVerifierBMu));
          }

          // Werte: Vorlage gegen Live und Mittel der besten 3 je Kopf.
          final live = VerifierBSequence.prepare(liveSeq, wakeVerifierBMu);
          final heads = fx['heads'] as Map<String, dynamic>;
          for (final e in heads.entries) {
            final h = e.value as Map<String, dynamic>;
            final idx = (h['templates'] as List).cast<int>();
            final want = (h['template_scores'] as List).cast<num>();
            for (var j = 0; j < idx.length; j++) {
              final got = verifierBTemplateScore(live, templates[idx[j]]);
              stdout.writeln(
                'WP143 ${mode.name} ${e.key} Vorlage ${idx[j]}: $got '
                '(Datei ${want[j]})',
              );
              expect(
                got,
                closeTo(want[j].toDouble(), (tol['scores'] as num).toDouble()),
              );
            }
            expect(
              verifierBScore(live, [for (final i in idx) templates[i]]),
              closeTo(
                (h['head_score'] as num).toDouble(),
                (tol['scores'] as num).toDouble(),
              ),
              reason: 'Kopf ${e.key}',
            );
          }
        } finally {
          m.close();
        }
      },
      skip: missing
          ? 'lokal: WENDELIN_WAKE_MODELS und WENDELIN_ORT_LIB setzen '
                '(Modelle nicht im Repo)'
          : null,
    );
  }
}
