// WP194: the overlay shows „Ich höre zu“ once the microphone delivers audio.

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';

import '../support/test_env.dart';
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

void main() {
  testWidgets('Overlay: Mikrofon liefert Ton beim Laden -> „Ich höre zu“, '
      'ohne Ton „Moment …“ (WP194)', (tester) async {
    final platform = FakeAssistantPlatform();
    final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
    final c = await pumpOverlay(tester, env, platform, autoStart: false);
    final voice = c.read(voiceControllerProvider.notifier);
    MicState mic() => tester.widget<MicButton>(find.byType(MicButton)).state;

    voice.seed(const VoiceUiState(preparing: true));
    await tester.pump();
    expect(find.text('Moment …'), findsWidgets);
    expect(mic(), MicState.preparing);

    voice.seed(const VoiceUiState(preparing: true, micLive: true));
    await tester.pump();
    expect(find.text('Moment …'), findsNothing);
    expect(find.text('Ich höre zu …'), findsOneWidget);
    expect(mic(), MicState.listening);
    expect(c.read(voiceControllerProvider).active, isTrue);
  });
}
