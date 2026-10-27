// WP160 Analyse (kein Fix): warum ist HA-Licht gesperrt nicht steuerbar?
// Je Fall der Weg Befehlserkenner -> LockGateAgentRun -> lockedScopeProvider
// -> RiskPolicy/ToolExecutor -> ha__call/haDecide, mit dem echten Overlay.
// Erwartung je Test = ADR 0022 (L2/L3); ein roter Test zeigt eine Abweichung.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/di/locked_scope.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/voice/voice_controller.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../overlay/assistant_overlay_test.dart'
    show FakeAssistantPlatform, overlaySample, pumpOverlay;
import '../support/test_env.dart';
import 'voice_controller_test.dart' show fakeVoice;

const _lightDefault =
    '[{"id":"light.b","name":"Stehlampe"},{"id":"lock.d","name":"Haustür"}]';
const _lightA = '[{"id":"light.a","name":"Flurlicht","level":"a"}]';
const _lock = '[{"id":"lock.d","name":"Haustür"}]';

TestEnv _env(
  FakeLlmProvider llm,
  String entities, {
  Set<String> enabled = const {'flashlight', 'ha'},
  ToolPrefs prefs = const ToolPrefs(),
}) {
  final env = TestEnv(
    providerConfig: scripted(llm),
    startup: StartupSettings(enabledIntegrations: enabled, toolPrefs: prefs),
  );
  env.secrets
    ..write('ha.url', 'http://192.168.1.20:8123')
    ..write('ha.token', 'a' * 40)
    ..write('ha.entities', entities);
  for (final id in ['light.a', 'light.b', 'lock.d']) {
    env.ha.set(id, 'off', const {});
  }
  return env;
}

FakeLlmProvider _calls(String entity, String service) => FakeLlmProvider([
  ScriptedTurn.toolCalls([
    ToolCallBlock(
      id: '1',
      name: 'ha__call',
      argumentsJson: '{"entity":"$entity","service":"$service"}',
    ),
  ]),
  ScriptedTurn.text('Fertig.'),
]);

final _known = FakeSpeakerRecognizer(
  const SpeakerMatch.known(personId: 'p1', name: 'Anna', score: 0.8),
);

class _Run {
  _Run(this.container, this.platform, this.tts);
  final ProviderContainer container;
  final FakeAssistantPlatform platform;
  final FakeTextToSpeech tts;
}

Future<_Run> _say(
  WidgetTester tester,
  TestEnv env,
  String said, {
  SpeakerRecognizer? speaker,
}) async {
  // unlockSucceeds=false: sonst gelingt das Entsperren im Test und die
  // Anfrage läuft danach legitim ungesperrt (Fehler im ersten Aufbau).
  final platform = FakeAssistantPlatform()
    ..locked = true
    ..unlockSucceeds = false;
  final tts = FakeTextToSpeech();
  final c = await pumpOverlay(
    tester,
    env,
    platform,
    voice: fakeVoice(
      script: [Transcript(text: said, language: 'de')],
      tts: tts,
      speaker: speaker,
    ),
  );
  c.read(agentControllerProvider.notifier).seed(overlaySample());
  for (var i = 0; i < 800; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final v = c.read(voiceControllerProvider);
    if (i > 5 && !v.active && !v.preparing) break;
  }
  await c.read(voiceControllerProvider.notifier).whenIdle;
  await tester.pump(const Duration(milliseconds: 50));
  return _Run(c, platform, tts);
}

void main() {
  group('Licht gesperrt: Ende-zu-Ende über das Overlay', () {
    testWidgets('1a Licht ohne Stufe (Standard B), ohne Stimme: verweigert, '
        'kein Modelllauf (ADR: Entsperren nötig)', (tester) async {
      final llm = _calls('light.b', 'turn_on');
      final env = _env(llm, _lightDefault);
      final r = await _say(tester, env, 'Stehlampe an');
      expect(env.ha.calls, isEmpty);
      expect(llm.requests, isEmpty, reason: 'Umfang null: nur Lampe < Modell');
      expect(r.tts.spoken.join(' '), 'Bitte entsperre das Telefon.');
      expect(r.platform.unlockRequests, 1);
    });

    testWidgets('1b Licht ohne Stufe (B), erkannte Stimme: läuft', (
      tester,
    ) async {
      final llm = _calls('light.b', 'turn_on');
      final env = _env(llm, _lightDefault);
      final r = await _say(tester, env, 'Stehlampe an', speaker: _known);
      expect(env.ha.calls.map((x) => x.service), ['turn_on']);
      expect(r.platform.unlockRequests, 0);
    });

    testWidgets('2 Licht explizit A, ohne Stimme: läuft', (tester) async {
      final llm = _calls('light.a', 'turn_on');
      final env = _env(llm, _lightA);
      final r = await _say(tester, env, 'Flurlicht an');
      expect(env.ha.calls.map((x) => x.service), ['turn_on']);
      expect(r.platform.unlockRequests, 0);
    });

    testWidgets('3a Licht A + altes „Immer bestätigen“ (D) auf ha__call: '
        'bleibt gesperrt (ADR: strengere gewinnt)', (tester) async {
      final llm = _calls('light.a', 'turn_on');
      final env = _env(
        llm,
        _lightA,
        prefs: const ToolPrefs(alwaysConfirm: {'ha__call'}),
      );
      final r = await _say(tester, env, 'Flurlicht an');
      expect(env.ha.calls, isEmpty);
      expect(llm.requests, isEmpty);
      expect(r.platform.unlockRequests, 1);
    });

    testWidgets('3b Licht A + gespeicherte Stufe D auf ha__call (levels): '
        'wird ignoriert, Licht läuft (Tool-Stufe gilt für ha__call nicht)', (
      tester,
    ) async {
      final llm = _calls('light.a', 'turn_on');
      final env = _env(
        llm,
        _lightA,
        prefs: const ToolPrefs(levels: {'ha__call': 'd'}),
      );
      await _say(tester, env, 'Flurlicht an');
      expect(env.ha.calls.map((x) => x.service), ['turn_on']);
    });

    testWidgets('4 Licht A, nur HA aktiv (keine Taschenlampe): Modelllauf '
        'kommt, Tools = nur ha__call, Prompt nur Geräte auf A', (tester) async {
      final llm = _calls('light.a', 'turn_on');
      final env = _env(
        llm,
        '[{"id":"light.a","name":"Flurlicht","level":"a"},'
        '{"id":"light.b","name":"Stehlampe"}]',
        enabled: const {'ha'},
      );
      await _say(tester, env, 'Flurlicht an');
      expect(llm.requests, isNotEmpty);
      expect([for (final t in llm.requests.first.tools) t.name], ['ha__call']);
      final prompt = llm.requests.first.systemPrompt ?? '';
      // Der Prompt nennt die Entity-Id (Anzeigename kommt aus dem
      // HA-Zustand, im Fake leer): Filter nach Stufe A wirkt.
      expect(prompt, contains('light.a'));
      expect(prompt, isNot(contains('light.b')));
      expect(env.ha.calls.map((x) => x.service), ['turn_on']);
    });

    testWidgets('5 Schloss D (Standard), erkannte Stimme: verweigert', (
      tester,
    ) async {
      final llm = _calls('lock.d', 'unlock');
      final env = _env(llm, _lock);
      final r = await _say(tester, env, 'Haustür auf', speaker: _known);
      expect(env.ha.calls, isEmpty);
      expect(r.platform.unlockRequests, 1);
    });

    testWidgets('5b Schloss explizit auf A neben Licht A: Nutzerwahl, läuft '
        '(ADR: Verantwortung beim Nutzer) – Gegenprobe, dass A wirkt', (
      tester,
    ) async {
      final llm = _calls('lock.d', 'unlock');
      final env = _env(llm, '[{"id":"lock.d","name":"Haustür","level":"a"}]');
      await _say(tester, env, 'Haustür auf');
      expect(env.ha.calls.map((x) => x.service), ['unlock']);
    });
  });

  group('Policy und Umfang direkt', () {
    Future<ProviderContainer> boot(TestEnv env) async {
      final c = env.container();
      addTearDown(c.dispose);
      await c.read(toolRegistryReadyProvider.future);
      return c;
    }

    Tool tool(ProviderContainer c, String name) => c
        .read(toolRegistryProvider)
        .activeToolsFor(PrivacyLevel.local)
        .firstWhere((t) => t.name == name);

    test(
      'ha__call mit Tool-Stufe C im Policy-Speicher: gesperrt Entsperren, '
      'auch für Licht A (Hinweis: die App schreibt diese Stufe nie)',
      () async {
        final env = _env(FakeLlmProvider(const []), _lightA);
        final c = await boot(env);
        final policy = c.read(riskPolicyProvider);
        const locked = AccessContext.lockedUnknownVoice;
        expect(
          policy.decide(tool(c, 'ha__call'), 's', access: locked).action,
          PolicyAction.allow,
          reason: 'ohne gespeicherte Stufe: durchgelassen (Gerät entscheidet)',
        );
        policy.setLevel('ha__call', SecurityLevel.c);
        expect(
          policy.decide(tool(c, 'ha__call'), 's', access: locked),
          PolicyDecision.unlock,
        );
        expect((await c.read(lockedScopeProvider)(locked)), isNull);
      },
    );

    test('ToolPrefs.levels[ha__call]=c erreicht die Policy nicht', () async {
      final env = _env(
        FakeLlmProvider(const []),
        _lightA,
        prefs: const ToolPrefs(levels: {'ha__call': 'c'}),
      );
      final c = await boot(env);
      expect(c.read(riskPolicyProvider).levelFor('ha__call'), isNull);
      final s = await c.read(lockedScopeProvider)(
        AccessContext.lockedUnknownVoice,
      );
      expect(s?.tools, contains('ha__call'));
    });

    test(
      'ha__call_secure gesperrt: nie im Umfang, Policy = Entsperren',
      () async {
        final env = _env(FakeLlmProvider(const []), _lightA);
        final c = await boot(env);
        final decision = c
            .read(riskPolicyProvider)
            .decide(
              tool(c, 'ha__call_secure'),
              's',
              access: AccessContext.lockedUnknownVoice,
            );
        expect(decision, PolicyDecision.unlock);
      },
    );
  });
}
