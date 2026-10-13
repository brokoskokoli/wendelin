// Speech models on the main screen (WP30, B11/B14 and review): warmed up
// only for people who use speech, freed in the background, warmed up again
// on return.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin/voice/voice_usage.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'main_screen_test.dart' show pumpApp;

/// Counts what the screen asks of the speech models.
final class _Models {
  int loads = 0;
  int warm = 0;
  int released = 0;

  VoiceComponents build() {
    loads++;
    return VoiceComponents(
      audio: FakeAudioInput(),
      vad: FakeVoiceActivityDetector(),
      stt: FakeSpeechToText(const []),
      textToSpeech: (_) async => null,
      config: const VoicePipelineConfig(),
      warmUp: () async => warm++,
      release: () async => released++,
    );
  }
}

void main() {
  final lines = <String>[];
  late void Function(String) savedSink;
  setUp(() {
    lines.clear();
    savedSink = voiceLogSink;
    voiceLogSink = lines.add;
  });
  tearDown(() => voiceLogSink = savedSink);

  TestEnv env(_Models models) => TestEnv(
    extraOverrides: [
      voiceReadyProvider.overrideWithValue(true),
      activeVoiceProvider.overrideWith((ref) async => models.build()),
      voiceReleaseDelayProvider.overrideWithValue(const Duration(seconds: 1)),
    ],
  );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
  }

  void lifecycle(WidgetTester tester, List<AppLifecycleState> states) {
    for (final s in states) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  const toBackground = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ];
  const toForeground = [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  testWidgets('nur getippt: kein Vorwärmen (Grundlast)', (tester) async {
    final models = _Models();
    await pumpApp(tester, env(models));
    await settle(tester);
    expect(models.warm, 0);
    expect(models.loads, 0);
    expect(
      lines.any((l) => l.contains(' prewarm-skip ')),
      isTrue,
      reason: '$lines',
    );
  });

  testWidgets('Sprache vor mehr als 24 h: kein Vorwärmen', (tester) async {
    final models = _Models();
    final e = env(models);
    await tester.runAsync(
      () => e.storage.settings.set(
        voiceLastUseKey,
        testNow.subtract(const Duration(hours: 25)),
      ),
    );
    await pumpApp(tester, e);
    await settle(tester);
    expect(models.warm, 0);
  });

  testWidgets('Sprache genutzt: Vorwärmen, Freigabe im Hintergrund, '
      'zurück wärmt wieder vor', (tester) async {
    final models = _Models();
    final e = env(models);
    await tester.runAsync(
      () => e.storage.settings.set(
        voiceLastUseKey,
        testNow.subtract(const Duration(hours: 2)),
      ),
    );
    await pumpApp(tester, e);
    await settle(tester);
    expect(models.warm, 1);

    lifecycle(tester, toBackground);
    await settle(tester);
    expect(models.released, 0, reason: 'erst nach der Frist');
    await tester.pump(const Duration(seconds: 2));
    await settle(tester);
    expect(models.released, 1);

    lifecycle(tester, toForeground);
    await settle(tester);
    expect(models.warm, 2);
  });
}
