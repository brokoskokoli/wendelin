// Gerätetest (WP27): MCP-Server auf dem Rechner, erreicht über
// http://10.0.2.2:<port> (Klartext erlaubt: Heimnetz-Ziel des Emulators).
//
// Läuft über `tool/e2e_mcp.sh` (nur Emulator), das `app/tool/mcp_test_server.dart`
// startet und `--dart-define=MCP_URL=…` und `MCP_TOKEN=…` übergibt.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wendelin/di/mcp/mcp_providers.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/fakes.dart';

/// The app's providers on the real device (HTTP, platform channels) with
/// an in-memory database and secrets, without UI.
ProviderContainer _container() {
  final storage = openInMemoryStorage();
  final c = ProviderContainer(
    overrides: [
      storageProvider.overrideWithValue(storage),
      secretStoreProvider.overrideWithValue(InMemorySecretStore()),
      startupProvider.overrideWithValue(
        const StartupSettings(enabledIntegrations: {}),
      ),
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
