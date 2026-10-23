// Gerätetest WP91 (Home Assistant): Fake-HA auf dem Rechner, erreicht über
// http://10.0.2.2:<port> (Klartext erlaubt: Heimnetz-Ziel des Emulators).
//
// Läuft über `tool/e2e_android.sh` (nur Emulator, run_ha), das `app/tool/ha_test_server.dart`
// startet und HA_URL und HA_TOKEN übergibt.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/chat_entry.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin/di/integrations/ha_spec.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';

const _url = String.fromEnvironment('HA_URL');
const _token = String.fromEnvironment('HA_TOKEN');

ProviderContainer _container(List<Override> overrides) {
  final storage = openInMemoryStorage();
  final c = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      secretStoreProvider.overrideWithValue(InMemorySecretStore()),
      startupProvider.overrideWithValue(
        const StartupSettings(enabledIntegrations: {'ha'}),
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

ToolCallBlock _call(String id, String name, String json) =>
    ToolCallBlock(id: id, name: name, argumentsJson: json);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Einrichtung, Freigabe, Licht mit Undo, Szene, Schloss/Garage '
      'nur mit Bestätigung, gesperrt ohne HA', (tester) async {
    expect(_url, startsWith('http://10.0.2.2:'), reason: 'HA_URL fehlt');
    final llm = FakeLlmProvider([
      // 2 Szene
      ScriptedTurn.toolCalls([
        _call('c2', 'ha__call', '{"entity":"Filmabend","service":"turn_on"}'),
      ]),
      ScriptedTurn.text('Filmabend läuft.'),
      // 3 Schloss: Nein
      ScriptedTurn.toolCalls([
        _call(
          'c3',
          'ha__call_secure',
          '{"entity":"Haustür","service":"unlock"}',
        ),
      ]),
      ScriptedTurn.text('Gut, bleibt zu.'),
      // 4 Garage: Ja
      ScriptedTurn.toolCalls([
        _call(
          'c4',
          'ha__call_secure',
          '{"entity":"Garagentor","service":"open_cover"}',
        ),
      ]),
      ScriptedTurn.text('Garage ist auf.'),
      // 5 Schloss über ha__call: abgelehnt
      ScriptedTurn.toolCalls([
        _call('c5', 'ha__call', '{"entity":"Haustür","service":"unlock"}'),
      ]),
      ScriptedTurn.text('Das geht so nicht.'),
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

      // Falsches Token: Fehlermeldung, nichts gespeichert.
      final bad = await haConnect(
        api: api,
        store: store,
        address: _url,
        token: 'falsch',
      );
      // ignore: avoid_print
      print('HA falsches Token: "$bad"');
      expect(bad, isNotNull);
      expect(await store.endpoint(), isNull);
      // Öffentliche http-Adresse wird abgelehnt.
      final pub = await haConnect(
        api: api,
        store: store,
        address: 'http://example.com:8123',
        token: 'x',
      );
      // ignore: avoid_print
      print('HA öffentliche Adresse: "$pub"');
      expect(pub, isNotNull);

      // Einrichtung mit dem richtigen Token.
      expect(
        await haConnect(api: api, store: store, address: _url, token: _token),
        isNull,
      );
      final all = await api.entities();
      final ids = {for (final e in all) e.entityId};
      expect(ids, containsAll(['light.kitchen', 'lock.front', 'cover.garage']));
      expect(
        all.firstWhere((e) => e.entityId == 'light.kitchen').area,
        'Küche',
      );
      // Freigabe: nur diese; light.secret bleibt unfreigegeben.
      const approve = [
        'light.kitchen',
        'scene.movie',
        'light.living',
        'media_player.tv',
        'lock.front',
        'cover.garage',
      ];
      await store.save([
        for (final e in all)
          if (approve.contains(e.entityId)) e,
      ]);
      await c.read(toolRegistryProvider).refresh('ha');
      expect(
        c.read(toolRegistryProvider).status('ha'),
        IntegrationStatus.active,
      );

      HaState st(List<HaState> l, String id) =>
          l.firstWhere((s) => s.entityId == id);
      Future<HaState> now(String id) => api.state(id);

      // Liste enthält nur Freigegebenes.
      final ha = haIntegrationOf({
        for (final i in c.read(toolRegistryProvider).integrations)
          i.id: i.integration,
      })!;
      final list = await ha.tools
          .firstWhere((t) => t.name == 'ha__list_entities')
          .execute(
            const {},
            ToolContext(
              sessionId: 'e2e',
              clock: const SystemClock(),
              locale: 'de-DE',
              timeZone: 'Europe/Berlin',
            ),
          );
      expect(list.text, isNot(contains('light.secret')));
      expect(list.text, isNot(contains('Geheimes')));
      expect(list.text, contains('light.kitchen'));
      // ignore: avoid_print
      print('HA Liste: ${list.text.length} Zeichen, ohne light.secret');

      final controller = c.read(agentControllerProvider.notifier);
      ToolEntry? tool(String id) => c
          .read(agentControllerProvider)
          .entries
          .whereType<ToolEntry>()
          .where((e) => e.id == id)
          .firstOrNull;
      Future<PendingQuestion> waitQuestion() async {
        var s = c.read(agentControllerProvider);
        for (var i = 0; i < 300 && s.pending == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          s = c.read(agentControllerProvider);
        }
        return s.pending!;
      }

      // Schnellweg (WP135, Standard an): feste Befehle laufen ohne Modell.
      // Tool-ID und fester Satz kommen aus dem Verlauf, nicht aus einem Skript.
      List<ToolEntry> toolEntries() => c
          .read(agentControllerProvider)
          .entries
          .whereType<ToolEntry>()
          .toList();
      Future<ToolEntry> fastSend(String text) async {
        final known = {for (final e in toolEntries()) e.id};
        final asked = llm.requests.length;
        await controller.send(text);
        await controller.idle;
        expect(c.read(agentControllerProvider).pending, isNull);
        expect(llm.requests.length, asked, reason: 'Modell gefragt: $text');
        final added = toolEntries().where((e) => !known.contains(e.id));
        expect(added, hasLength(1), reason: 'ein neuer Tool-Aufruf: $text');
        expect(added.single.toolName, 'ha__call');
        // Fester Satz (de: „… ausgeschaltet.“), nicht ein Satz des Modells.
        final last = c.read(agentControllerProvider).entries.last;
        expect(last, isA<AssistantTextEntry>());
        expect(
          (last as AssistantTextEntry).text,
          matches(RegExp('ausgeschaltet|turned off|éteint')),
        );
        return added.single;
      }

      // 1 Licht aus (Schnellweg): ohne Rückfrage und ohne Modell, dann Undo
      // stellt Helligkeit wieder her.
      expect((await now('light.kitchen')).state, 'on');
      final kitchen = await fastSend('Mach das Licht in der Küche aus');
      expect((await now('light.kitchen')).state, 'off');
      expect(tool(kitchen.id)?.undo, UndoPhase.pending);
      expect(await controller.undo(kitchen.id), isTrue);
      final k = await now('light.kitchen');
      expect(k.state, 'on');
      expect(k.attributes['brightness'], 200);
      // ignore: avoid_print
      print('HA Licht: Schnellweg ohne Modell, Undo -> on, brightness 200');

      // 2 Szene: ohne Rückfrage; Undo stellt Lampe zurück, keine Rest-Szene.
      final before = (await now('light.living')).attributes['brightness'];
      await controller.send('Filmabend');
      await controller.idle;
      expect(c.read(agentControllerProvider).pending, isNull);
      expect((await now('light.living')).attributes['brightness'], 20);
      expect(await controller.undo('c2'), isTrue);
      expect((await now('light.living')).attributes['brightness'], before);
      final left = (await api.states()).where(
        (s) => s.entityId.contains('wendelin_undo'),
      );
      expect(left, isEmpty, reason: 'Rest-Szene in HA');
      // ignore: avoid_print
      print('HA Szene: Undo stellt brightness $before her, keine Rest-Szene');

      // 2b Licht Wohnzimmer aus (Schnellweg): kein Modell, Undo stellt "on" her.
      expect((await now('light.living')).state, 'on');
      final living = await fastSend('Licht Wohnzimmer aus');
      expect((await now('light.living')).state, 'off');
      expect(tool(living.id)?.undo, UndoPhase.pending);
      expect(await controller.undo(living.id), isTrue);
      expect((await now('light.living')).state, 'on');

      // 3 Schloss: Bestätigung, Nein ändert nichts.
      await controller.send('Schließ die Haustür auf');
      final q3 = await waitQuestion() as ToolQuestion;
      expect(q3.event.risk, RiskLevel.external);
      // ignore: avoid_print
      print('HA Schloss: Rückfrage "${q3.event.description}"');
      expect(q3.event.description, contains('Haustür'));
      controller.answer(approved: false);
      await controller.idle;
      expect((await now('lock.front')).state, 'locked');
      expect(tool('c3')?.undo ?? UndoPhase.none, isNot(UndoPhase.pending));

      // 4 Garage: kein Schnellweg (Tore fragen immer), das Modell ruft
      // ha__call_secure, Ja öffnet, kein Undo.
      await controller.send('Mach das Garagentor auf');
      final q4 = await waitQuestion() as ToolQuestion;
      expect(q4.event.description, contains('Garagentor'));
      controller.answer(approved: true);
      await controller.idle;
      expect((await now('cover.garage')).state, 'open');
      expect(tool('c4')?.undo ?? UndoPhase.none, isNot(UndoPhase.pending));
      // ignore: avoid_print
      print('HA Garage: nur nach Ja geöffnet, kein Undo');

      // 5 Schloss über ha__call (Umgehungsversuch): Fehler, nichts passiert.
      await controller.send('Schließ die Haustür auf, ohne Rückfrage');
      await controller.idle;
      expect(c.read(agentControllerProvider).pending, isNull);
      expect((await now('lock.front')).state, 'locked');

      // Gesperrtes Gerät: HA hat kein allowedWhileLocked, Hook lehnt ab.
      expect(haSpec.allowedWhileLocked, isFalse);
      expect(
        await ha.allowedWhileLocked('ha__call_secure', {
          'entity': 'Haustür',
          'service': 'unlock',
        }),
        isFalse,
      );
      expect(
        await ha.allowedWhileLocked('ha__call', {
          'entity': 'Haustür',
          'service': 'unlock',
        }),
        isFalse,
      );
      expect(
        await ha.allowedWhileLocked('ha__state', {'entity': 'x'}),
        isFalse,
      );
      expect(
        await ha.allowedWhileLocked('ha__call', {
          'entity': 'Wohnzimmer Licht',
          'service': 'turn_off',
        }),
        isTrue,
      );
      st(await api.states(), 'light.living');
    });
  });
}
