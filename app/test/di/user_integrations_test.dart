import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/preference_models.dart';
import 'package:wendelin/di/preferences.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/startup.dart';
import 'package:wendelin/di/user_integrations.dart';
import 'package:wendelin_core/testing.dart';
import 'package:wendelin_core/wendelin_core.dart';
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

  UserIntegrationSync sync(
    List<UserIntegrationSource> sources, {
    List<IntegrationCleanup> cleanups = const [],
    void Function(Integration)? onRegistered,
  }) => UserIntegrationSync(
    registry: registry,
    sources: sources,
    settings: storage.settings,
    cleanups: cleanups,
    onRegistered: onRegistered,
    onError: (e, _) => errors.add(e),
  );

  test('hinzufügen: registriert, aus bis eingeschaltet, Art bekannt', () async {
    final source = FakeUserIntegrationSource();
    final s = sync([source]);
    await s.ready;
    expect(s.ids, isEmpty);

    source.update([
      userIntegration('mcp_home', tools: ['git', 'docker']),
    ]);
    await s.settled();
    expect(s.ids, ['mcp_home']);
    expect(s.kindOf('mcp_home'), UserIntegrationKind.mcp);
    expect(s.kindOf('calendar'), isNull);
    expect(registry.info('mcp_home').enabled, isFalse);
    registry.setEnabled('mcp_home', enabled: true);
    expect(activeTools(registry), ['mcp_home__docker', 'mcp_home__git']);
    await s.dispose();
  });

  test('ändern: neue Tools ersetzen die alten, Schalter bleibt', () async {
    final source = FakeUserIntegrationSource(
      integrations: [
        userIntegration('mcp_home', tools: ['git']),
      ],
    );
    final registered = <String>[];
    final s = sync([source], onRegistered: (i) => registered.add(i.id));
    await s.ready;
    registry.setEnabled('mcp_home', enabled: true);

    source.update([
      userIntegration('mcp_home', tools: ['git', 'shell']),
    ]);
    await s.settled();
    expect(activeTools(registry), ['mcp_home__git', 'mcp_home__shell']);
    expect(registry.info('mcp_home').enabled, isTrue);
    expect(registered, ['mcp_home', 'mcp_home']);

    // Dasselbe Objekt gilt als unverändert: keine Neuregistrierung.
    source.notify();
    await s.settled();
    expect(registered, hasLength(2));
    await s.dispose();
  });

  test('entfernen: Registry leer, Secrets und Aufräumen aufgerufen', () async {
    final removedHa = userIntegration('http_ha');
    final http = FakeUserIntegrationSource(
      kind: UserIntegrationKind.http,
      integrations: [removedHa, userIntegration('http_n8n')],
    );
    final cleaned = <String>[];
    final s = sync(
      [http],
      cleanups: [
        (r) async => cleaned.add('a:${r.id}'),
        (r) async => throw StateError('kaputt'),
        (r) async => cleaned.add('c:${r.id}'),
      ],
    );
    await s.ready;
    await storage.settings.set(AppSettings.integrationEnabled('http_ha'), true);

    http.update([userIntegration('http_n8n')]);
    await s.settled();
    expect(registry.integrations.map((i) => i.id), ['http_n8n']);
    expect(http.deletedSecrets, ['http_ha']);
    final removal = http.removals.single;
    expect(removal.whole, isTrue);
    expect(removal.toolNames, {'http_ha__ping'});
    expect(
      removal.integration,
      same(removedHa),
      reason: 'Quelle liest Secret-Refs aus der entfernten Fassung',
    );
    expect(cleaned, ['a:http_ha', 'c:http_ha'], reason: 'Fehler stoppt nicht');
    expect(errors.single, isA<StateError>());
    expect(
      await storage.settings.get(AppSettings.integrationEnabled('http_ha')),
      isFalse,
    );

    http.update([]);
    await s.settled();
    expect(registry.integrations, isEmpty);
    expect(http.deletedSecrets, ['http_ha', 'http_n8n']);
    await s.dispose();
  });

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

  test('zwei Quellen mit derselben Id: die zweite wird abgewiesen', () async {
    final mcp = FakeUserIntegrationSource(
      integrations: [userIntegration('dup')],
    );
    final http = FakeUserIntegrationSource(
      kind: UserIntegrationKind.http,
      integrations: [
        userIntegration('dup', tools: ['other']),
      ],
    );
    final s = sync([mcp, http]);
    await s.ready;
    expect(s.kindOf('dup'), UserIntegrationKind.mcp);
    expect(s.rejected.keys, ['dup']);
    await s.dispose();
  });

  test('Ladefehler wird gemeldet, andere Quellen laufen weiter', () async {
    final broken = _ThrowingSource();
    final ok = FakeUserIntegrationSource(
      integrations: [userIntegration('mcp_ok')],
    );
    final s = sync([broken, ok]);
    await s.ready;
    expect(errors.single, isA<StateError>());
    expect(s.ids, ['mcp_ok']);
    await s.dispose();
    // Nach dispose passiert nichts mehr.
    ok.update([]);
    await s.settled();
    expect(registry.integrations.map((i) => i.id), ['mcp_ok']);
  });

  test(
    'ändern: weggefallene Tools werden aufgeräumt, die übrigen nicht',
    () async {
      final source = FakeUserIntegrationSource(
        kind: UserIntegrationKind.http,
        integrations: [
          userIntegration('http', tools: ['http__a', 'http__b']),
        ],
      );
      final cleaned = <IntegrationRemoval>[];
      final s = sync([source], cleanups: [(r) async => cleaned.add(r)]);
      await s.ready;
      final old = source.integrations.single;
      source.update([
        userIntegration('http', tools: ['http__b']),
      ]);
      await s.settled();
      expect(activeTools(registry), isEmpty, reason: 'Schalter aus');
      expect(
        registry.integrations.single.integration.tools.map((t) => t.name),
        ['http__b'],
      );
      final r = cleaned.single;
      expect(r.whole, isFalse);
      expect(r.toolNames, {'http__a'});
      expect(r.integration, same(old));
      expect(source.removals.single.toolNames, {'http__a'});
      expect(source.deletedSecrets, isEmpty, reason: 'Integration bleibt');
      await s.dispose();
    },
  );

  test('http/http_sensitive: Tool wechselt die Integration, nichts wird '
      'aufgeräumt; http fällt weg, sensible behalten ihre Tools', () async {
    final source = FakeUserIntegrationSource(
      kind: UserIntegrationKind.http,
      integrations: [
        userIntegration('http', tools: ['http__a', 'http__b']),
        userIntegration('http_sensitive', tools: ['http__s']),
      ],
    );
    final cleaned = <IntegrationRemoval>[];
    final s = sync([source], cleanups: [(r) async => cleaned.add(r)]);
    await s.ready;
    registry
      ..setEnabled('http', enabled: true)
      ..setEnabled('http_sensitive', enabled: true);

    // http__b wird sensibel: zieht nach http_sensitive um.
    source.update([
      userIntegration('http', tools: ['http__a']),
      userIntegration('http_sensitive', tools: ['http__s', 'http__b']),
    ]);
    await s.settled();
    expect(s.rejected, isEmpty, reason: 'kein Namenskonflikt beim Umzug');
    expect(activeTools(registry), ['http__a', 'http__b', 'http__s']);
    expect(cleaned, isEmpty);

    // Das letzte nicht sensible Tool wird gelöscht: http fällt weg.
    source.update([
      userIntegration('http_sensitive', tools: ['http__s', 'http__b']),
    ]);
    await s.settled();
    expect(activeTools(registry), ['http__b', 'http__s']);
    final r = cleaned.single;
    expect((r.id, r.whole), ('http', true));
    expect(r.toolNames, {'http__a'});
    await s.dispose();
  });

  group('verdrahtet (Provider)', () {
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

final class _ThrowingSource implements UserIntegrationSource {
  @override
  UserIntegrationKind get kind => UserIntegrationKind.http;

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  Future<List<Integration>> load() async => throw StateError('kaputt');

  @override
  Future<void> deleteSecrets(IntegrationRemoval removal) async {}
}
