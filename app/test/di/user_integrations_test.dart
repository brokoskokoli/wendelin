import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/user_integrations.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';
import 'package:wendelin_tools/wendelin_tools.dart';

import '../support/fake_user_integrations.dart';
import '../support/test_env.dart';

List<String> activeTools(ToolRegistry r) => [
  for (final s in r.activeSpecsFor(PrivacyLevel.local, sessionId: 's')) s.name,
];

void main() {
  late ToolRegistry registry;
  late WendelinStorage storage;
  final errors = <Object>[];

  setUp(() {
    registry = ToolRegistry();
    storage = openInMemoryStorage(clock: FixedClock(testNow));
    errors.clear();
  });

  tearDown(() async {
    await registry.dispose();
    await storage.close();
  });

  UserIntegrationSync sync(List<UserIntegrationSource> sources) =>
      UserIntegrationSync(
        registry: ToolRegistryUserIntegrations(registry),
        sources: sources,
        switches: SettingsUserIntegrationSwitches(storage.settings),
        onError: (e, _) => errors.add(e),
      );

  test('Neustart stellt den gespeicherten Schalter wieder her', () async {
    await storage.settings.set(AppSettings.integrationEnabled('mcp_on'), true);
    final source = FakeUserIntegrationSource(
      integrations: [userIntegration('mcp_on'), userIntegration('mcp_off')],
    );
    final s = sync([source]);
    await s.ready;
    expect(registry.info('mcp_on').enabled, isTrue);
    expect(registry.status('mcp_on'), IntegrationStatus.active);
    expect(registry.info('mcp_off').enabled, isFalse);
    expect(source.deletedSecrets, isEmpty, reason: 'Start löscht nichts');
    await s.dispose();
  });

  test('Namenskollision wird abgewiesen statt zu überschreiben', () async {
    await registry.registerIntegration(
      FakeIntegration(
        id: 'calendar',
        tools: [FakeTool(name: 'calendar__x')],
      ),
      enabled: true,
    );
    final source = FakeUserIntegrationSource(
      integrations: [
        // Gleiche Id wie eine eingebaute.
        userIntegration('calendar', tools: ['y']),
        // Tool-Name einer anderen Integration.
        userIntegration('mcp_a', tools: ['calendar__x']),
        userIntegration('mcp_b', tools: ['tools__search']),
      ],
    );
    final s = sync([source]);
    await s.ready;
    expect(registry.integrations.map((i) => i.id), ['calendar']);
    expect(activeTools(registry), ['calendar__x']);
    expect(s.rejected.keys, unorderedEquals(['calendar', 'mcp_a', 'mcp_b']));
    expect(s.rejected['mcp_a'], contains('calendar__x'));
    expect(s.rejected['calendar'], contains('schon vergeben'));
    expect(s.rejected['mcp_b'], contains('reserviert'));
    expect(s.kindOf('calendar'), isNull);

    // Änderung, die kollidiert: die alte Fassung bleibt registriert.
    source.update([
      userIntegration('mcp_c', tools: ['ok']),
    ]);
    await s.settled();
    registry.setEnabled('mcp_c', enabled: true);
    source.update([
      userIntegration('mcp_c', tools: ['ok', 'calendar__x']),
    ]);
    await s.settled();
    expect(activeTools(registry), ['calendar__x', 'mcp_c__ok']);
    expect(registry.info('mcp_c').enabled, isTrue);
    expect(s.rejected.keys, ['mcp_c']);
    expect(source.deletedSecrets, isEmpty, reason: 'abgewiesen ≠ gelöscht');
    await s.dispose();
  });

  group('verdrahtet (Provider)', () {
    test('einzelnes Tool fällt weg: Markierung und Schalter bleiben', () async {
      final source = FakeUserIntegrationSource(
        kind: UserIntegrationKind.http,
        integrations: [
          userIntegration('http', tools: ['http__a', 'http__b']),
        ],
      );
      final env = TestEnv(
        enabled: const {},
        extraOverrides: [
          userIntegrationSourcesProvider.overrideWithValue([source]),
        ],
      );
      final c = env.container();
      await c.read(toolRegistryReadyProvider.future);
      await c
          .read(integrationActivatorProvider)
          .setEnabled('http', enabled: true);
      await c
          .read(toolPrefsProvider.notifier)
          .set(
            const ToolPrefs(
              disabled: {'http__a', 'http__b'},
              alwaysConfirm: {'http__a', 'http__b'},
              sensitive: {'http': true},
            ),
          );
      await c.read(toolRegistryReadyProvider.future);
      source.update([
        userIntegration('http', tools: ['http__b']),
      ]);
      await c.read(userIntegrationSyncProvider).settled();

      final prefs = c.read(toolPrefsProvider);
      expect(prefs.disabled, {'http__b'});
      expect(prefs.alwaysConfirm, {'http__b'});
      expect(prefs.sensitive, {'http': true});
      expect(c.read(enabledIntegrationsProvider), contains('http'));
      // Storing the prefs rebuilds the registry: wait for the new one.
      final registry = await c.read(toolRegistryReadyProvider.future);
      expect(registry.info('http').enabled, isTrue);
      expect(registry.info('http').integration.sensitive, isTrue);
      expect(
        await env.storage.settings.get(AppSettings.integrationEnabled('http')),
        isTrue,
      );
      c.dispose();
    });

    test(
      'http fällt weg: sensible HTTP-Tools behalten ihre Einstellungen',
      () async {
        final source = FakeUserIntegrationSource(
          kind: UserIntegrationKind.http,
          integrations: [
            userIntegration('http', tools: ['http__a']),
            userIntegration('http_sensitive', tools: ['http__s']),
          ],
        );
        final env = TestEnv(
          enabled: const {},
          extraOverrides: [
            userIntegrationSourcesProvider.overrideWithValue([source]),
          ],
        );
        final c = env.container();
        await c.read(toolRegistryReadyProvider.future);
        await c
            .read(toolPrefsProvider.notifier)
            .set(
              const ToolPrefs(
                disabled: {'http__a', 'http__s'},
                alwaysConfirm: {'http__a', 'http__s'},
                sensitive: {'http_sensitive': true, 'http': false},
              ),
            );
        // Rebuilt with the marks: wait for the new sync.
        await c.read(toolRegistryReadyProvider.future);
        source.update([
          userIntegration('http_sensitive', tools: ['http__s']),
        ]);
        await c.read(userIntegrationSyncProvider).settled();
        final prefs = c.read(toolPrefsProvider);
        expect(prefs.disabled, {'http__s'});
        expect(prefs.alwaysConfirm, {'http__s'});
        expect(prefs.sensitive, {'http_sensitive': true});
        c.dispose();
      },
    );

    test('Schalter über den Aktivator, Neustart, Löschen räumt auf', () async {
      final source = FakeUserIntegrationSource(
        integrations: [
          userIntegration('mcp_home', tools: ['git']),
        ],
      );
      final env = TestEnv(
        enabled: const {},
        extraOverrides: [
          userIntegrationSourcesProvider.overrideWithValue([source]),
        ],
      );
      var c = env.container();
      await c.read(toolRegistryReadyProvider.future);
      await c
          .read(integrationActivatorProvider)
          .setEnabled('mcp_home', enabled: true);
      await c
          .read(toolPrefsProvider.notifier)
          .set(
            const ToolPrefs(
              disabled: {'mcp_home__git', 'calendar__list_events'},
              alwaysConfirm: {'mcp_home__git'},
              sensitive: {'mcp_home': true},
            ),
          );
      c.dispose();

      // Neustart: neue Umgebung auf derselben Datenbank, Einstellungen wie
      // in main.dart gelesen.
      final restarted = TestEnv(
        storage: env.storage,
        startup: await StartupSettings.load(env.storage.settings, const []),
        extraOverrides: [
          userIntegrationSourcesProvider.overrideWithValue([source]),
        ],
      );
      c = restarted.container();
      final registry = await c.read(toolRegistryReadyProvider.future);
      expect(registry.info('mcp_home').enabled, isTrue);
      expect(registry.isToolEnabled('mcp_home__git'), isFalse);
      expect(registry.info('mcp_home').integration.sensitive, isTrue);

      source.update([]);
      await c.read(userIntegrationSyncProvider).settled();
      expect(
        registry.integrations.map((i) => i.id),
        isNot(contains('mcp_home')),
      );
      expect(source.deletedSecrets, ['mcp_home']);
      final prefs = c.read(toolPrefsProvider);
      expect(prefs.disabled, {'calendar__list_events'});
      expect(prefs.alwaysConfirm, isEmpty);
      expect(prefs.sensitive, isEmpty);
      expect(c.read(enabledIntegrationsProvider), isNot(contains('mcp_home')));
      c.dispose();
    });
  });
}
