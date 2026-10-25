import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

void main() {
  group('Sprachmodelle im Overlay (B11/B14)', () {
    late int warm;
    late int released;
    VoiceComponents counting() => VoiceComponents(
      audio: FakeAudioInput(),
      vad: FakeVoiceActivityDetector(),
      stt: FakeSpeechToText(const []),
      textToSpeech: (_) async => null,
      config: const VoicePipelineConfig(),
      warmUp: () async => warm++,
      release: () async => released++,
    );
    setUp(() {
      warm = 0;
      released = 0;
    });

    testWidgets('Schließen gibt die Modelle frei', (tester) async {
      final platform = FakeAssistantPlatform();
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      await pumpOverlay(
        tester,
        env,
        platform,
        autoStart: false,
        voice: counting(),
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Beenden'));
      await tester.pump();
      await tester.pump();
      expect(released, 1);
      expect(platform.finished, 1);
    });

    testWidgets('gesperrt: Modell nur für das Zuhören geladen (WP53)', (
      tester,
    ) async {
      final platform = FakeAssistantPlatform()
        ..locked = true
        ..unlockSucceeds = false;
      final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
      final c = await pumpOverlay(tester, env, platform, voice: counting());
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        find.text(AppLocalizationsDe().overlayLockedTitle),
        findsOneWidget,
      );
      expect(warm, 1, reason: 'einmal, beim Zuhören (Whisper lokal)');

      platform.unlockSucceeds = true;
      await tester.tap(find.text('Entsperren'));
      await tester.pump(const Duration(milliseconds: 10));
      expect(warm, greaterThan(0), reason: 'entsperrt: vorwärmen');
      await c.read(voiceControllerProvider.notifier).cancel();
    });
  });
}
