// Gerätetest (WP27): MCP-Server auf dem Rechner, erreicht über
// http://10.0.2.2:<port> (Klartext erlaubt: Heimnetz-Ziel des Emulators).
//
// Läuft über `tool/e2e_mcp.sh` (nur Emulator), das `app/tool/mcp_test_server.dart`
// startet und `--dart-define=MCP_URL=…` und `MCP_TOKEN=…` übergibt.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/agent/agent_controller.dart';
import 'package:wendelin/agent/conversation_state.dart';
import 'package:wendelin/debug/device_test_overrides.dart';
import 'package:wendelin/di/http_tools.dart';
import 'package:wendelin/di/mcp/mcp_providers.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/fakes.dart';

/// The app's providers on the real device (HTTP, platform channels) with
/// an in-memory database and secrets, without UI.
ProviderContainer _container({List<Override> overrides = const []}) {
  final storage = openInMemoryStorage();
  final c = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      secretStoreProvider.overrideWithValue(InMemorySecretStore()),
      startupProvider.overrideWithValue(
        const StartupSettings(enabledIntegrations: {}),
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

const _url = String.fromEnvironment('MCP_URL');
const _token = String.fromEnvironment('MCP_TOKEN');
const _httpUrl = String.fromEnvironment('HTTP_URL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Emulator verbindet sich mit dem Test-MCP-Server über 10.0.2.2, '
      'Tools landen in der Registry und lassen sich aufrufen', (tester) async {
    expect(_url, startsWith('http://10.0.2.2:'), reason: 'MCP_URL fehlt');
    final c = _container();
    await tester.runAsync(() async {
      await c.read(toolRegistryReadyProvider.future);
      final source = c.read(mcpServerSourceProvider);

      // Heimnetz-Ziel: Klartext erlaubt.
      checkServerUrl(Uri.parse(_url));
      final draft = McpDraft(
        name: 'Rechner',
        url: Uri.parse(_url),
        auth: McpAuthKind.bearer,
        token: _token,
      );
      final probe = await source.probeDraft(draft);
      expect(probe.status, McpReachability.reachable, reason: '$probe');

      final view = await source.add(draft);
      expect(view.check?.status, McpReachability.reachable);
      await c.read(userIntegrationSyncProvider).settled();
      await c
          .read(integrationActivatorProvider)
          .setEnabled(view.integrationId, enabled: true);
      await c.read(userIntegrationSyncProvider).settled();
      final registry = c.read(toolRegistryProvider);
      expect(registry.status(view.integrationId), IntegrationStatus.active);
      final names = registry
          .activeSpecsFor(PrivacyLevel.standard, sessionId: 'e2e')
          .map((s) => s.name);
      expect(
        names,
        containsAll(['mcp_rechner__get_state', 'mcp_rechner__delete_scene']),
      );

      final tool = registry.integrations
          .expand((i) => i.integration.tools)
          .firstWhere((t) => t.name == 'mcp_rechner__get_state');
      final outcome = await tool.execute(
        const {'entity': 'licht'},
        ToolContext(
          sessionId: 'e2e',
          clock: const SystemClock(),
          locale: 'de-DE',
          timeZone: 'Europe/Berlin',
        ),
      );
      expect(outcome.isError, isFalse);
      final text = outcome.content.whereType<TextBlock>().map((b) => b.text);
      expect(text.join(), contains('licht: an'));
      expect(text.join(), contains('<mcp_result'));
      expect(
        registry.integrations
            .expand((i) => i.integration.tools)
            .firstWhere((t) => t.name == 'mcp_rechner__delete_scene')
            .risk,
        RiskLevel.external,
      );

      // Löschen räumt auf.
      await source.remove(view.config.id);
      await c.read(userIntegrationSyncProvider).settled();
      expect(c.read(secretStoreProvider).listKeys(), completion(isEmpty));
    });
  });

  testWidgets('Agent: read-Tool läuft ohne Rückfrage, destruktives Tool '
      '(destructiveHint) fragt nach und „Nein“ führt es nicht aus', (
    tester,
  ) async {
    expect(_url, startsWith('http://10.0.2.2:'), reason: 'MCP_URL fehlt');
    final llm = FakeLlmProvider([
      ScriptedTurn.toolCalls([
        const ToolCallBlock(
          id: 'c1',
          name: 'mcp_rechner__get_state',
          argumentsJson: '{"entity":"licht"}',
        ),
      ]),
      ScriptedTurn.text('Das Licht ist an.'),
      ScriptedTurn.toolCalls([
        const ToolCallBlock(
          id: 'c2',
          name: 'mcp_rechner__delete_thing',
          argumentsJson: '{}',
        ),
      ]),
      ScriptedTurn.text('Gut, ich lasse es.'),
    ]);
    final c = _container(
      overrides: [
        storedProviderConfigProvider.overrideWith(
          (ref) async => deviceTestProviderConfig(llm),
        ),
      ],
    );
    await tester.runAsync(() async {
      await c.read(toolRegistryReadyProvider.future);
      final view = await c
          .read(mcpServerSourceProvider)
          .add(
            McpDraft(
              name: 'Rechner',
              url: Uri.parse(_url),
              auth: McpAuthKind.bearer,
              token: _token,
            ),
          );
      await c.read(userIntegrationSyncProvider).settled();
      await c
          .read(integrationActivatorProvider)
          .setEnabled(view.integrationId, enabled: true);
      await c.read(userIntegrationSyncProvider).settled();

      final controller = c.read(agentControllerProvider.notifier);
      await controller.send('Ist das Licht an?');
      await controller.idle;
      final state = c.read(agentControllerProvider);
      expect(
        state.pending,
        isNull,
        reason: 'read-Tool braucht keine Rückfrage',
      );
      expect(
        llm.requests[1].messages.expand((m) => m.content).toString(),
        contains('licht: an'),
      );

      await controller.send('Lösch das Ding');
      ConversationState asking = c.read(agentControllerProvider);
      for (var i = 0; i < 300 && asking.pending == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        asking = c.read(agentControllerProvider);
      }
      final question = asking.pending! as ToolQuestion;
      expect(question.event.risk, RiskLevel.external);
      // ignore: avoid_print
      print('MCP destruktiv: Rückfrage "${question.event.description}"');
      controller.answer(approved: false);
      await controller.idle;
      expect(llm.requests, hasLength(4));
      final last = llm.requests.last.messages.expand((m) => m.content);
      expect(last.toString(), isNot(contains('gelöscht')));
    });
  });

  testWidgets('HTTP-Tool gegen den Test-Server (http__ha_state über 10.0.2.2, '
      'Bearer aus dem Secret-Speicher)', (tester) async {
    expect(_httpUrl, startsWith('http://10.0.2.2:'), reason: 'HTTP_URL fehlt');
    final c = _container();
    await tester.runAsync(() async {
      await c.read(toolRegistryReadyProvider.future);
      await c
          .read(httpToolRepositoryProvider)
          .save(
            HttpToolDefinition(
              id: 'ha-state',
              name: 'ha_state',
              description: 'Zustand einer Entität lesen',
              method: HttpMethod.get,
              urlTemplate: '$_httpUrl/api/states/{entity_id}',
              inputSchema: const {
                'type': 'object',
                'properties': {
                  'entity_id': {'type': 'string'},
                },
                'required': ['entity_id'],
              },
              auth: const ApiKeyAuth('ha-state.token'),
              homeNetwork: true,
            ),
            secretValues: {'ha-state.token': _token},
          );
      await c.read(userIntegrationSyncProvider).settled();
      await c
          .read(integrationActivatorProvider)
          .setEnabled(HttpToolsIntegration.plainId, enabled: true);
      await c.read(userIntegrationSyncProvider).settled();
      final tool = c
          .read(toolRegistryProvider)
          .integrations
          .expand((i) => i.integration.tools)
          .firstWhere((t) => t.name == 'http__ha_state');
      final outcome = await tool.execute(
        const {'entity_id': 'light.wohnzimmer'},
        ToolContext(
          sessionId: 'e2e',
          clock: const SystemClock(),
          locale: 'de-DE',
          timeZone: 'Europe/Berlin',
        ),
      );
      expect(outcome.isError, isFalse, reason: '${outcome.summary}');
      final text = outcome.content.whereType<TextBlock>().map((b) => b.text);
      expect(text.join(), contains('light.wohnzimmer'));
      expect(text.join(), isNot(contains(_token)));
    });
  });

  testWidgets('OAuth ohne Browser (AOSP): klarer Hinweis statt Absturz', (
    tester,
  ) async {
    final c = _container();
    await tester.runAsync(() async {
      final available = await c.read(mcpBrowserAvailableProvider)();
      // ignore: avoid_print
      print('Browser für OAuth verfügbar: $available');
      if (available) return;
      await c.read(toolRegistryReadyProvider.future);
      final source = c.read(mcpServerSourceProvider);
      final view = await source.add(
        McpDraft(name: 'OAuth', url: Uri.parse(_url), auth: McpAuthKind.oauth),
      );
      await expectLater(
        source.signIn(view.config.id),
        throwsA(same(McpSignInException.noBrowser)),
      );
    });
  });
}
