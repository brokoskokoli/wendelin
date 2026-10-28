// WP164 B: Waze als zweite Navigations-App. Ein Tool `maps__navigate` für
// beide, Auswahl per Einstellung und per Argument `app`, fail-closed.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_requirements.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/ui/settings/integration_detail_screen.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../settings/integrations_screen_test.dart'
    show pumpIntegrations, settle, switchOf, tile, tileWidget;
import '../settings/other_screens_test.dart' show pumpPage;
import '../support/test_env.dart';

ToolContext _ctx() => ToolContext(
  sessionId: 's',
  clock: FixedClock(testNow),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);

Future<ToolRegistry> _registry(ProviderContainer c) async {
  final registry = c.read(toolRegistryProvider);
  await registry.refresh();
  return registry;
}

Tool? _navigate(ToolRegistry r) =>
    r.catalogFor(PrivacyLevel.local, sessionId: 's').lookup('maps__navigate');

List<Object?> _appEnum(Tool t) =>
    ((t.inputSchema['properties']! as Map)['app']! as Map)['enum']!
        as List<Object?>;

void main() {
  group('Tool-Sichtbarkeit je Integrationsstand', () {
    for (final (enabled, offered) in <(Set<String>, List<String>?)>[
      ({}, null),
      ({'maps'}, ['google_maps']),
      ({'waze'}, ['waze']),
      ({'maps', 'waze'}, ['google_maps', 'waze']),
    ]) {
      test('an: $enabled -> $offered', () async {
        final env = TestEnv(enabled: enabled);
        final c = env.container();
        addTearDown(c.dispose);
        final tool = _navigate(await _registry(c));
        if (offered == null) {
          expect(tool, isNull);
        } else {
          expect(tool, isNotNull);
          expect(_appEnum(tool!), offered);
        }
      });
    }

    test('Waze nicht installiert: Integration nicht verfügbar, kein Tool, '
        'keine Option', () async {
      final env = TestEnv(enabled: const {'waze'});
      env.apps.uninstall(KnownApps.waze.androidPackage);
      final c = env.container();
      addTearDown(c.dispose);
      final registry = await _registry(c);
      expect(registry.status('waze'), IntegrationStatus.unavailable);
      expect(_navigate(registry), isNull);
      // Maps zusätzlich an: Tool da, aber ohne Waze-Option.
      await c
          .read(integrationActivatorProvider)
          .setEnabled('maps', enabled: true);
      expect(_appEnum(_navigate(registry)!), ['google_maps']);
    });

    test('Waze ist eine Integration ohne eigene Tools', () async {
      final env = TestEnv(enabled: const {'waze'});
      final c = env.container();
      addTearDown(c.dispose);
      final registry = await _registry(c);
      expect(registry.status('waze'), IntegrationStatus.active);
      expect(registry.info('waze').integration.tools.map((t) => t.name), [
        'maps__navigate',
      ]);
      expect(
        registry
            .catalogFor(PrivacyLevel.local, sessionId: 's')
            .activeSpecs()
            .where((s) => s.name.startsWith('waze__')),
        isEmpty,
      );
    });
  });

  group('Auswahl der App', () {
    Future<ToolOutcome> go(
      ToolRegistry r, [
      Map<String, Object?> a = const {},
    ]) => _navigate(r)!.execute({'destination': 'Hafen', ...a}, _ctx());

    test('Standard: Google Maps; ohne Maps nur Waze: Waze', () async {
      final env = TestEnv(enabled: const {'maps', 'waze'});
      final c = env.container();
      addTearDown(c.dispose);
      final r = await _registry(c);
      final o = await go(r);
      expect(o.text, 'Google Maps ist geöffnet.');
      expect(env.mapsLauncher.launched.single.package, googleMapsPackage);
      await c
          .read(integrationActivatorProvider)
          .setEnabled('maps', enabled: false);
      final w = await go(r);
      expect(w.text, 'Waze ist geöffnet.');
      expect(env.mapsLauncher.launched.last.package, wazePackage);
    });

    test('Einstellung „Navigations-App“ und Argument app', () async {
      final env = TestEnv(
        startup: const StartupSettings(
          enabledIntegrations: {'maps', 'waze'},
          navigationApp: 'waze',
        ),
      );
      final c = env.container();
      addTearDown(c.dispose);
      final r = await _registry(c);
      expect(c.read(navigationAppProvider), NavigationApp.waze);
      expect((await go(r)).text, 'Waze ist geöffnet.');
      expect(
        env.mapsLauncher.launched.last.uri.toString(),
        'https://waze.com/ul?q=Hafen&navigate=yes',
      );
      // Das Argument schlägt die Einstellung.
      expect(
        (await go(r, {'app': 'google_maps'})).text,
        'Google Maps ist geöffnet.',
      );
      // Eine Änderung der Einstellung gilt für den nächsten Aufruf.
      await c
          .read(navigationAppProvider.notifier)
          .set(NavigationApp.googleMaps);
      expect((await go(r)).text, 'Google Maps ist geöffnet.');
      await c.read(navigationAppProvider.notifier).set(null);
      expect(c.read(navigationAppProvider), isNull);
    });

    test('gewählte App nicht verfügbar: Fehler, kein Wechsel', () async {
      final env = TestEnv(
        startup: const StartupSettings(
          enabledIntegrations: {'maps', 'waze'},
          navigationApp: 'waze',
        ),
      );
      final c = env.container();
      addTearDown(c.dispose);
      final r = await _registry(c);
      // Waze wird nach der Prüfung deinstalliert: die Live-Prüfung greift.
      env.apps.uninstall(KnownApps.waze.androidPackage);
      final gone = await go(r);
      expect(gone.isError, isTrue);
      expect(gone.text, contains('Waze'));
      // Waze ausgeschaltet, aber noch Einstellung/Argument: Fehler.
      await c
          .read(integrationActivatorProvider)
          .setEnabled('waze', enabled: false);
      expect((await go(r)).isError, isTrue);
      expect((await go(r, {'app': 'waze'})).isError, isTrue);
      expect(env.mapsLauncher.launched, isEmpty);
    });
  });

  testWidgets('Integrationsliste: Waze antippbar, Hinweis bei fehlender App', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {});
    env.apps.uninstall(KnownApps.waze.androidPackage);
    await pumpIntegrations(tester, env);
    expect(tile('Waze'), findsOneWidget);
    expect(tileWidget(tester, 'Waze').status, IntegrationStatus.unavailable);
    expect(find.text('App nicht installiert'), findsWidgets);

    env.apps.install(KnownApps.waze.androidPackage);
    final c = ProviderScope.containerOf(tester.element(tile('Waze')));
    await tester.runAsync(() => c.read(toolRegistryProvider).refresh());
    await tester.pumpAndSettle();
    await tester.tap(switchOf('Waze'));
    await settle(
      tester,
      until: () =>
          tileWidget(tester, 'Waze').status == IntegrationStatus.active,
    );
    expect(tileWidget(tester, 'Waze').status, IntegrationStatus.active);
    expect(tileWidget(tester, 'Waze').detail, '1 Tool');
  });

  testWidgets('Einstellung „Navigations-App“ in den Details, speichert', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'maps', 'waze'});
    final c = await pumpPage(
      tester,
      env,
      const IntegrationDetailScreen('waze'),
    );
    expect(find.text('Navigations-App'), findsOneWidget);
    expect(find.text('Standard (Google Maps, sonst Waze)'), findsOneWidget);
    expect(c.read(navigationAppProvider), isNull);
    await tester.tap(find.widgetWithText(InkWell, 'Waze').last);
    await settle(tester);
    expect(c.read(navigationAppProvider), NavigationApp.waze);
    await tester.tap(find.text('Standard (Google Maps, sonst Waze)'));
    await settle(tester);
    expect(c.read(navigationAppProvider), isNull);
  });

  testWidgets('Navigations-App nur bei Maps und Waze', (tester) async {
    await pumpPage(
      tester,
      TestEnv(enabled: const {'memory'}),
      const IntegrationDetailScreen('memory'),
    );
    expect(find.byKey(const ValueKey('navigationAppSection')), findsNothing);
  });
}
