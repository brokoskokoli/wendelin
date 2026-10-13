import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/user_integrations.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/coming_soon_screen.dart';
import 'package:wendelin/ui/settings/http_tool_editor_screen.dart';
import 'package:wendelin/ui/settings/http_tools_screen.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin/ui/settings/routing/routing_screen.dart';
import 'package:wendelin/ui/settings/settings_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';

import '../support/fake_user_integrations.dart';
import '../support/test_env.dart';
import 'integrations_screen_test.dart';
import 'other_screens_test.dart' show pumpPage;

void main() {
  testWidgets('Übersicht: Routing öffnet den Editor, MCP-Server führt zum '
      'Platzhalter, HTTP-Tools zur Liste', (tester) async {
    await pumpPage(tester, TestEnv(), const SettingsScreen());
    final titles = [for (final (t, _, _) in SettingsScreen.areas) t];
    expect(titles.take(5), [
      'Provider',
      'Routing',
      'Integrationen',
      'MCP-Server',
      'HTTP-Tools',
    ]);
    await tester.tap(find.text('Routing'));
    await settle(tester);
    expect(find.byType(RoutingScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await settle(tester);
    for (final title in ['MCP-Server']) {
      await tester.tap(find.text(title));
      await settle(tester);
      expect(find.byType(ComingSoonScreen), findsOneWidget, reason: title);
      expect(find.text('Kommt in M3'), findsOneWidget);
      await tester.tap(find.byTooltip('Zurück'));
      await settle(tester);
    }
    await tester.tap(find.text('HTTP-Tools'));
    await settle(tester);
    expect(find.byType(HttpToolsScreen), findsOneWidget);
  });

  testWidgets('„+ MCP-Server“ und „+ HTTP-Tool“ öffnen ihre Bereiche', (
    tester,
  ) async {
    await pumpIntegrations(tester, TestEnv());
    await tester.tap(find.text('+ MCP-Server'));
    await settle(tester);
    expect(find.widgetWithText(ComingSoonScreen, 'MCP-Server'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await settle(tester);
    await tester.tap(find.text('+ HTTP-Tool'));
    await settle(tester);
    expect(find.byType(HttpToolEditorScreen), findsOneWidget);
    expect(find.text('Neues HTTP-Tool'), findsOneWidget);
  });

  testWidgets('eigene Integrationen: eigener Abschnitt mit MCP/HTTP, '
      'Schalter, Detail, Abweisung', (tester) async {
    final mcp = FakeUserIntegrationSource(
      integrations: [
        userIntegration('mcp_home', displayName: 'Homeserver', tools: ['git']),
      ],
    );
    final http = FakeUserIntegrationSource(
      kind: UserIntegrationKind.http,
      integrations: [
        userIntegration('http_ha', displayName: 'Home Assistant'),
        // Kollidiert mit einem eingebauten Tool.
        userIntegration('http_bad', tools: ['calendar__list_events']),
      ],
    );
    final env = TestEnv(
      enabled: const {},
      extraOverrides: [
        userIntegrationSourcesProvider.overrideWithValue([mcp, http]),
      ],
    );
    await pumpIntegrations(tester, env);
    // The sync runs in the test's fake zone: let it work in steps.
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }

    expect(find.text('Eigene Integrationen'), findsOneWidget);
    expect(tileWidget(tester, 'Homeserver').kind, 'MCP');
    expect(tileWidget(tester, 'Home Assistant').kind, 'HTTP');
    expect(tileWidget(tester, 'Kalender').kind, isNull);
    expect(find.text('MCP'), findsOneWidget);
    expect(find.text('HTTP'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Homeserver, MCP',
      ),
      findsOneWidget,
      reason: 'Badge wird mit vorgelesen',
    );
    expect(find.textContaining('Abgewiesen: Tool-Name'), findsOneWidget);
    // Eigene stehen unter den eingebauten.
    expect(
      tester.getTopLeft(tile('Homeserver')).dy,
      greaterThan(tester.getTopLeft(tile('Web')).dy),
    );

    await tester.tap(switchOf('Homeserver'));
    await settle(tester);
    expect(tileWidget(tester, 'Homeserver').status, IntegrationStatus.active);

    await tester.tap(find.text('Homeserver'));
    await settle(tester);
    expect(find.byType(IntegrationDetailScreen), findsOneWidget);
    expect(find.text('mcp_home__git'), findsOneWidget);
    await tester.tap(find.byTooltip('Zurück'));
    await settle(tester);

    // Gelöscht: verschwindet aus der Liste.
    mcp.update([]);
    // The sync runs in the test's fake zone: let it work in steps.
    for (var i = 0; i < 3; i++) {
      await settle(tester);
    }
    expect(find.text('Homeserver'), findsNothing);
    expect(mcp.deletedSecrets, ['mcp_home']);
  });

  testWidgets('ohne eigene Integrationen kein Abschnitt', (tester) async {
    await pumpIntegrations(tester, TestEnv());
    expect(find.text('Eigene Integrationen'), findsNothing);
    expect(find.byType(IntegrationTile), findsNWidgets(8));
  });
}
