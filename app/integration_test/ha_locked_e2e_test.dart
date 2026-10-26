// Gerätetest-Entwurf WP154 L2 (Gesperrt-Pfad, Home Assistant): Fake-HA auf dem
// Rechner (`app/tool/ha_test_server.dart`, Emulator: 10.0.2.2). Ein Lauf mit
// `LockedScope` (gesperrt, Stimme unbekannt) wie ihn das Overlay startet:
// Licht Küche auf A läuft, Licht Wohnzimmer auf C und das Schloss auf D
// werden mit „Entsperren nötig“ abgewiesen, der Server sieht nur den
// einen erlaubten Aufruf.
//
// Läuft mit `tool/e2e_android.sh integration_test/ha_locked_e2e_test.dart`:
// das Skript startet den Fake-HA für jede Datei `ha_*e2e_test.dart` und
// übergibt HA_URL/HA_TOKEN. Bisher nur `flutter analyze`d; der Emulatorlauf
// steht aus (E2E-Agent).
//
// L3 (zweiter Test): dieselbe Anfrage mit der Stimme aus der Sprechererkennung
// (`FakeSpeakerRecognizer`, die Eingabe entsteht wie in der Pipeline aus
// `Transcript.withSpeaker`). Licht Küche auf B läuft nur mit erkannter Stimme,
// ein Fremder bekommt „Entsperren nötig“, das Schloss (D) läuft nie.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/locked_scope.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_voice/fakes.dart';
import 'package:wendelin_voice/wendelin_voice.dart';

const _url = String.fromEnvironment('HA_URL');
const _token = String.fromEnvironment('HA_TOKEN');

ProviderContainer _container(List<Override> overrides) {
  final storage = openInMemoryStorage();
  final c = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      secretStoreProvider.overrideWithValue(InMemorySecretStore()),
      startupProvider.overrideWithValue(
        const StartupSettings(enabledIntegrations: {'ha'}, uiLanguage: 'de'),
      ),
      ...overrides,
    ],
  );
  addTearDown(() async {
    c.dispose();
    await storage.close();
  });
  return c;
}

ToolCallBlock _call(String id, String entity, String service) => ToolCallBlock(
  id: id,
  name: 'ha__call',
  argumentsJson: '{"entity":"$entity","service":"$service"}',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gesperrt: Licht A läuft, Licht C und Schloss D nicht', (
    tester,
  ) async {
    expect(_url, startsWith('http://10.0.2.2:'), reason: 'HA_URL fehlt');
    final llm = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        _call('k', 'light.kitchen', 'turn_off'),
        _call('l', 'light.living', 'turn_off'),
        _call('s', 'lock.front', 'unlock'),
      ]),
      ScriptedTurn.text('Küche aus, der Rest geht nur entsperrt.'),
    ]);
    final c = _container([
      storedProviderConfigProvider.overrideWith(
        (ref) async => deviceTestProviderConfig(llm),
      ),
    ]);
    await tester.runAsync(() async {
      await c.read(toolRegistryReadyProvider.future);
      final api = c.read(haApiProvider);
      final store = c.read(haStoreProvider);
      expect(
        await haConnect(api: api, store: store, address: _url, token: _token),
        isNull,
      );
      final all = await api.entities();
      // Küche A, Wohnzimmer C, Schloss ohne Wahl (Standard D).
      final levels = {
        'light.kitchen': SecurityLevel.a,
        'light.living': SecurityLevel.c,
      };
      await store.save([
        for (final e in all)
          if (levels.containsKey(e.entityId) || e.entityId == 'lock.front')
            e.withLevel(levels[e.entityId]),
      ]);
      await c.read(toolRegistryProvider).refresh('ha');

      final scope = await c.read(lockedScopeProvider)(
        AccessContext.lockedUnknownVoice,
      );
      expect(scope, isNotNull, reason: 'Licht A erlaubt ein Modell');
      expect(scope!.tools, contains('ha__call'));
      expect(scope.tools, isNot(contains('ha__call_secure')));

      final events = await c
          .read(agentControllerProvider.notifier)
          .submit(UserInput(text: 'Alles aus'), locked: scope)
          .toList();
      expect(events.last, isA<AgentDone>());
      final finished = {
        for (final e in events.whereType<ToolCallFinished>()) e.call.id: e,
      };
      expect(finished['k']!.outcome.isError, isFalse);
      expect(finished['l']!.outcome.summary, 'Entsperren nötig');
      expect(finished['s']!.outcome.summary, 'Entsperren nötig');

      expect((await api.state('light.kitchen')).state, 'off');
      expect((await api.state('light.living')).state, 'on');
      expect((await api.state('lock.front')).state, 'locked');
      // Nichts gespeichert (kein Verlauf einer gesperrten Anfrage).
      final storage = c.read(storageProvider);
      expect(await storage.conversations.sessions(limit: 5), isEmpty);
    });
  });

  // Eingabe wie sie die Pipeline baut (`voice_pipeline.dart`, `_answer`).
  Future<UserInput> spoken(SpeakerMatch match) async {
    final recognizer = FakeSpeakerRecognizer(match);
    final heard = const Transcript(
      text: 'Küche aus',
      language: 'de',
    ).withSpeaker(await recognizer.identify(FakeSpeakerEmbedder.audio(0)));
    return UserInput(
      text: heard.text,
      source: InputSource.voice,
      language: heard.language,
      speakerId: heard.speaker?.personId,
    );
  }

  for (final (name, match, runs) in [
    (
      'erkannte Stimme',
      const SpeakerMatch.known(personId: 'p1', name: 'Anna', score: 0.8),
      true,
    ),
    (
      'fremde Stimme',
      const SpeakerMatch.unknown(SpeakerUnknownReason.belowThreshold),
      false,
    ),
  ]) {
    testWidgets('gesperrt, $name: Licht B ${runs ? 'läuft' : 'bleibt'}, '
        'Schloss D nie', (tester) async {
      expect(_url, startsWith('http://10.0.2.2:'), reason: 'HA_URL fehlt');
      final llm = FakeLlmProvider([
        ScriptedTurn.toolCalls([
          _call('k', 'light.kitchen', 'turn_off'),
          _call('s', 'lock.front', 'unlock'),
        ]),
        ScriptedTurn.text('Fertig.'),
      ]);
      final c = _container([
        storedProviderConfigProvider.overrideWith(
          (ref) async => deviceTestProviderConfig(llm),
        ),
      ]);
      await tester.runAsync(() async {
        await c.read(toolRegistryReadyProvider.future);
        final api = c.read(haApiProvider);
        final store = c.read(haStoreProvider);
        expect(
          await haConnect(api: api, store: store, address: _url, token: _token),
          isNull,
        );
        final all = await api.entities();
        await store.save([
          for (final e in all)
            if (e.entityId == 'light.kitchen')
              e.withLevel(SecurityLevel.b)
            else if (e.entityId == 'lock.front')
              e,
        ]);
        await c.read(toolRegistryProvider).refresh('ha');

        final input = await spoken(match);
        final access = AccessContext.lockedFor(input);
        expect(access.speakerRecognized, runs);
        final scope = await c.read(lockedScopeProvider)(access);
        expect(scope == null, !runs, reason: 'ohne Stimme kein Modelllauf');
        if (scope == null) {
          expect((await api.state('light.kitchen')).state, 'on');
          return;
        }
        final events = await c
            .read(agentControllerProvider.notifier)
            .submit(input, locked: scope)
            .toList();
        final finished = {
          for (final e in events.whereType<ToolCallFinished>()) e.call.id: e,
        };
        expect(finished['k']!.outcome.isError, isFalse);
        expect(finished['s']!.outcome.summary, 'Entsperren nötig');
        expect((await api.state('light.kitchen')).state, 'off');
        expect((await api.state('lock.front')).state, 'locked');
      });
    });
  }
}
