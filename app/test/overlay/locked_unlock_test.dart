// WP114 (K85): Entsperren ist kein Tippen; die Anfrage von vor dem
// Entsperren läuft danach im Overlay weiter oder wird verworfen.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/overlay/unlock_window.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../voice/voice_controller_test.dart' show fakeVoice;
import 'assistant_overlay_test.dart' show FakeAssistantPlatform, pumpOverlay;

Future<void> _settle(WidgetTester tester, ProviderContainer c) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final v = c.read(voiceControllerProvider);
    final a = c.read(agentControllerProvider);
    if (i > 5 && !v.active && !v.preparing && !a.running) break;
  }
  await c.read(voiceControllerProvider.notifier).whenIdle;
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late FakeLlmProvider llm;
  late TestEnv env;
  late FakeAssistantPlatform platform;

  setUp(() {
    llm = FakeLlmProvider([ScriptedTurn.text('Es ist zehn Uhr.')]);
    env = TestEnv(providerConfig: scripted(llm), enabled: const {'memory'});
    platform = FakeAssistantPlatform()..locked = true;
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    final c = await pumpOverlay(
      tester,
      env,
      platform,
      voice: fakeVoice(
        script: const [Transcript(text: 'Wie spät ist es', language: 'de')],
      ),
    );
    await _settle(tester, c);
    return c;
  }

  testWidgets('Anfrage von vorher läuft nach dem Entsperren, Overlay bleibt', (
    tester,
  ) async {
    platform.unlockSucceeds = true;
    final c = await open(tester);
    expect(platform.unlockRequests, 1);
    expect(llm.requests, hasLength(1), reason: 'erst nach dem Entsperren');
    final entries = c.read(agentControllerProvider).entries;
    expect(entries.whereType<UserEntry>().single.text, 'Wie spät ist es');
    expect(find.textContaining('Es ist zehn Uhr.'), findsOneWidget);
    expect(platform.finished, 0, reason: 'Overlay bleibt offen');
    expect(c.read(lockedPendingProvider), isNull);
    expect(c.read(lockedModeProvider), isFalse);
  });

  testWidgets('Vor dem Entsperren: kein Modellaufruf, nichts sichtbar', (
    tester,
  ) async {
    platform.unlockGate = Completer<bool>();
    final c = await open(tester);
    expect(platform.unlockRequests, 1);
    expect(llm.requests, isEmpty);
    expect(find.textContaining('Uhr'), findsNothing);
    expect(find.textContaining('spät'), findsNothing);
    expect(c.read(lockedPendingProvider)?.text, 'Wie spät ist es');
    platform.unlockGate!.complete(false);
    await tester.pump();
  });

  testWidgets('Entsperren abgebrochen: Anfrage verworfen, Hinweis im Overlay', (
    tester,
  ) async {
    platform.unlockSucceeds = false;
    final c = await open(tester);
    expect(llm.requests, isEmpty);
    expect(c.read(lockedPendingProvider), isNull);
    expect(
      find.text(AppLocalizationsDe().overlayUnlockCancelled),
      findsOneWidget,
    );
    expect(platform.finished, 0);
  });

  testWidgets('zu alte Anfrage wird nicht ausgeführt (fail closed)', (
    tester,
  ) async {
    platform.unlockGate = Completer<bool>();
    final c = await open(tester);
    env.clock.advance(lockedPendingMaxAge + const Duration(seconds: 1));
    platform.unlockGate!.complete(true);
    await _settle(tester, c);
    expect(llm.requests, isEmpty);
    expect(c.read(lockedPendingProvider), isNull);
  });

  group('Entsperren ist kein Tippen', () {
    Future<ProviderContainer> locked(WidgetTester tester) async {
      platform.unlockGate = Completer<bool>();
      return open(tester);
    }

    testWidgets('Keyguard-Übergang schließt das Overlay nicht', (tester) async {
      final c = await locked(tester);
      // Während der Keyguard zu sehen ist: Lebenszyklus, Plattform-Schließen,
      // Tippen außerhalb des Sheets.
      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await platform.closeHandler!();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(platform.finished, 0);
      platform.unlockGate!.complete(true);
      await _settle(tester, c);
      // Kurz nach dem Ergebnis kommt dasselbe noch einmal (onStop).
      await platform.closeHandler!();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(platform.finished, 0, reason: 'Gnadenfrist nach dem Entsperren');
      expect(llm.requests, hasLength(1), reason: 'Anfrage lief weiter');
    });

    testWidgets('nach der Gnadenfrist schließt Tippen wieder', (tester) async {
      final c = await locked(tester);
      platform.unlockGate!.complete(true);
      await _settle(tester, c);
      env.clock.advance(unlockGrace);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump();
      expect(platform.finished, 1);
    });

    testWidgets(
      'Entsperren abgebrochen: Tippen schließt nach der Gnadenfrist',
      (tester) async {
        platform.unlockSucceeds = false;
        await open(tester);
        env.clock.advance(unlockGrace);
        await tester.tapAt(const Offset(20, 20));
        await tester.pump();
        await tester.pump();
        expect(platform.finished, 1);
      },
    );
  });
}
