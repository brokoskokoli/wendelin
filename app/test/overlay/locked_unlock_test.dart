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
import 'package:wendelin_voice/fakes.dart';
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

// Legal lifecycle paths (the listener asserts the order).
void _leave(TestWidgetsFlutterBinding b, {bool paused = true}) {
  b
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  if (paused) b.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _back(TestWidgetsFlutterBinding b) {
  b
    ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
    ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
    ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

void main() {
  late FakeLlmProvider llm;
  late TestEnv env;
  late FakeAssistantPlatform platform;
  late FakeTextToSpeech tts;

  setUp(() {
    llm = FakeLlmProvider([ScriptedTurn.text('Es ist zehn Uhr.')]);
    env = TestEnv(providerConfig: scripted(llm), enabled: const {'memory'});
    platform = FakeAssistantPlatform()..locked = true;
    tts = FakeTextToSpeech();
  });

  Future<ProviderContainer> open(WidgetTester tester) async {
    final c = await pumpOverlay(
      tester,
      env,
      platform,
      voice: fakeVoice(
        script: const [Transcript(text: 'Wie spät ist es', language: 'de')],
        tts: tts,
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
    expect(
      tts.spoken.any((t) => t.contains('Es ist zehn Uhr.')),
      isTrue,
      reason: 'die Antwort wird vorgelesen wie eine Sprachantwort',
    );
    expect(platform.finished, 0, reason: 'Overlay bleibt offen');
    expect(c.read(lockedPendingProvider), isNull);
    expect(c.read(lockedModeProvider), isFalse);
    expect(c.read(lockedExchangeProvider), isNull, reason: 'WP163: Entsperren');
  });

  testWidgets('Vor dem Entsperren: kein Modellaufruf, keine Antwort sichtbar', (
    tester,
  ) async {
    platform.unlockGate = Completer<bool>();
    final c = await open(tester);
    expect(platform.unlockRequests, 1);
    expect(llm.requests, isEmpty);
    expect(find.textContaining('Uhr'), findsNothing);
    // WP163: die Anfrage ist gesperrt sichtbar, der Antwortinhalt nicht.
    expect(find.textContaining('spät'), findsOneWidget);
    expect(c.read(lockedPendingProvider)?.text, 'Wie spät ist es');
    // WP163: gesperrt halten Anfrage und gesprochener Satz im Speicher.
    final ex = c.read(lockedExchangeProvider);
    expect(ex?.request, 'Wie spät ist es');
    expect(ex?.answer, 'Bitte entsperre das Telefon.');
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
      _leave(binding);
      await platform.closeHandler!();
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      expect(platform.finished, 0);
      _back(binding);
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

    testWidgets('Home in der Frist, Entsperren klappt: schließt, kein Zuhören '
        'und keine Anfrage', (tester) async {
      final c = await locked(tester);
      final binding = tester.binding;
      _leave(binding);
      platform.unlockGate!.complete(true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(llm.requests, isEmpty, reason: 'unsichtbar: nichts senden');
      expect(c.read(voiceControllerProvider).active, isFalse);
      await tester.pump(unlockGrace + const Duration(milliseconds: 100));
      await tester.pump();
      expect(platform.finished, 1, reason: 'nach der Frist neu geprüft');
      expect(llm.requests, isEmpty);
      expect(c.read(lockedPendingProvider), isNull);
    });

    testWidgets('Home in der Frist nach dem Entsperren: schließt nach der '
        'Frist', (tester) async {
      final c = await locked(tester);
      final binding = tester.binding;
      platform.unlockGate!.complete(true);
      await _settle(tester, c);
      _leave(binding);
      await platform.closeHandler!();
      await tester.pump();
      expect(platform.finished, 0, reason: 'in der Frist ignoriert');
      await tester.pump(unlockGrace + const Duration(milliseconds: 100));
      await tester.pump();
      expect(platform.finished, 1, reason: 'danach nachgeholt');
    });

    testWidgets('Home in der Frist, dann zurück: die Anfrage läuft sofort, '
        'ohne die Frist abzuwarten', (tester) async {
      final c = await locked(tester);
      final binding = tester.binding;
      _leave(binding);
      platform.unlockGate!.complete(true);
      await tester.pump(const Duration(milliseconds: 100));
      expect(llm.requests, isEmpty, reason: 'unsichtbar: nichts senden');
      _back(binding);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      expect(llm.requests, hasLength(1), reason: 'nicht bis zum Fristende');
      expect(platform.finished, 0);
      await _settle(tester, c);
    });

    testWidgets('Keyguard-Aufblitzen (hidden, dann resumed) bricht die '
        'laufende Anfrage nicht ab', (tester) async {
      llm = FakeLlmProvider([
        ScriptedTurn.text('Es ist zehn Uhr.'),
      ], eventDelay: const Duration(milliseconds: 400));
      env = TestEnv(providerConfig: scripted(llm), enabled: const {'memory'});
      final c = await locked(tester);
      final binding = tester.binding;
      platform.unlockGate!.complete(true);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        if (c.read(agentControllerProvider).running) break;
      }
      expect(c.read(agentControllerProvider).running, isTrue);
      _leave(binding, paused: false);
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester, c);
      expect(find.textContaining('Es ist zehn Uhr.'), findsOneWidget);
      expect(platform.finished, 0);
    });

    testWidgets('Entsperren in der Frist nach einem Abbruch wirkt', (
      tester,
    ) async {
      platform.unlockSucceeds = false;
      await open(tester);
      expect(platform.unlockRequests, 1);
      await tester.tap(find.text(AppLocalizationsDe().overlayUnlock));
      await tester.pump();
      expect(platform.unlockRequests, 2);
    });

    testWidgets('gemerkte Anfrage wird beim Schließen verworfen', (
      tester,
    ) async {
      platform.unlockSucceeds = false;
      final c = await open(tester);
      env.clock.advance(unlockGrace);
      c.read(lockedPendingProvider.notifier).keep('vertraulich');
      expect(c.read(lockedPendingProvider), isNotNull);
      await platform.closeHandler!();
      await tester.pump();
      expect(c.read(lockedPendingProvider), isNull);
    });
  });

  testWidgets('WP163: gesperrte Anfrage und Antwort werden beim Schließen '
      'verworfen', (tester) async {
    platform.unlockSucceeds = false;
    final c = await open(tester);
    env.clock.advance(unlockGrace);
    expect(c.read(lockedExchangeProvider), isNotNull);
    await platform.closeHandler!();
    await tester.pump();
    expect(c.read(lockedExchangeProvider), isNull);
  });

  group('UnlockWatch.visibleAfterUnlock', () {
    testWidgets('sichtbar: sofort true', (tester) async {
      final w = UnlockWatch(env.clock);
      expect(await w.visibleAfterUnlock(() => true), isTrue);
    });

    testWidgets('unsichtbar, kommt zurück: true vor Ablauf der Frist', (
      tester,
    ) async {
      final w = UnlockWatch(env.clock);
      _leave(tester.binding);
      bool? seen;
      unawaited(w.visibleAfterUnlock(() => true).then((v) => seen = v));
      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, isNull);
      _back(tester.binding);
      w.resumed(); // the overlay reports it from its lifecycle callback
      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, isTrue, reason: 'nicht die volle Frist abwarten');
    });

    testWidgets('unsichtbar bis zum Ablauf der Frist: false', (tester) async {
      final w = UnlockWatch(env.clock);
      _leave(tester.binding);
      bool? seen;
      unawaited(w.visibleAfterUnlock(() => true).then((v) => seen = v));
      await tester.pump(unlockGrace + const Duration(milliseconds: 100));
      expect(seen, isFalse);
      _back(tester.binding);
    });

    testWidgets('Overlay weg während des Wartens: false', (tester) async {
      final w = UnlockWatch(env.clock);
      _leave(tester.binding);
      var mounted = true;
      bool? seen;
      unawaited(w.visibleAfterUnlock(() => mounted).then((v) => seen = v));
      await tester.pump(const Duration(milliseconds: 100));
      _back(tester.binding);
      mounted = false;
      w.resumed();
      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, isFalse);
    });
  });
}
