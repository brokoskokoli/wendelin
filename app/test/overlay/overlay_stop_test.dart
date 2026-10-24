// WP31 (B5): „Stopp“ im Overlay blendet den alten Austausch aus, zeigt
// „Abgebrochen.“ und schließt das Overlay (Einstellung).
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../screens/main_screen_test.dart' show pumpUntil;
import '../support/test_env.dart';
import '../voice/voice_controller_test.dart' show fakeVoice;
import 'assistant_overlay_test.dart'
    show FakeAssistantPlatform, overlaySample, pumpOverlay;

Future<FakeAssistantPlatform> _stop(WidgetTester tester) async {
  AssistantOverlayScreen.stopCloseDelay = const Duration(milliseconds: 300);
  addTearDown(
    () => AssistantOverlayScreen.stopCloseDelay = const Duration(
      milliseconds: 1200,
    ),
  );
  final env = TestEnv(providerConfig: scripted(FakeLlmProvider(const [])));
  final platform = FakeAssistantPlatform();
  final c = await pumpOverlay(
    tester,
    env,
    platform,
    autoStart: false,
    voice: fakeVoice(script: const [Transcript(text: 'Stopp')]),
  );
  c.read(agentControllerProvider.notifier).seed(overlaySample());
  await c.read(voiceSettingsProvider.future);
  await c.read(voiceSettingsProvider.notifier).set(const VoiceSettings());
  await tester.pump();
  expect(find.text('„Trag mir morgen um zehn Tauchen ein.“'), findsOneWidget);
  platform.trigger();
  await pumpUntil(tester, find.text('Abgebrochen.'));
  return platform;
}

void main() {
  testWidgets('Stopp: alter Austausch weg, „Abgebrochen.“, Overlay schließt', (
    tester,
  ) async {
    final platform = await _stop(tester);
    expect(find.textContaining('Tauchen'), findsNothing);
    expect(find.text('Rückgängig · 8 s'), findsNothing);
    expect(platform.finished, 0);
    for (var i = 0; i < 20 && platform.finished == 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(platform.finished, 1);
  });

  testWidgets('Schließen: Teardown des Containers vor finish (WP145)', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform();
    final order = <String>[];
    AssistantOverlayScreen.tearDownEngine = (_, _) async =>
        order.add('teardown finished=${platform.finished}');
    await pumpOverlay(
      tester,
      TestEnv(providerConfig: scripted(FakeLlmProvider(const []))),
      platform,
    );
    await platform.closeHandler!();
    await tester.pump();
    expect(order, ['teardown finished=0']);
    expect(platform.finished, 1);
  });
}
