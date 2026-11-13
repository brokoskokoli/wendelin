// WP195 part 2: stop tone and hint when nothing was heard.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/di/wake_settings.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'voice_controller_test.dart' show fakeVoice, waitVoice;

void main() {
  late ProviderContainer c;
  var tones = 0;

  /// [silent]: only silence (nothing heard); otherwise speech whose
  /// transcript is empty (heard, not understood).
  Future<void> run({required bool silent, bool toneOn = true}) async {
    final voice = silent
        ? VoiceComponents(
            audio: FakeAudioInput(
              frames: List.generate(100, (_) => AudioFrames.silence()),
              frameInterval: const Duration(milliseconds: 30),
            ),
            vad: FakeVoiceActivityDetector(),
            stt: FakeSpeechToText(const []),
            textToSpeech: (_) async => null,
            config: const VoicePipelineConfig(
              firstNoSpeechTimeout: Duration(milliseconds: 300),
              listenGrace: Duration(milliseconds: 100),
            ),
          )
        : fakeVoice(script: const [Transcript(text: '')]);
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([])),
      extraOverrides: [
        activeVoiceProvider.overrideWith((ref) async => voice),
        stopToneProvider.overrideWithValue(() async => tones++),
      ],
    );
    await env.storage.settings.set(wakeToneKey, toneOn);
    c = env.container();
    c.read(voiceControllerProvider);
    await c
        .read(voiceControllerProvider.notifier)
        .start(TriggerKind.pushToTalk);
    await c.read(voiceControllerProvider.notifier).whenIdle;
    // The tone is fire-and-forget behind the setting read.
    await pumpEventQueue();
  }

  setUp(() => tones = 0);
  tearDown(() => c.dispose());

  test('nichts gehört: genau ein Stopp-Ton und der Hinweis', () async {
    await run(silent: true);
    expect(tones, 1);
    final v = await waitVoice(c, (v) => v.hint != null);
    expect(v.hint, voiceNothingHeardHint);
  });

  test('Bestätigungston aus: nichts gehört bleibt ganz still', () async {
    await run(silent: true, toneOn: false);
    expect(tones, 0);
  });

  test('gesprochen, aber nichts verstanden: kein Stopp-Ton', () async {
    await run(silent: false);
    expect(tones, 0);
    final hint = c.read(voiceControllerProvider).hint;
    expect(hint, isNotNull);
    expect(hint, isNot(voiceNothingHeardHint));
  });
}
