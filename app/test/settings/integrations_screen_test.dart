import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin/ui/settings/integrations_screen.dart';
import 'package:wendelin/ui/settings/lists_screen.dart';
import 'package:wendelin/ui/settings/web_search_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';

Future<ProviderContainer> pumpIntegrations(
  WidgetTester tester,
  TestEnv env, {
  Size size = const Size(390, 1400),
}) async {
  setView(tester, size);
  await tester.pumpWidget(env.app(home: const IntegrationsScreen()));
  await tester.pumpAndSettle();
  final c = ProviderScope.containerOf(
    tester.element(find.byType(IntegrationsScreen)),
  );
  await tester.runAsync(() => c.read(toolRegistryProvider).refresh());
  await tester.pumpAndSettle();
  return c;
}

/// Lets database work finish (it runs outside the fake clock) and pumps.
Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pumpAndSettle();
}

Finder tile(String name) => find.widgetWithText(IntegrationTile, name);

Finder switchOf(String name) =>
    find.descendant(of: tile(name), matching: find.byType(WSwitch));

IntegrationTile tileWidget(WidgetTester tester, String name) =>
    tester.widget<IntegrationTile>(tile(name));

void main() {
  testWidgets('alle Integrationen mit Zustand und Toolzahl', (tester) async {
    final env = TestEnv(enabled: const {'memory', 'web'});
    await pumpIntegrations(tester, env);
    expect(find.byType(IntegrationTile), findsNWidgets(6));
    expect(tileWidget(tester, 'Gedächtnis').status, IntegrationStatus.active);
    expect(tileWidget(tester, 'Gedächtnis').detail, '3 Tools');
    expect(tileWidget(tester, 'Gedächtnis').sensitive, isTrue);
    expect(tileWidget(tester, 'Kalender').status, IntegrationStatus.available);
    // Ohne Suchdienst ist Web aktiv, nur mit web__fetch (WP14).
    final web = tileWidget(tester, 'Web');
    expect(web.status, IntegrationStatus.active);
    expect(web.detail, '1 Tool');
  });

  testWidgets('Einschalten: erst Erklärung, dann Berechtigung', (tester) async {
    final env = TestEnv(enabled: const {});
    env.calendar.permissionGranted = false;
    await pumpIntegrations(tester, env);
    expect(env.permissionRequests, 0, reason: 'nicht beim Öffnen');

    await tester.tap(switchOf('Kalender'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Zugriff auf deine Kalender'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(env.permissionRequests, 0, reason: 'abgebrochen');
    expect(tileWidget(tester, 'Kalender').status, IntegrationStatus.available);

    await tester.tap(switchOf('Kalender'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await settle(tester);
    expect(env.permissionRequests, 1);
    expect(tileWidget(tester, 'Kalender').status, IntegrationStatus.active);
  });

  testWidgets('ohne Berechtigungsbedarf: sofort an, keine Erklärung', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {});
    await pumpIntegrations(tester, env);
    await tester.tap(switchOf('Zwischenablage'));
    await tester.pumpAndSettle();
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      tileWidget(tester, 'Zwischenablage').status,
      IntegrationStatus.active,
    );
    expect(env.permissionRequests, 0);
  });

  testWidgets('„Einrichten“ bei Listen öffnet die Listen-Seite', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'lists'});
    await pumpIntegrations(tester, env);
    expect(
      tileWidget(tester, 'Listen').status,
      IntegrationStatus.setupRequired,
    );
    await tester.tap(
      find.descendant(
        of: tile('Listen'),
        matching: find.byType(OutlinedButton),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ListsScreen), findsOneWidget);
  });

  testWidgets('Web-Detail führt zur Suchdienst-Einrichtung', (tester) async {
    final env = TestEnv(enabled: const {'web'});
    await pumpIntegrations(tester, env);
    await tester.tap(find.text('Web'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Suchdienst einrichten'));
    await tester.pumpAndSettle();
    expect(find.byType(WebSearchScreen), findsOneWidget);
  });

  testWidgets('Detail: Tool aus, „Immer nachfragen“, external fragt immer', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'calendar'});
    final c = await pumpIntegrations(tester, env);
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    expect(find.byType(IntegrationDetailScreen), findsOneWidget);
    expect(find.text('calendar__delete_event'), findsOneWidget);
    expect(find.text('Außenwirkung · fragt immer nach'), findsOneWidget);

    // Tool ausschalten → geht nicht mehr ans Modell.
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(InkWell, 'calendar__list_events'),
        matching: find.byType(WSwitch),
      ),
    );
    await tester.pumpAndSettle();
    final registry = c.read(toolRegistryProvider);
    expect(registry.isToolEnabled('calendar__list_events'), isFalse);
    expect(
      registry
          .activeSpecsFor(PrivacyLevel.local, sessionId: 's')
          .map((t) => t.name),
      isNot(contains('calendar__list_events')),
    );

    // write-Tool auf „Immer nachfragen“ → Policy fragt.
    await tester.tap(find.text('calendar__create_event'));
    await tester.pumpAndSettle();
    expect(find.text('ändert · fragt immer nach'), findsOneWidget);
    final policy = c.read(riskPolicyProvider);
    final create = c
        .read(integrationsProvider)['calendar']!
        .tools
        .firstWhere((t) => t.name == 'calendar__create_event');
    expect(policy.decide(create, 's').action, PolicyAction.confirm);

    // external lässt sich nicht lockern.
    await tester.tap(find.text('calendar__delete_event'));
    await tester.pumpAndSettle();
    expect(find.text('Außenwirkung · fragt immer nach'), findsOneWidget);

    // Zurücknehmen und gespeichert.
    await tester.tap(find.text('calendar__create_event'));
    await tester.pumpAndSettle();
    expect(policy.decide(create, 's').action, PolicyAction.allow);
    final stored = c.read(toolPrefsProvider);
    expect(stored.disabled, {'calendar__list_events'});
    expect(stored.alwaysConfirm, isEmpty);
  });

  testWidgets('Detail: Stufe für sensible Integrationen', (tester) async {
    final env = TestEnv(enabled: const {'calendar'});
    final c = await pumpIntegrations(tester, env);
    await tester.tap(find.text('Kalender'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Ab TEE'), 200);
    await tester.tap(find.text('Ab TEE'));
    await tester.pumpAndSettle();
    final registry = c.read(toolRegistryProvider);
    expect(registry.sensitiveMinimum, PrivacyLevel.tee);
    expect(
      registry.activeSpecsFor(PrivacyLevel.standard, sessionId: 's'),
      isEmpty,
      reason: 'Kalender ist sensibel',
    );
    expect(
      registry.activeSpecsFor(PrivacyLevel.tee, sessionId: 's'),
      isNotEmpty,
    );
  });

  testWidgets('MCP/HTTP-Tool: Hinweis auf M3', (tester) async {
    await pumpIntegrations(tester, TestEnv());
    await tester.tap(find.text('+ MCP-Server'));
    await tester.pump();
    expect(find.text('Kommt mit M3.'), findsOneWidget);
  });

  testWidgets('Golden Integrationen (390 × 844)', tags: ['golden'], (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'calendar', 'memory', 'web', 'lists'});
    env.alarms.available = false;
    await pumpIntegrations(tester, env, size: screenSize);
    await expectLater(
      find.byType(IntegrationsScreen),
      matchesGoldenFile('goldens/integrationen.png'),
    );
  });
}
