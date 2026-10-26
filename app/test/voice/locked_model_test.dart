// WP154 L2: gesperrtes Gerät – Befehlspfad über Policy/Executor, Modelllauf
// nur mit erlaubten Tools, Entsperren ohne Doppelausführung.
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
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

import '../overlay/assistant_overlay_test.dart'
    show FakeAssistantPlatform, overlaySample, pumpOverlay;
import '../support/test_env.dart';
import 'voice_controller_test.dart' show fakeVoice;

const _entities =
    '['
    '{"id":"light.a","name":"Flurlicht","level":"a"},'
    '{"id":"light.b","name":"Stehlampe"},'
    '{"id":"cover.c","name":"Rollo","level":"c"},'
    '{"id":"lock.d","name":"Haustür"}'
    ']';

TestEnv _env(
  FakeLlmProvider llm, {
  Set<String> enabled = const {'flashlight', 'ha'},
  ToolPrefs prefs = const ToolPrefs(),
  String entities = _entities,
}) {
  final env = TestEnv(
    providerConfig: scripted(llm),
    startup: StartupSettings(enabledIntegrations: enabled, toolPrefs: prefs),
  );
  env.secrets
    ..write('ha.url', 'http://192.168.1.20:8123')
    ..write('ha.token', 'a' * 40)
    ..write('ha.entities', entities);
  for (final id in ['light.a', 'light.b', 'cover.c', 'lock.d']) {
    env.ha.set(id, 'off', const {});
  }
  return env;
}

Future<void> _settle(WidgetTester tester, ProviderContainer c) async {
  for (var i = 0; i < 800; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    final v = c.read(voiceControllerProvider);
    if (i > 5 && !v.active && !v.preparing) break;
  }
  await c.read(voiceControllerProvider.notifier).whenIdle;
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('lockedScopeProvider je Kombination', () {
    Future<Set<String>?> scope(
      ToolPrefs prefs, {
      String entities = _entities,
      Set<String> enabled = const {'flashlight', 'ha'},
    }) async {
      final llm = FakeLlmProvider(const []);
      final env = _env(llm, prefs: prefs, entities: entities, enabled: enabled);
      final c = env.container();
      addTearDown(c.dispose);
      final s = await c.read(lockedScopeProvider)(
        AccessContext.lockedUnknownVoice,
      );
      return s?.tools;
    }

    const torch = {'flashlight__on', 'flashlight__off'};

    test(
      'Standard: nur Taschenlampe an/aus, also kein Modell (null)',
      () async {
        expect(
          await scope(
            const ToolPrefs(),
            entities: '[{"id":"light.b","name":"L"}]',
          ),
          isNull,
        );
      },
    );

    test(
      'Standard mit allen Integrationen: weiter kein Modell (null)',
      () async {
        final probe = _env(FakeLlmProvider(const []));
        final c0 = probe.container();
        addTearDown(c0.dispose);
        final all = {for (final i in c0.read(integrationSpecsProvider)) i.id};
        expect(all, containsAll(['flashlight', 'ha', 'memory']));
        expect(
          await scope(
            const ToolPrefs(),
            entities: '[{"id":"light.b","name":"L"}]',
            enabled: all,
          ),
          isNull,
        );
      },
    );

    test('Licht auf A: ha__call kommt dazu', () async {
      expect(
        await scope(
          const ToolPrefs(),
          entities: '[{"id":"light.a","name":"L","level":"a"}]',
        ),
        {'ha__call', ...torch},
      );
    });

    for (final (name, entity) in [
      ('Licht B', '{"id":"light.b","name":"L"}'),
      ('Rollo C', '{"id":"cover.c","name":"R","level":"c"}'),
      ('Schloss D', '{"id":"lock.d","name":"S"}'),
      ('Licht auf D', '{"id":"light.a","name":"L","level":"d"}'),
    ]) {
      test('$name allein: kein Modell', () async {
        expect(await scope(const ToolPrefs(), entities: '[$entity]'), isNull);
      });
    }

    test('altes „Immer bestätigen“ auf ha__call: nicht im Umfang', () async {
      expect(
        await scope(
          const ToolPrefs(alwaysConfirm: {'ha__call'}),
          entities: '[{"id":"light.a","name":"L","level":"a"}]',
        ),
        isNull,
      );
    });

    test('Taschenlampe auf D: fällt aus dem Umfang, Licht A bleibt', () async {
      expect(
        await scope(
          const ToolPrefs(
            levels: {'flashlight__on': 'd', 'flashlight__off': 'd'},
          ),
          entities: '[{"id":"light.a","name":"L","level":"a"}]',
        ),
        {'ha__call'},
      );
    });

    test('Lesetool auf A: im Umfang (Gedächtnissuche)', () async {
      expect(
        await scope(
          const ToolPrefs(levels: {'memory__search': 'a'}),
          enabled: const {'flashlight', 'memory'},
        ),
        {'memory__search', ...torch},
      );
    });

    test('ungültige Stufe: D, nie erlaubt (fail-closed)', () async {
      expect(
        await scope(
          const ToolPrefs(levels: {'memory__search': 'x'}),
          enabled: const {'flashlight', 'memory'},
        ),
        isNull,
      );
    });
  });

  group('Overlay gesperrt', () {
    late FakeLlmProvider llm;

    Future<(ProviderContainer, FakeAssistantPlatform, FakeTextToSpeech)> run(
      WidgetTester tester,
      TestEnv env,
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

    setUp(() => llm = FakeLlmProvider(const []));

    testWidgets(
      'Taschenlampe auf D: nicht ausgeführt, Entsperr-Satz, kein Modell',
      (tester) async {
        final env = _env(
          llm,
          prefs: const ToolPrefs(levels: {'flashlight__on': 'd'}),
        );
        final (_, platform, tts) = await run(tester, env, 'Taschenlampe an');
        expect(env.torch.on, isFalse);
        expect(env.torch.methodCalls, isNot(contains('set')));
        expect(tts.spoken.join(' '), 'Bitte entsperre das Telefon.');
        expect(llm.requests, isEmpty);
        expect(platform.unlockRequests, 1);
      },
    );

    testWidgets('immer bestätigen auf der Taschenlampe: nicht ausgeführt', (
      tester,
    ) async {
      final env = _env(
        llm,
        prefs: const ToolPrefs(alwaysConfirm: {'flashlight__on'}),
      );
      final (_, _, tts) = await run(tester, env, 'Taschenlampe an');
      expect(env.torch.on, isFalse);
      expect(tts.spoken.join(' '), isNot('Taschenlampe an.'));
      expect(llm.requests, isEmpty);
    });

    testWidgets('hängendes TorchPort.set endet nach 20 s und blockiert nicht', (
      tester,
    ) async {
      final env = _env(llm);
      env.torch.hangs = true;
      final (c, _, tts) = await run(tester, env, 'Taschenlampe an');
      expect(tts.spoken.join(' '), 'Das hat nicht geklappt.');
      expect(c.read(voiceControllerProvider).active, isFalse);
      await c.read(auditRecorderProvider).flush();
      final call = (await env.storage.audit.query()).singleWhere(
        (e) => e.kind == AuditKind.toolCall,
      );
      expect(call.payload['whileLocked'], isTrue);
    });

    testWidgets('Licht A läuft gesperrt über das Modell, Tools = erlaubte', (
      tester,
    ) async {
      llm = FakeLlmProvider([
        ScriptedTurn.toolCalls([
          ToolCallBlock(
            id: '1',
            name: 'ha__call',
            argumentsJson: '{"entity":"light.a","service":"turn_on"}',
          ),
        ]),
        ScriptedTurn.text('Erledigt.'),
      ]);
      final env = _env(llm);
      final (_, platform, _) = await run(tester, env, 'Flurlicht an');
      expect([
        for (final t in llm.requests.first.tools) t.name,
      ], unorderedEquals(['ha__call', 'flashlight__on', 'flashlight__off']));
      expect(env.ha.calls.single.service, 'turn_on');
      expect(platform.unlockRequests, 0);
    });

    testWidgets(
      'Licht A plus Schloss D: Licht läuft, Schloss nie, nach dem Entsperren '
      'keine Wiederholung',
      (tester) async {
        llm = FakeLlmProvider([
          ScriptedTurn.toolCalls([
            ToolCallBlock(
              id: '1',
              name: 'ha__call',
              argumentsJson: '{"entity":"light.a","service":"turn_on"}',
            ),
            ToolCallBlock(
              id: '2',
              name: 'ha__call',
              argumentsJson: '{"entity":"lock.d","service":"unlock"}',
            ),
          ]),
          ScriptedTurn.text('Licht an, für die Tür bitte entsperren.'),
        ]);
        final env = _env(llm);
        final (c, platform, _) = await run(
          tester,
          env,
          'Flurlicht an und Haustür auf',
          unlockSucceeds: true,
        );
        expect(env.ha.calls.map((x) => '${x.domain}.${x.service}'), [
          'light.turn_on',
        ], reason: 'Schloss nie, Licht genau einmal');
        expect(platform.unlockRequests, 1, reason: 'Entsperren wird angeboten');
        expect(c.read(lockedPendingProvider), isNull);
        // Nach dem Entsperren keine zweite Anfrage an das Modell.
        expect(llm.requests, hasLength(2));
        expect(env.ha.calls, hasLength(1));
      },
    );

    testWidgets('nur Schloss D: verweigert, Anfrage gemerkt und nach dem '
        'Entsperren wiederholt (nichts lief)', (tester) async {
      llm = FakeLlmProvider([
        ScriptedTurn.toolCalls([
          ToolCallBlock(
            id: '1',
            name: 'ha__call',
            argumentsJson: '{"entity":"lock.d","service":"unlock"}',
          ),
        ]),
        ScriptedTurn.text('Bitte entsperren.'),
        ScriptedTurn.toolCalls([
          ToolCallBlock(
            id: '2',
            name: 'ha__call',
            argumentsJson: '{"entity":"lock.d","service":"unlock"}',
          ),
        ]),
        ScriptedTurn.text('Tür offen.'),
      ]);
      final env = _env(llm);
      final (c, platform, _) = await run(
        tester,
        env,
        'Haustür auf',
        unlockSucceeds: true,
      );
      // Genau 4 Anfragen: 1-2 gesperrt, 3-4 nach dem Entsperren wiederholt.
      expect(llm.requests, hasLength(4));
      Set<String> names(int i) => {
        for (final t in llm.requests[i].tools) t.name,
      };
      expect(names(0), {'ha__call', 'flashlight__on', 'flashlight__off'});
      expect(names(1), names(0));
      expect(names(2), contains('ha__call_secure'), reason: 'voller Katalog');
      expect(names(2).length, greaterThan(names(0).length));
      expect(platform.unlockRequests, 1);
      expect(c.read(lockedPendingProvider), isNull);
      expect(
        env.ha.calls.where((x) => x.domain == 'lock'),
        isEmpty,
        reason: 'gesperrt nie; entsperrt wartet das Schloss auf Bestätigung',
      );
    });
  });
}
