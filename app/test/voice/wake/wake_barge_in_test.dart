import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_providers.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/wake/wake_barge_in.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../../support/test_env.dart';

WakeTemplates tpl(double threshold) => WakeTemplates(
  speakerId: 'a',
  featureVersion: 'fake-1',
  threshold: threshold,
  embeddings: [
    Float32List.fromList([1, 0]),
  ],
);

void main() {
  group('LazyWakeBargeInDetector', () {
    late FakeAudioInput audio;

    LazyWakeBargeInDetector make(List<WakeTemplates> sets, Float32List e) {
      audio = FakeAudioInput(
        frames: [Int16List(480), Int16List(480)],
        frameInterval: const Duration(milliseconds: 5),
      );
      return LazyWakeBargeInDetector(
        audio: audio,
        templates: () async => sets,
        features: () => FakeWakeFeatureExtractor(
          windowEvery: 480,
          windowFor: (end, _) => WakeWindow(endSample: end, embedding: e),
        ),
      );
    }

    test('„Wendelin“ während der Sprachausgabe: Signal wake', () async {
      final d = make([tpl(0.9)], Float32List.fromList([1, 0]));
      final signals = <BargeInSignal>[];
      d.signals.listen(signals.add);
      await d.start();
      expect(d.isRunning, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(signals.first.keyword, BargeInKeyword.wake);
      await d.stop();
      expect(d.isRunning, isFalse);
      expect(audio.isRunning, isFalse);
      await d.dispose();
    });

    test('strenger als im Leerlauf: Schwelle + 0,05', () async {
      // Similarity 0.93 passes 0.9 but not 0.9 + 0.05.
      final d = make([tpl(0.9)], Float32List.fromList([0.93, 0.3676]));
      final signals = <BargeInSignal>[];
      d.signals.listen(signals.add);
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(signals, isEmpty);
      await d.dispose();
    });

    test('nichts eingelernt: still, mit Logzeile', () async {
      final lines = <String>[];
      final saved = voiceLogSink;
      voiceLogSink = lines.add;
      addTearDown(() => voiceLogSink = saved);
      final d = make([], Float32List.fromList([1, 0]));
      await d.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(audio.isRunning, isFalse);
      expect(lines.join(), contains('barge-in-off'));
      await d.stop();
      await d.dispose();
    });
  });

  group('wakeBargeInDetectorProvider', () {
    test('null ohne Gesprächsmodus, sonst ein Detektor', () async {
      final env = TestEnv();
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(voiceSettingsProvider.future);
      expect(c.read(wakeBargeInDetectorProvider), isNull);
      await env.storage.settings.set(
        voiceSettingsKey,
        const VoiceSettings(conversationMode: true),
      );
      final c2 = env.container();
      addTearDown(c2.dispose);
      await c2.read(voiceSettingsProvider.future);
      expect(c2.read(wakeBargeInDetectorProvider), isA<BargeInDetector>());
    });
  });
}
