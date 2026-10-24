// WP31 (B5): „Stopp“ im Overlay blendet den alten Austausch aus, zeigt
// „Abgebrochen.“ und schließt das Overlay (Einstellung).
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/voice_providers.dart';
import 'package:wendelin/ui/overlay/assistant_overlay.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../screens/main_screen_test.dart' show pumpUntil;
import '../support/test_env.dart';
import '../voice/voice_controller_test.dart' show fakeVoice, utterance;
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

  // Every way to close takes the same path (WP145): release the host first,
  // then the teardown, then tell the host it may destroy the engine.
  testWidgets('Schließen: Host frei, Teardown, dann teardownDone', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform();
    AssistantOverlayScreen.tearDownEngine = (_, _) async =>
        platform.calls.add('teardown');
    await pumpOverlay(
      tester,
      TestEnv(providerConfig: scripted(FakeLlmProvider(const []))),
      platform,
    );
    await platform.closeHandler!();
    await tester.pump();
    expect(platform.calls, ['releaseHost', 'teardown', 'teardownDone']);
  });

  testWidgets('Stopp: derselbe Schließweg', (tester) async {
    final platform = await _stop(tester);
    AssistantOverlayScreen.tearDownEngine = (_, _) async =>
        platform.calls.add('teardown');
    for (var i = 0; i < 20 && !platform.calls.contains('teardownDone'); i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(platform.calls, ['releaseHost', 'teardown', 'teardownDone']);
  });

  // The wake word service listens again as soon as the host is released: the
  // overlay's microphone must be closed by then (mic stop before releaseHost).
  testWidgets('Mikrofon ist beim Freigeben des Hosts schon zu', (tester) async {
    final platform = FakeAssistantPlatform();
    final audio = FakeAudioInput(
      frames: utterance(),
      frameInterval: const Duration(seconds: 30),
    );
    int? stopsAtRelease;
    int? startsAtRelease;
    platform.onReleaseHost = () {
      stopsAtRelease = audio.stopCount;
      startsAtRelease = audio.startCount;
    };
    await pumpOverlay(
      tester,
      TestEnv(providerConfig: scripted(FakeLlmProvider(const []))),
      platform,
      voice: fakeVoice(audio: audio),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(audio.startCount, 1, reason: 'Mikrofon war offen');
    await platform.closeHandler!();
    await tester.pump();
    expect(startsAtRelease, 1);
    expect(stopsAtRelease, 1, reason: 'Mikrofon zu, bevor der Host frei wird');
  });

  testWidgets('Host kann nicht halten: Teardown, dann finish', (tester) async {
    final platform = FakeAssistantPlatform()..canRelease = false;
    await pumpOverlay(
      tester,
      TestEnv(providerConfig: scripted(FakeLlmProvider(const []))),
      platform,
    );
    await platform.closeHandler!();
    await tester.pump();
    expect(platform.calls, ['releaseHost', 'finish']);
  });
}
