import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_requirements.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/integration_specs.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/l10n/gen/app_localizations_de.dart';
import 'package:wendelin/ui/design/design.dart';
import 'package:wendelin/ui/onboarding/onboarding_screen.dart';
import 'package:wendelin/ui/settings/integrations_screen.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../support/test_env.dart';
import '../ui/helpers.dart';
import 'integrations_screen_test.dart';
import 'onboarding_test.dart' show seedProvider;

const spotifyPkg = 'com.spotify.music';

/// An integration that needs Spotify (like the planned Spotify one).
FakeIntegration spotify() => FakeIntegration(
  id: 'spotify',
  displayName: 'Spotify',
  tools: [FakeTool(name: 'spotify__play', risk: RiskLevel.write)],
);

/// Built-ins plus [extra] specs, with a recording URL launcher.
List<Override> specOverrides(
  List<IntegrationSpec> extra,
  List<Uri> opened, {
  Future<void> Function(Uri)? launcher,
}) => [
  integrationSpecsProvider.overrideWithValue([
    ...builtInIntegrationSpecs,
    ...extra,
  ]),
  urlLauncherProvider.overrideWithValue(
    launcher ?? (url) async => opened.add(url),
  ),
];

IntegrationSpec spotifySpec(FakeIntegration i) => IntegrationSpec(
  id: 'spotify',
  create: (_) => i,
  requiredApp: KnownApps.spotify,
);

/// To the background and back into the app.
Future<void> resume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await settle(tester);
}

List<String> activeTools(ProviderContainer c) => [
  for (final s
      in c
          .read(toolRegistryProvider)
          .activeSpecsFor(PrivacyLevel.local, sessionId: 's'))
    s.name,
];

void main() {
  testWidgets('fehlende Pflicht-App: ausgegraut, Hinweis, Link zum Store', (
    tester,
  ) async {
    final opened = <Uri>[];
    final env = TestEnv(
      enabled: const {},
      extraOverrides: specOverrides([spotifySpec(spotify())], opened),
    );
    env.apps.uninstall(spotifyPkg);
    await pumpIntegrations(tester, env);

    final t = tileWidget(tester, 'Spotify');
    expect(t.status, IntegrationStatus.unavailable);
    expect(t.detail, 'App nicht installiert');
    expect(
      find.descendant(of: tile('Spotify'), matching: find.byType(WSwitch)),
      findsNothing,
    );
    // Unten in der Liste, wie im Entwurf.
    expect(
      tester.getTopLeft(tile('Spotify')).dy,
      greaterThan(tester.getTopLeft(tile('Web')).dy),
    );
    await tester.tap(find.text('Im Store'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(KnownApps.spotify.storeUrl)]);
    expect(env.apps.queries, contains(spotifyPkg));
  });

  testWidgets('Store-Link ohne Browser: Adresse als Hinweis', (tester) async {
    final env = TestEnv(
      enabled: const {},
      extraOverrides: specOverrides(
        [spotifySpec(spotify())],
        [],
        launcher: (url) async => throw const PortException(
          PortErrorKind.unavailable,
          'kein Browser',
        ),
      ),
    );
    env.apps.uninstall(spotifyPkg);
    await pumpIntegrations(tester, env);
    await tester.tap(find.text('Im Store'));
    await tester.pump();
    expect(find.text(KnownApps.spotify.storeUrl), findsOneWidget);
  });

  testWidgets('App kommt hinzu: nach Rückkehr in die App verfügbar', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {},
      extraOverrides: specOverrides([spotifySpec(spotify())], []),
    );
    env.apps.uninstall(spotifyPkg);
    await pumpIntegrations(tester, env);
    expect(tileWidget(tester, 'Spotify').status, IntegrationStatus.unavailable);

    env.apps.install(spotifyPkg);
    await settle(tester);
    expect(
      tileWidget(tester, 'Spotify').status,
      IntegrationStatus.unavailable,
      reason: 'erst bei Rückkehr geprüft',
    );
    await resume(tester);
    expect(tileWidget(tester, 'Spotify').status, IntegrationStatus.available);
    expect(find.text('Im Store'), findsNothing);
  });

  testWidgets('App fällt weg: pausiert, Schalter bleibt gespeichert', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {},
      extraOverrides: specOverrides([spotifySpec(spotify())], []),
    );
    final c = await pumpIntegrations(tester, env);
    await tester.tap(switchOf('Spotify'));
    await settle(tester);
    expect(tileWidget(tester, 'Spotify').status, IntegrationStatus.active);
    expect(activeTools(c), contains('spotify__play'));

    env.apps.uninstall(spotifyPkg);
    await resume(tester);
    final t = tileWidget(tester, 'Spotify');
    expect(t.status, IntegrationStatus.unavailable);
    expect(t.detail, 'App nicht installiert · pausiert');
    expect(activeTools(c), isNot(contains('spotify__play')));
    expect(c.read(toolRegistryProvider).info('spotify').enabled, isTrue);
    expect(c.read(enabledIntegrationsProvider), contains('spotify'));
    expect(
      await env.storage.settings.get(AppSettings.integrationEnabled('spotify')),
      isTrue,
    );

    // Wieder installiert: ohne Zutun wieder aktiv.
    env.apps.install(spotifyPkg);
    await resume(tester);
    expect(tileWidget(tester, 'Spotify').status, IntegrationStatus.active);
    expect(activeTools(c), contains('spotify__play'));
  });

  testWidgets('Prüfung fehlgeschlagen: Fehler statt still aktiv', (
    tester,
  ) async {
    final env = TestEnv(
      enabled: const {'spotify'},
      // Only Spotify: no other app check may take the injected failure.
      extraOverrides: [
        integrationSpecsProvider.overrideWithValue([spotifySpec(spotify())]),
      ],
    );
    await pumpIntegrations(tester, env);
    expect(tileWidget(tester, 'Spotify').status, IntegrationStatus.active);
    env.apps.failNext('isInstalled');
    await resume(tester);
    expect(tileWidget(tester, 'Spotify').status, IntegrationStatus.error);
  });

  testWidgets('optionale App fehlt: nur ein Hinweis (Obsidian)', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {});
    env.apps.uninstall(KnownApps.obsidian.androidPackage);
    final c = await pumpIntegrations(tester, env);
    final t = tileWidget(tester, 'Obsidian');
    expect(t.status, IntegrationStatus.available);
    expect(t.detail, 'Obsidian-App fehlt: Öffnen in Obsidian geht nicht');
    expect(c.read(installedAppsProvider)['md.obsidian'], isFalse);

    env.apps.install(KnownApps.obsidian.androidPackage);
    await resume(tester);
    expect(tileWidget(tester, 'Obsidian').detail, isNull);
  });

  testWidgets('optionale App, Prüfung scheitert: Obsidian bleibt nutzbar', (
    tester,
  ) async {
    final env = TestEnv(enabled: const {'obsidian'});
    final c = await pumpIntegrations(tester, env);
    expect(
      tileWidget(tester, 'Obsidian').status,
      IntegrationStatus.setupRequired,
      reason: 'ohne Vault',
    );
    env.apps.failNext('isInstalled');
    await resume(tester);
    final t = tileWidget(tester, 'Obsidian');
    expect(t.status, IntegrationStatus.setupRequired, reason: 'kein Fehler');
    expect(t.detail, 'Obsidian-Vault-Ordner wählen', reason: 'kein Hinweis');
    expect(c.read(installedAppsProvider)['md.obsidian'], isNull);
    expect(env.apps.methodCalls.length, greaterThan(1));
  });

  test('integrationDetail: aktive Integration mit App-Hinweis', () {
    final info = IntegrationInfo(
      integration: spotify(),
      status: IntegrationStatus.active,
      enabled: true,
      availability: Availability.yes,
      setup: SetupState(),
    );
    expect(integrationDetail(AppLocalizationsDe(), info), '1 Tool');
    expect(
      integrationDetail(AppLocalizationsDe(), info, appHint: 'App fehlt'),
      '1 Tool · App fehlt',
    );
  });

  testWidgets('Onboarding: nur Integrationen der Plattform, fehlende Apps '
      'ausgegraut', (tester) async {
    final opened = <Uri>[];
    final env = TestEnv(
      startup: const StartupSettings(
        setupWizardDone: false,
        setupWizardPage: 'integrations',
      ),
      storedProfiles: true,
      extraOverrides: specOverrides([
        spotifySpec(spotify()),
        IntegrationSpec(
          id: 'shortcuts',
          create: (_) => FakeIntegration(
            id: 'shortcuts',
            displayName: 'Kurzbefehle',
            platforms: const {AppPlatform.ios},
            tools: [FakeTool(name: 'shortcuts__run')],
          ),
        ),
      ], opened),
    );
    env.apps.uninstall(spotifyPkg);
    // The required pages before are met, the wizard starts at the integrations.
    await seedProvider(env);
    env.speechModels.installed.addAll(['whisper-small', 'silero-vad']);
    setView(tester, const Size(390, 1800));
    await tester.pumpWidget(env.app());
    await settle(tester);
    final c = ProviderScope.containerOf(
      tester.element(find.byType(OnboardingScreen)),
    );
    expect(find.text('Was darf Wendelin?'), findsOneWidget);
    await tester.runAsync(() => c.read(toolRegistryProvider).refresh());
    await tester.pumpAndSettle();

    expect(find.text('Kurzbefehle'), findsNothing, reason: 'nur iOS');
    final t = tileWidget(tester, 'Spotify');
    expect(t.status, IntegrationStatus.unavailable);
    expect(t.detail, 'App nicht installiert');
    await tester.tap(find.text('Im Store'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
  });
}
