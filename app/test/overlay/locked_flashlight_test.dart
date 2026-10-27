// WP53 (K16): gesperrtes Gerät – nur die Taschenlampe, ohne Modell.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/integrations/integration_spec.dart';
import 'package:wendelin/di/integrations/registry.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../support/test_env.dart';
import '../voice/voice_controller_test.dart' show fakeVoice;
import 'assistant_overlay_test.dart'
    show FakeAssistantPlatform, overlaySample, pumpOverlay;

const _all = {'calendar', 'memory', 'flashlight'};

Future<void> _settle(WidgetTester tester, ProviderContainer c) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final v = c.read(voiceControllerProvider);
    if (i > 5 && !v.active && !v.preparing) break;
  }
  await c.read(voiceControllerProvider.notifier).whenIdle;
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  late FakeLlmProvider llm;
  late TestEnv env;

  setUp(() {
    llm = FakeLlmProvider(const []);
    env = TestEnv(providerConfig: scripted(llm), enabled: _all);
  });

  Future<(ProviderContainer, FakeAssistantPlatform, FakeTextToSpeech)> run(
    WidgetTester tester,
    String said, {
    bool unlockSucceeds = false,
  }) async {
    final platform = FakeAssistantPlatform()
      ..locked = true
      ..unlockSucceeds = unlockSucceeds;
    final tts = FakeTextToSpeech();
    final c = await pumpOverlay(
      tester,
      env,
      platform,
      voice: fakeVoice(
        script: [Transcript(text: said, language: 'de')],
        tts: tts,
      ),
    );
    c.read(agentControllerProvider.notifier).seed(overlaySample());
    await _settle(tester, c);
    return (c, platform, tts);
  }

  testWidgets('gesperrt + „Taschenlampe an“: Fake-Torch an, kein Modell', (
    tester,
  ) async {
    final (c, platform, tts) = await run(tester, 'Taschenlampe an');
    expect(env.torch.on, isTrue);
    expect(llm.requests, isEmpty);
    expect(tts.spoken.join(' '), 'Taschenlampe an.');
    expect(platform.unlockRequests, 0, reason: 'kein Entsperren nötig');
    // Audit: Tool-Aufruf mit Markierung „bei Sperre“, ohne Text.
    await c.read(auditRecorderProvider).flush();
    final log = await env.storage.audit.query();
    final call = log.singleWhere((e) => e.kind == AuditKind.toolCall);
    expect(call.payload['tool'], 'flashlight__on');
    expect(call.payload['whileLocked'], isTrue);
    expect(log.where((e) => e.kind == AuditKind.request), isEmpty);
    expect(log.toString(), isNot(contains('Taschenlampe an')));
  });

  testWidgets('gesperrt + „Taschenlampe aus“ schaltet aus', (tester) async {
    env.torch.on = true;
    await run(tester, 'Taschenlampe aus');
    expect(env.torch.on, isFalse);
    expect(llm.requests, isEmpty);
  });

  testWidgets('gesperrt + Nicht-Taschenlampe: Entsperr-Hinweis, kein Agent', (
    tester,
  ) async {
    final (c, platform, tts) = await run(tester, 'Wie spät ist es');
    expect(llm.requests, isEmpty, reason: 'kein Modellaufruf');
    expect(env.torch.on, isFalse);
    expect(tts.spoken.join(' '), 'Bitte entsperre das Telefon.');
    // Nichts im Verlauf außer dem (versteckten) Beispiel; keine neue Anfrage.
    final entries = c.read(agentControllerProvider).entries;
    expect(entries.length, overlaySample().entries.length);
    // Danach der bisherige Entsperr-Pfad (Äußerung verworfen).
    expect(platform.unlockRequests, 1);
    final log = await env.storage.audit.query();
    expect(log.where((e) => e.kind == AuditKind.toolCall), isEmpty);
    final refused = log.singleWhere((e) => e.kind == AuditKind.request);
    expect(refused.payload['refused'], isTrue);
    expect(refused.payload.containsKey('text'), isFalse);
    expect(log.toString(), isNot(contains('spät')));
  });

  testWidgets(
    'gesperrt: Sheet zeigt Anfrage, aber weder Verlauf noch Tool-Karte',
    (tester) async {
      final (c, _, _) = await run(tester, 'Was steht morgen im Kalender?');
      expect(find.text('Entsperren'), findsOneWidget);
      // Der Verlauf liegt im Agenten, wird gesperrt aber nicht gerendert.
      expect(c.read(agentControllerProvider).entries, isNotEmpty);
      expect(find.textContaining('Tauchen'), findsNothing);
      expect(find.byType(ToolResultCard), findsNothing);
      expect(llm.requests, isEmpty);
      expect(c.read(voiceControllerProvider).active, isFalse);
    },
  );

  testWidgets('gesperrt: Entsperren oben, darunter Anfrage und Antwort', (
    tester,
  ) async {
    await run(tester, 'Taschenlampe an');
    final button = find.text('Entsperren');
    final request = find.text('„Taschenlampe an“');
    final answer = find.text('Taschenlampe an.');
    expect(button, findsOneWidget);
    expect(request, findsOneWidget);
    expect(answer, findsOneWidget);
    expect(
      tester.getTopLeft(button).dy,
      lessThan(tester.getTopLeft(request).dy),
    );
    expect(
      tester.getTopLeft(request).dy,
      lessThan(tester.getTopLeft(answer).dy),
    );
    // Der alte pauschale Sperrtext ist weg.
    expect(find.textContaining('Auf dem Sperrbildschirm'), findsNothing);
    expect(find.textContaining('Gerät entsperren'), findsNothing);
  });

  testWidgets('gesperrt: Verweigerung zeigt nur den Entsperren-nötig-Satz', (
    tester,
  ) async {
    await run(tester, 'Wie spät ist es');
    expect(find.text('„Wie spät ist es“'), findsOneWidget);
    expect(find.text('Bitte entsperre das Telefon.'), findsOneWidget);
    expect(find.textContaining('Auf dem Sperrbildschirm'), findsNothing);
    expect(find.textContaining('Tauchen'), findsNothing);
  });

  testWidgets('Taschenlampen-Integration aus: Befehl wird nicht ausgeführt', (
    tester,
  ) async {
    env = TestEnv(providerConfig: scripted(llm), enabled: const {'memory'});
    final (_, _, tts) = await run(tester, 'Taschenlampe an');
    expect(env.torch.on, isFalse);
    expect(llm.requests, isEmpty);
    expect(tts.spoken.join(' '), 'Das hat nicht geklappt.');
  });

  testWidgets('Spec ohne allowedWhileLocked: Befehl wird nicht ausgeführt', (
    tester,
  ) async {
    env = TestEnv(
      providerConfig: scripted(llm),
      enabled: _all,
      extraOverrides: [
        integrationSpecsProvider.overrideWithValue([
          for (final s in builtInIntegrationSpecs)
            if (s.id == 'flashlight')
              IntegrationSpec(id: s.id, create: s.create)
            else
              s,
        ]),
      ],
    );
    final (_, _, tts) = await run(tester, 'Taschenlampe an');
    expect(env.torch.on, isFalse);
    expect(llm.requests, isEmpty);
    expect(tts.spoken.join(' '), 'Das hat nicht geklappt.');
  });

  testWidgets('einzeln abgeschaltetes Taschenlampen-Tool läuft nicht', (
    tester,
  ) async {
    env = TestEnv(
      providerConfig: scripted(llm),
      enabled: _all,
      startup: StartupSettings(
        enabledIntegrations: _all,
        toolPrefs: const ToolPrefs(disabled: {'flashlight__on'}),
      ),
    );
    final (_, _, tts) = await run(tester, 'Taschenlampe an');
    expect(env.torch.on, isFalse);
    expect(llm.requests, isEmpty);
    expect(tts.spoken.join(' '), 'Das hat nicht geklappt.');
  });

  testWidgets('Tool-Ergebnis mit Fehler: „Das hat nicht geklappt.“', (
    tester,
  ) async {
    env.torch.available = false;
    final (_, _, tts) = await run(tester, 'Taschenlampe an');
    expect(env.torch.on, isFalse);
    expect(tts.spoken.join(' '), 'Das hat nicht geklappt.');
  });

  testWidgets('entsperrt: normaler Agentenpfad', (tester) async {
    llm = FakeLlmProvider([ScriptedTurn.text('Es ist zehn.')]);
    env = TestEnv(providerConfig: scripted(llm), enabled: _all);
    final platform = FakeAssistantPlatform();
    final c = await pumpOverlay(
      tester,
      env,
      platform,
      voice: fakeVoice(
        script: const [Transcript(text: 'Wie spät ist es', language: 'de')],
      ),
    );
    await _settle(tester, c);
    expect(llm.requests, hasLength(1));
  });
}
