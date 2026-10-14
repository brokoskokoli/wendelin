import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

/// Names of the tools of the enabled integrations, sorted.
List<String> activeTools(FakeUserIntegrationRegistry r) => [
  for (final MapEntry(key: id, value: i) in r.integrations.entries)
    if (r.isEnabled(id)) ...[for (final t in i.tools) t.name],
]..sort();

void main() {
  late FakeUserIntegrationRegistry registry;
  late FakeUserIntegrationSwitches switches;
  final errors = <Object>[];

  setUp(() {
    registry = FakeUserIntegrationRegistry();
    switches = FakeUserIntegrationSwitches();
    errors.clear();
  });

  UserIntegrationSync sync(
    List<UserIntegrationSource> sources, {
    List<IntegrationCleanup> cleanups = const [],
    void Function(Integration)? onRegistered,
  }) => UserIntegrationSync(
    registry: registry,
    sources: sources,
    switches: switches,
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
    expect(registry.isEnabled('mcp_home'), isFalse);
    registry.enabled['mcp_home'] = true;
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
    registry.enabled['mcp_home'] = true;

    source.update([
      userIntegration('mcp_home', tools: ['git', 'shell']),
    ]);
    await s.settled();
    expect(activeTools(registry), ['mcp_home__git', 'mcp_home__shell']);
    expect(registry.isEnabled('mcp_home'), isTrue);
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
    switches.values['http_ha'] = true;

    http.update([userIntegration('http_n8n')]);
    await s.settled();
    expect(registry.integrations.keys, ['http_n8n']);
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
    expect(switches.values, isNot(contains('http_ha')));

    http.update([]);
    await s.settled();
    expect(registry.integrations, isEmpty);
    expect(http.deletedSecrets, ['http_ha', 'http_n8n']);
    await s.dispose();
  });

  test('Neustart stellt den gespeicherten Schalter wieder her', () async {
    switches.values['mcp_on'] = true;
    final source = FakeUserIntegrationSource(
      integrations: [userIntegration('mcp_on'), userIntegration('mcp_off')],
    );
    final s = sync([source]);
    await s.ready;
    expect(registry.isEnabled('mcp_on'), isTrue);
    expect(registry.isEnabled('mcp_off'), isFalse);
    expect(source.deletedSecrets, isEmpty, reason: 'Start löscht nichts');
    await s.dispose();
  });

  test('Namenskollision wird abgewiesen statt zu überschreiben', () async {
    await registry.register(
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
    expect(registry.integrations.keys, ['calendar']);
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
    registry.enabled['mcp_c'] = true;
    source.update([
      userIntegration('mcp_c', tools: ['ok', 'calendar__x']),
    ]);
    await s.settled();
    expect(activeTools(registry), ['calendar__x', 'mcp_c__ok']);
    expect(registry.isEnabled('mcp_c'), isTrue);
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
    expect(registry.integrations.keys, ['mcp_ok']);
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
      expect(registry.integrations.values.single.tools.map((t) => t.name), [
        'http__b',
      ]);
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
    registry.enabled
      ..['http'] = true
      ..['http_sensitive'] = true;

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
