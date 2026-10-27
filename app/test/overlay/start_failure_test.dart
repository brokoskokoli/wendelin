// WP158 (finding 7): errors on the way to the microphone must not leave the
// wake word service recording, and the overlay must not crash.

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/testing.dart';

import '../support/test_env.dart';
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

FakeAssistantPlatform wakeHit() => FakeAssistantPlatform()
  ..wakeHandoff = AudioFrames.speech(const Duration(milliseconds: 600))
  ..wakeEnd = 600 * 16;

TestEnv quietEnv() => TestEnv(
  providerConfig: scripted(FakeLlmProvider([ScriptedTurn.text('x')])),
);

void main() {
  testWidgets('isLocked wirft beim Wake-Treffer: gesperrt angenommen, Dienst '
      'gibt das Mikrofon ab', (tester) async {
    final platform = wakeHit()..lockError = PlatformException(code: 'boom');
    final c = await pumpOverlay(tester, quietEnv(), platform);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    expect(platform.wakeTakes, greaterThanOrEqualTo(1));
    expect(platform.wakeHandoff, isNull);
    expect(c.read(lockedModeProvider), isTrue, reason: 'fail-closed');
    await c.read(voiceControllerProvider.notifier).cancel();
  });

  testWidgets('Mikrofon-Berechtigung wirft beim Wake-Treffer: Fehler, Dienst '
      'gibt das Mikrofon ab', (tester) async {
    final platform = wakeHit();
    final env = quietEnv()
      ..microphone.permissionError = PlatformException(code: 'boom');
    final c = await pumpOverlay(tester, env, platform);
    await tester.pump(const Duration(milliseconds: 60));
    expect(tester.takeException(), isNull);
    expect(platform.wakeTakes, greaterThanOrEqualTo(1));
    expect(platform.wakeHandoff, isNull);
    final v = c.read(voiceControllerProvider);
    expect(v.active, isFalse);
    expect(v.preparing, isFalse);
    expect(v.error, isNotNull);
  });

  testWidgets(
    'Übernahme der Übergabe wirft: Dienst wird trotzdem freigegeben',
    (tester) async {
      final platform = wakeHit();
      platform.onTake = () {
        if (platform.wakeTakes == 1) throw PlatformException(code: 'boom');
      };
      await pumpOverlay(tester, quietEnv(), platform);
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.takeException(), isNull);
      expect(platform.wakeTakes, 2, reason: 'zweiter Versuch gibt frei');
      expect(platform.wakeFinishes, 1, reason: 'Übergabe sofort beendet');
      expect(platform.wakeHandoff, isNull);
    },
  );

  // The trigger path (and with it the lock check, `_typing = false` and the
  // close timer) is not taken while a request still runs. A typed request
  // with an open keyboard cannot be combined with the locked state in the UI,
  // so the lock checks are counted instead (WP153 follow-up).
  testWidgets('Entsperren bei laufender Anfrage: kein neuer Trigger', (
    tester,
  ) async {
    final platform = FakeAssistantPlatform()..locked = true;
    final c = await pumpOverlay(tester, quietEnv(), platform, autoStart: false);
    await tester.pump();
    c
        .read(agentControllerProvider.notifier)
        .seed(ConversationState(running: true));
    final before = platform.lockChecks;
    await tester.tap(find.text('Entsperren'));
    await tester.pump(const Duration(milliseconds: 60));
    expect(platform.unlockRequests, 1);
    expect(platform.lockChecks, before, reason: 'kein _onTrigger');
  });
}
