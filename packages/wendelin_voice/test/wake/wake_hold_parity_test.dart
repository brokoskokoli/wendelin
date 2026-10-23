// WP141: the hold rule of CandidateWakeEngine against the shared fixture
// test/fixtures/wake_hold_parity.json. The Python replica
// (tool/train_wake_word/stage2_cut.py `app_events`, test_stage2_cut.py) is
// checked against the same file, so both stay one rule.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

/// One scripted window per `accept` call, at the given end time.
final class _Scripted implements WakeFeatureExtractor {
  _Scripted(this.windows);
  final List<WakeWindow> windows;
  int next = 0;

  @override
  String get featureVersion => 'fake-1';
  @override
  Float32List? get embeddingMean => null;
  @override
  String? get centerId => null;
  @override
  Future<void> open() async {}
  @override
  Future<List<WakeWindow>> accept(Int16List frame) async => [windows[next++]];
  @override
  void reset() {}
  @override
  Future<void> close() async {}
}

int _samples(num ms) => (ms * 16).round();

void main() {
  final fx = jsonDecode(
    File('test/fixtures/wake_hold_parity.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final rule = fx['rule']! as Map<String, Object?>;
  final cases = (fx['cases']! as List).cast<Map<String, Object?>>();

  test('Fixture deckt die Pflichtfälle ab', () {
    final names = cases.map((c) => c['name']).toSet();
    expect(
      names,
      containsAll([
        'spitze_bei_0_72',
        'spitze_bei_0_80_zaehlt',
        'spitze_bei_0_88_zaehlt_nicht',
        'raster_0_79',
        'raster_0_81_entscheidet',
        'doppelgipfel',
        'abfall_unter_das_band_und_wiederanstieg',
        'direkt_nach_abfall',
        'nan_mitten_im_halten',
        'sperrzeit_spitze_zu_spitze',
        'zwei_rufe',
      ]),
    );
  });

  for (final c in cases) {
    test('Parität: ${c['name']}', () async {
      final ws = (c['windows']! as List)
          .map(
            (w) => WakeWindow(
              endSample: _samples((w as List)[0] as num),
              embedding: Float32List(2),
              modelScore: (w[1] as num?)?.toDouble(),
            ),
          )
          .toList();
      final e = CandidateWakeEngine(
        features: _Scripted(ws),
        modelThreshold: (rule['lower']! as num).toDouble(),
        directThreshold: (rule['upper']! as num).toDouble(),
        refractory: Duration(milliseconds: rule['refractory_ms']! as int),
        holdDuration: Duration(milliseconds: rule['hold_ms']! as int),
      );
      await e.open([KeywordSpec.wendelin]);
      final hits = <WakeWordHit>[];
      for (var i = 0; i < ws.length; i++) {
        hits.addAll(await e.accept(Int16List(10)));
      }
      final want = (c['events']! as List).cast<Map<String, Object?>>();
      expect(
        [
          for (final h in hits)
            (h.endSample, h.score!.toStringAsFixed(4), h.direct),
        ],
        [
          for (final w in want)
            (
              _samples(w['t_ms']! as num),
              (w['score']! as num).toStringAsFixed(4),
              w['direct']! as bool,
            ),
        ],
      );
    });
  }
}
