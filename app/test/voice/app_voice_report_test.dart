// WP146: the voice controller tells the wake-word service when the app
// records or is about to, so the service does not open its microphone next to
// it (two VOICE_RECOGNITION recordings degrade the app's audio).

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/platform/assistant_platform.dart';
import 'package:wendelin/voice/app_voice_reporter.dart';
import 'package:wendelin/voice/voice_components.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../overlay/assistant_overlay_test.dart' show FakeAssistantPlatform;
import '../support/test_env.dart';

void main() {
  late ProviderContainer c;
  late FakeAssistantPlatform platform;

  setUp(() {
    platform = FakeAssistantPlatform();
    final audio = FakeAudioInput(
      frames: AudioFrames.pattern('S' * 10 + '.' * 40),
      frameInterval: const Duration(milliseconds: 30),
    );
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('Sonnig.')])),
      extraOverrides: [
        voiceReadyProvider.overrideWithValue(true),
        audioInputProvider.overrideWithValue(audio),
        assistantPlatformProvider.overrideWithValue(platform),
        activeVoiceProvider.overrideWith(
          (ref) async => VoiceComponents(
            audio: audio,
            vad: FakeVoiceActivityDetector(),
            stt: FakeSpeechToText([
              Transcript(text: 'Wetter?', language: 'de'),
            ]),
            textToSpeech: (_) async => null,
            config: const VoicePipelineConfig(),
          ),
        ),
      ],
    );
    c = env.container();
  });
  tearDown(() => c.dispose());

  VoiceController voice() => c.read(voiceControllerProvider.notifier);

  test(
    'Anfrage: aktiv beim Start, frei nach dem Ende (nur Wechsel gemeldet)',
    () async {
      c.read(voiceControllerProvider);
      expect(await voice().start(TriggerKind.pushToTalk), isTrue);
      expect(platform.appVoice.first, isTrue);
      expect(platform.appVoice.last, isTrue);
      await voice().whenIdle;
      await voice().cancel();
      expect(platform.appVoice.last, isFalse);
      // Only changes are reported, never the same value twice in a row.
      for (var i = 1; i < platform.appVoice.length; i++) {
        expect(platform.appVoice[i], isNot(platform.appVoice[i - 1]));
      }
    },
  );

  test('Abbruch während der Vorbereitung meldet frei', () async {
    c.read(voiceControllerProvider);
    final started = voice().start(TriggerKind.pushToTalk);
    await voice().cancel();
    await started;
    await voice().whenIdle;
    expect(platform.appVoice.last, isFalse);
    expect(platform.appVoice.where((b) => b).length, lessThanOrEqualTo(1));
  });

  test('Dispose während der Aufnahme meldet frei', () async {
    c.read(voiceControllerProvider);
    await voice().start(TriggerKind.pushToTalk);
    expect(platform.appVoice.last, isTrue);
    c.dispose();
    expect(platform.appVoice.last, isFalse);
    // tearDown disposes again: harmless.
  });

  test('Folgefenster (inaktiv, aber offen) meldet aktiv, Ende meldet frei', () {
    final reporter = AppVoiceReporter(platform);
    final until = DateTime.utc(2026, 10, 25, 12);
    reporter
      ..update(const VoiceUiState(preparing: true))
      // The follow-up window between two recordings: not `active`, but the
      // next recording follows (WP146, wake-resume between them).
      ..update(
        VoiceUiState(
          followUpUntil: until,
          followUpWindow: const Duration(seconds: 5),
        ),
      );
    expect(platform.appVoice, [true]);
    reporter.update(const VoiceUiState());
    expect(platform.appVoice, [true, false]);
    reporter.dispose();
    expect(platform.appVoice, [true, false]);
  });

  test('solange die App beschäftigt ist, wird "aktiv" wiederholt (Obergrenze '
      'im Dienst); danach nicht mehr', () {
    fakeAsync((async) {
      final reporter = AppVoiceReporter(platform)
        ..update(const VoiceUiState(preparing: true));
      expect(platform.appVoice, [true]);
      async.elapse(AppVoiceReporter.heartbeat * 3);
      expect(platform.appVoice, [true, true, true, true]);
      reporter.update(const VoiceUiState());
      async.elapse(AppVoiceReporter.heartbeat * 3);
      expect(platform.appVoice, [true, true, true, true, false]);
    });
  });
}
