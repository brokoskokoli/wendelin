// WP195 round 1: at „nothing heard“ the overlay stays until the stop tone has
// played and the hint was visible (the teardown stops the player).
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin/voice/voice_log.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

void main() {
  late void Function(String) savedSink;
  setUp(() {
    AssistantOverlayScreen.tearDownEngine = (_, _) async {};
    AssistantOverlayScreen.closeWhenIdle = true;
    savedSink = voiceLogSink;
  });
  tearDown(() => voiceLogSink = savedSink);

  testWidgets('nichts gehoert: Overlay schliesst erst nach dem Stopp-Ton, '
      'Hinweis sichtbar', (tester) async {
    final events = <String>[];
    var hintSeen = false;
    final platform = FakeAssistantPlatform();
    final env = TestEnv(
      providerConfig: scripted(FakeLlmProvider([])),
      stopTone: () async {
        events.add('tone-start');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        events.add('tone-end');
      },
    );
    final c = await pumpOverlay(
      tester,
      env,
      platform,
      autoStart: false,
      voice: VoiceComponents(
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
      ),
    );
    voiceLogSink = (l) {
      if (l.contains('overlay-close')) events.add('close');
    };
    platform.trigger();
    for (var i = 0; i < 100 && !events.contains('close'); i++) {
      await tester.pump(const Duration(milliseconds: 50));
      hintSeen |= find
          .text(AppLocalizationsDe().voiceNothingHeardHint)
          .evaluate()
          .isNotEmpty;
    }
    expect(c.read(voiceControllerProvider).phase, VoiceState.idle);
    expect(events, ['tone-start', 'tone-end', 'close']);
    expect(hintSeen, isTrue, reason: 'Hinweis im Overlay sichtbar');
  });
}
