import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/mcp/mcp_providers.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/integrations_screen.dart';
import 'package:wendelin/ui/settings/mcp/mcp_add_server_screen.dart';
import 'package:wendelin/ui/settings/mcp/mcp_server_detail_screen.dart';
import 'package:wendelin/ui/settings/mcp/mcp_servers_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

import '../settings/integrations_screen_test.dart'
    show settle, switchOf, tile, tileWidget;
import '../support/mcp_support.dart';
import '../support/test_env.dart';
import '../ui/helpers.dart';

/// Lets network and database work happen (outside the fake clock) until
/// [condition] holds.
Future<void> pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await settle(tester);
  }
  expect(condition(), isTrue, reason: 'Zustand nicht erreicht');
}

bool shows(String text) => find.textContaining(text).evaluate().isNotEmpty;

ProviderContainer containerOf(WidgetTester tester, Type screen) =>
    ProviderScope.containerOf(tester.element(find.byType(screen)));

List<String> catalog(ProviderContainer c) => c
    .read(toolRegistryProvider)
    .activeSpecsFor(PrivacyLevel.standard, sessionId: 's')
    .map((s) => s.name)
    .toList();

Tool registered(ProviderContainer c, String name) => c
    .read(toolRegistryProvider)
    .integrations
    .expand((i) => i.integration.tools)
    .firstWhere((t) => t.name == name);

Future<void> tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.tap(find.text(text).last);
  await settle(tester);
}

void main() {
  setUp(allowRealHttp);

  testWidgets('Server per Vorlage anlegen: Prüfen zeigt Zustände, Speichern '
      'schaltet ihn ein, Tools erscheinen', (tester) async {
    final server = (await tester.runAsync(
      () => FakeMcpServer.start(tools: homeTools(), auth: FakeAuthMode.bearer),
    ))!;
    final env = TestEnv(enabled: const {}, extraOverrides: mcpOverrides());
    setView(tester, const Size(390, 1800));
    await tester.pumpWidget(env.app(home: const McpServersScreen()));
    await settle(tester);
    expect(find.text('Noch kein Server'), findsOneWidget);

    await tapText(tester, '+ Server');
    expect(find.byType(McpAddServerScreen), findsOneWidget);
    for (final name in ['Home Assistant', 'Obsidian', 'Kalender (CalDAV)']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('Eigener Server'), findsOneWidget);
    await tapText(tester, 'Home Assistant');
    final url = find.byKey(const ValueKey('mcpUrl'));
    expect(
      tester.widget<TextField>(url).controller!.text,
      'http://homeassistant.local:8123/api/mcp',
    );
    expect(shows('Unverschlüsselt (http)'), isTrue);
    final token = find.byKey(const ValueKey('mcpToken'));
    expect(tester.widget<TextField>(token).obscureText, isTrue);

    // Klartext ins Internet wird abgelehnt.
    await tester.enterText(url, 'http://example.org/mcp');
    await tapText(tester, 'Verbindung prüfen');
    expect(shows('http nur im Heimnetz'), isTrue);

    await tester.enterText(url, server.url.toString());
    await tester.enterText(token, 'falsch');
    await tapText(tester, 'Verbindung prüfen');
    await pumpUntil(tester, () => shows('Token oder Header prüfen'));

    await tester.enterText(token, server.bearerToken);
    await tapText(tester, 'Verbindung prüfen');
    await pumpUntil(tester, () => shows('Erreichbar · fake-mcp 1.0.0'));

    await tester.runAsync(server.close);
    await tapText(tester, 'Verbindung prüfen');
    await pumpUntil(tester, () => shows('Tailscale/WireGuard aktiv?'));

    final again = (await tester.runAsync(
      () => FakeMcpServer.start(tools: homeTools(), auth: FakeAuthMode.bearer),
    ))!;
    await tester.enterText(url, again.url.toString());
    await tester.enterText(token, again.bearerToken);
    await tapText(tester, 'Speichern');
    await pumpUntil(
      tester,
      () => find.byType(McpServerDetailScreen).evaluate().isNotEmpty,
    );
    final c = containerOf(tester, McpServerDetailScreen);
    await pumpUntil(
      tester,
      () => catalog(c).contains('mcp_homeassistant__get_state'),
    );
    for (final name in ['get_state', 'set_light', 'delete_scene']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('liest · ohne Nachfrage'), findsOneWidget);
    expect(find.text('ändert · fragt nach · kein Rückgängig'), findsOneWidget);
    expect(find.text('Außenwirkung · fragt immer nach'), findsOneWidget);
    // Token im SecretStore, nie wieder angezeigt.
    final id = c.read(mcpServerSourceProvider).servers.single.config.id;
    expect(
      await tester.runAsync(() => env.secrets.read(McpSecretRefs.bearer(id))),
      again.bearerToken,
    );
    expect(find.text(again.bearerToken), findsNothing);
    await tester.runAsync(again.close);
    await _unmount(tester);
  });

  testWidgets('Formular: „Alle Tools bestätigen“ beim Anlegen macht jedes '
      'Tool external', (tester) async {
    final server = (await tester.runAsync(
      () => FakeMcpServer.start(tools: homeTools()),
    ))!;
    final env = TestEnv(enabled: const {}, extraOverrides: mcpOverrides());
    setView(tester, const Size(390, 1800));
    await tester.pumpWidget(env.app(home: const McpAddServerScreen()));
    await settle(tester);
    await tapText(tester, 'Eigener Server');
    await tester.enterText(find.byKey(const ValueKey('mcpName')), 'Labor');
    await tester.enterText(
      find.byKey(const ValueKey('mcpUrl')),
      server.url.toString(),
    );
    final confirmAll = find.descendant(
      of: find.widgetWithText(InkWell, 'Alle Tools bestätigen'),
      matching: find.byType(WSwitch),
    );
    await tester.ensureVisible(confirmAll);
    await tester.tap(confirmAll);
    await settle(tester);
    expect(tester.widget<WSwitch>(confirmAll).value, isTrue);
    await tapText(tester, 'Speichern');
    await pumpUntil(
      tester,
      () => find.byType(McpServerDetailScreen).evaluate().isNotEmpty,
    );
    final c = containerOf(tester, McpServerDetailScreen);
    await pumpUntil(tester, () => catalog(c).length >= 3);
    final tools = [
      for (final n in catalog(c))
        if (n.startsWith('mcp_labor__')) registered(c, n),
    ];
    expect(tools, hasLength(3));
    expect(tools.map((t) => t.risk).toSet(), {RiskLevel.external});
    expect(find.text('liest · fragt immer nach'), findsOneWidget);
    await tester.runAsync(server.close);
    await _unmount(tester);
  });

  testWidgets('Tool-Schalter, „Immer nachfragen“ und „ohne Nachfrage“ wirken '
      'auf den Tool-Katalog; Löschen räumt Registry und Secrets auf', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {'mcp_homeserver'},
      extraOverrides: mcpOverrides(),
    );
    await tester.runAsync(
      () => seedServers(
        env,
        [
          (
            config: McpServerConfig(
              id: 'srv',
              name: 'Homeserver',
              slug: 'homeserver',
              url: Uri.parse('http://homeserver.local:3000/mcp'),
              auth: McpBearerAuth(McpSecretRefs.bearer('srv')),
            ),
            tools: homeToolInfos(),
            check: null,
          ),
        ],
        secrets: {McpSecretRefs.bearer('srv'): 'token'},
      ),
    );
    setView(tester, const Size(390, 1800));
    await tester.pumpWidget(env.app(home: const McpServersScreen()));
    final c = containerOf(tester, McpServersScreen);
    await pumpUntil(
      tester,
      () => catalog(c).contains('mcp_homeserver__get_state'),
    );
    await settle(tester);
    expect(tileWidget(tester, 'Homeserver').status, IntegrationStatus.active);
    expect(tileWidget(tester, 'Homeserver').kind, 'MCP');
    expect(tileWidget(tester, 'Homeserver').detail, '3 Tools');

    await tapText(tester, 'Homeserver');
    expect(find.byType(McpServerDetailScreen), findsOneWidget);

    // Tool abschalten.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InkWell, 'delete_scene'),
        matching: find.byType(WSwitch),
      ),
    );
    await pumpUntil(
      tester,
      () => !catalog(c).contains('mcp_homeserver__delete_scene'),
    );
    expect(find.text('abgeschaltet'), findsOneWidget);

    // read → „Immer nachfragen“ (nur verschärfen).
    await tapText(tester, 'get_state');
    expect(find.text('Server: nur lesend (readOnlyHint)'), findsOneWidget);
    await tapText(tester, 'Immer nachfragen');
    await pumpUntil(
      tester,
      () =>
          registered(c, 'mcp_homeserver__get_state').risk == RiskLevel.external,
    );
    expect(find.text('liest · fragt immer nach'), findsOneWidget);

    // write → „Ohne Nachfrage“ mit Hinweis „kein Rückgängig“.
    await tapText(tester, 'set_light');
    expect(shows('Kein Rückgängig'), isTrue);
    await tapText(tester, 'Ohne Nachfrage');
    await pumpUntil(
      tester,
      () => registered(c, 'mcp_homeserver__set_light').risk == RiskLevel.write,
    );
    expect(
      find.text('ändert · ohne Nachfrage · kein Rückgängig'),
      findsOneWidget,
    );

    // external lässt sich nicht lockern.
    await tapText(tester, 'delete_scene');
    expect(shows('lässt sich nicht lockern'), isTrue);
    expect(find.text('Ohne Nachfrage'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);

    // „Alle Tools bestätigen“ schlägt „ohne Nachfrage“.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InkWell, 'Alle Tools bestätigen'),
        matching: find.byType(WSwitch),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          registered(c, 'mcp_homeserver__set_light').risk == RiskLevel.external,
    );

    // Löschen.
    await tapText(tester, 'Server löschen');
    await tapText(tester, 'Löschen');
    await pumpUntil(
      tester,
      () => find.byType(McpServerDetailScreen).evaluate().isEmpty,
    );
    await pumpUntil(tester, () => !catalog(c).any((n) => n.startsWith('mcp_')));
    expect(await tester.runAsync(env.secrets.listKeys), isEmpty);
    expect(find.text('Noch kein Server'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('Integrationen: MCP-Server unter „Eigene Integrationen“, Tippen '
      'öffnet die Serverseite; Einrichten führt zur Serverliste', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {'mcp_home', 'mcp_notes'},
      extraOverrides: mcpOverrides(),
    );
    await tester.runAsync(
      () => seedServers(
        env,
        _goldenServers(),
        secrets: {McpSecretRefs.bearer('home'): 'token'},
      ),
    );
    setView(tester, const Size(390, 1600));
    await tester.pumpWidget(env.app(home: const IntegrationsScreen()));
    await pumpUntil(
      tester,
      () => tile('Obsidian Desktop').evaluate().isNotEmpty,
    );
    final c = containerOf(tester, IntegrationsScreen);
    await tester.runAsync(() => c.read(toolRegistryProvider).refresh());
    await settle(tester);
    expect(find.text('Eigene Integrationen'), findsOneWidget);
    expect(tileWidget(tester, 'Home Assistant').kind, 'MCP');
    expect(
      tileWidget(tester, 'Home Assistant').status,
      IntegrationStatus.active,
    );
    expect(
      tileWidget(tester, 'Obsidian Desktop').status,
      IntegrationStatus.setupRequired,
    );
    await tester.tap(switchOf('Home Assistant'));
    await settle(tester);
    expect(
      tileWidget(tester, 'Home Assistant').status,
      IntegrationStatus.available,
    );
    await tapText(tester, 'Home Assistant');
    expect(find.byType(McpServerDetailScreen), findsOneWidget);
    expect(find.text('get_state'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await settle(tester);
    await tester.tap(
      find.descendant(
        of: tile('Obsidian Desktop'),
        matching: find.text('Einrichten'),
      ),
    );
    await settle(tester);
    expect(find.byType(McpServersScreen), findsOneWidget);
  });

  group('Goldens', () {
    Future<TestEnv> seeded(WidgetTester tester) async {
      final env = TestEnv(
        enabled: const {'mcp_home', 'mcp_notes', 'mcp_kalender'},
        extraOverrides: mcpOverrides(),
      );
      await tester.runAsync(
        () => seedServers(
          env,
          _goldenServers(),
          secrets: {McpSecretRefs.bearer('home'): 'token'},
        ),
      );
      return env;
    }

    Future<void> ready(WidgetTester tester, Type screen) async {
      await settle(tester);
      final c = containerOf(tester, screen);
      await pumpUntil(
        tester,
        () => c.read(userIntegrationSyncProvider).ids.length == 4,
      );
      await tester.runAsync(() => c.read(toolRegistryProvider).refresh());
      await settle(tester);
    }

    Future<void> guidelines(WidgetTester tester) async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    testWidgets('Serverliste (390 × 844)', tags: ['golden'], (tester) async {
      final handle = tester.ensureSemantics();
      final env = await seeded(tester);
      setView(tester, screenSize);
      await tester.pumpWidget(env.app(home: const McpServersScreen()));
      await ready(tester, McpServersScreen);
      expect(
        tileWidget(tester, 'Home Assistant').status,
        IntegrationStatus.active,
      );
      expect(
        tileWidget(tester, 'Obsidian Desktop').status,
        IntegrationStatus.setupRequired,
      );
      expect(tileWidget(tester, 'Kalender').status, IntegrationStatus.error);
      expect(
        tileWidget(tester, 'Kalender').detail,
        'Nicht erreichbar · Tailscale/WireGuard aktiv?',
      );
      expect(
        tileWidget(tester, 'Werkstatt').status,
        IntegrationStatus.available,
      );
      await expectLater(
        find.byType(McpServersScreen),
        matchesGoldenFile('goldens/mcp_server.png'),
      );
      await guidelines(tester);
      handle.dispose();
    });

    testWidgets('Serverseite (390 × 1400)', tags: ['golden'], (tester) async {
      final handle = tester.ensureSemantics();
      final env = await seeded(tester);
      setView(tester, const Size(390, 1400));
      await tester.pumpWidget(
        env.app(home: const McpServerDetailScreen('home')),
      );
      await ready(tester, McpServerDetailScreen);
      expect(shows('erreichbar · 13.10. 08:12 · 42 ms'), isTrue);
      await expectLater(
        find.byType(McpServerDetailScreen),
        matchesGoldenFile('goldens/mcp_server_detail.png'),
      );
      await guidelines(tester);
      handle.dispose();
    });
  });
}

/// Ends the app and lets the time limits of finished MCP requests (timers
/// in the test's fake clock) run out.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await settle(tester);
  await tester.pump(const Duration(minutes: 1));
}

/// Four servers in the states of the design: active, login missing, not
/// reachable, switched off.
List<({McpServerConfig config, List<McpToolInfo> tools, McpCheck? check})>
_goldenServers() {
  final at = testNow;
  McpCheck check(McpReachability status, {String? detail}) => McpCheck(
    at: at,
    status: status,
    detail: detail,
    latency: const Duration(milliseconds: 42),
    serverName: 'fake-mcp 1.0.0',
  );
  return [
    (
      config: McpServerConfig(
        id: 'home',
        name: 'Home Assistant',
        slug: 'home',
        url: Uri.parse('http://homeassistant.local:8123/api/mcp'),
        auth: McpBearerAuth(McpSecretRefs.bearer('home')),
        toolOverrides: {'set_light': const McpToolOverride(autoRun: true)},
      ),
      tools: homeToolInfos(),
      check: check(McpReachability.reachable),
    ),
    (
      config: McpServerConfig(
        id: 'notes',
        name: 'Obsidian Desktop',
        slug: 'notes',
        url: Uri.parse('https://desktop.tail1234.ts.net/mcp'),
        auth: McpOAuth(
          tokenRef: McpSecretRefs.oauthToken('notes'),
          clientRef: McpSecretRefs.oauthClient('notes'),
        ),
        // Lang mit zwei Badges: die Badges rücken in die nächste Zeile.
        sensitive: true,
      ),
      tools: const [],
      check: null,
    ),
    (
      config: McpServerConfig(
        id: 'kalender',
        name: 'Kalender',
        slug: 'kalender',
        url: Uri.parse('http://homeserver.tail1234.ts.net:3000/mcp'),
      ),
      tools: homeToolInfos().take(1).toList(),
      check: check(
        McpReachability.unreachable,
        detail: 'Server nicht erreichbar (Connection refused)',
      ),
    ),
    (
      config: McpServerConfig(
        id: 'werkstatt',
        name: 'Werkstatt',
        slug: 'werkstatt',
        url: Uri.parse('https://werkstatt.example.org/mcp'),
        sensitive: true,
      ),
      tools: homeToolInfos(),
      check: null,
    ),
  ];
}
