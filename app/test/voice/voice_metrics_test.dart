import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/voice/voice_metrics.dart';

VoiceMetric _m(int ms) => VoiceMetric(
  kind: VoiceMetricKind.stt,
  model: 'm',
  audio: const Duration(seconds: 2),
  compute: Duration(milliseconds: ms),
);

void main() {
  test('RTF ist Rechenzeit durch Audiozeit; ohne Audio 0', () {
    expect(_m(500).rtf, 0.25);
    expect(
      const VoiceMetric(
        kind: VoiceMetricKind.tts,
        model: 'm',
        audio: Duration.zero,
        compute: Duration(seconds: 1),
      ).rtf,
      0,
    );
  });

  test('Die Liste behält die letzten Einträge, neueste zuerst', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final log = c.read(voiceMetricsProvider.notifier);
    for (var i = 0; i < VoiceMetricsLog.capacity + 5; i++) {
      log.add(_m(i));
    }
    final list = c.read(voiceMetricsProvider);
    expect(list, hasLength(VoiceMetricsLog.capacity));
    expect(list.first.compute.inMilliseconds, VoiceMetricsLog.capacity + 4);
    log.clear();
    expect(c.read(voiceMetricsProvider), isEmpty);
  });
}
