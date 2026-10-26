import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

const _canary = 'kanarienvogel-mcp-4711';

final class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 's${++_n}';
}

List<FakeMcpTool> _tools() => [
  FakeMcpTool(
    'get_state',
    description: 'Zustand lesen',
    annotations: const {'readOnlyHint': true},
  ),
  FakeMcpTool('delete_scene', description: 'Szene löschen'),
];

void main() {
  late FakeMcpServer server;
  late FakeMcpConfigStore configs;
  late InMemoryMcpCacheStore cache;
  late FakeMcpSecrets secrets;
  late FakeMcpAudit audit;
  late http.Client client;
  late McpServerSource source;
  final errors = <String>[];
  final logs = <String>[];

  McpServerSource newSource() => McpServerSource(
    configs: configs,
    cache: cache,
    secrets: secrets,
    httpClient: client,
    browser: FakeAuthorizationBrowser(),
    ids: _Ids(),
    audit: audit.call,
    reportError: (id, message) => errors.add('$id: $message'),
    log: logs.add,
  );

  McpDraft draft({
    String name = 'Home Lab',
    McpAuthKind auth = McpAuthKind.none,
    String? token,
  }) => McpDraft(name: name, url: server.url, auth: auth, token: token);

  setUp(() async {
    server = await FakeMcpServer.start(tools: _tools());
    configs = FakeMcpConfigStore();
    cache = InMemoryMcpCacheStore();
    secrets = FakeMcpSecrets();
    audit = FakeMcpAudit();
    client = http.Client();
    errors.clear();
    logs.clear();
    source = newSource();
  });

  tearDown(() async {
    await source.dispose();
    client.close();
    await server.close();
  });

  test('Anlegen: Konfiguration ohne Secret, Token im Secret-Speicher, '
      'Tools aus dem Server', () async {
    server.auth = FakeAuthMode.bearer;
    final view = await source.add(
      draft(auth: McpAuthKind.bearer, token: server.bearerToken),
    );
    final id = view.config.id;
    expect(view.integrationId, 'mcp_homelab');
    expect(view.check!.status, McpReachability.reachable);
    expect(source.kind, UserIntegrationKind.mcp);
    expect(
      jsonEncode(configs.stored.map((c) => c.toJson()).toList()),
      isNot(contains(server.bearerToken)),
    );
    expect(secrets.values[McpSecretRefs.bearer(id)], server.bearerToken);
    expect(cache.entries[id], isNotNull);
    expect(configs.checks[id]!.ok, isTrue);
    final integration = (await source.load()).single;
    expect(
      integration.tools.map((t) => t.name),
      contains('mcp_homelab__get_state'),
    );
    expect(await integration.checkAvailability(), Availability.yes);
    expect(identical(integration, view.integration), isTrue);
  });

  test('Neustart baut die Tools aus dem Cache, ohne Netz', () async {
    await source.add(draft());
    await source.dispose();
    server.requests.clear();
    source = newSource();
    final integration = (await source.load()).single;
    expect(integration.tools, isNotEmpty);
    expect(await integration.checkAvailability(), Availability.yes);
    expect(server.requests, isEmpty, reason: 'Laden und Prüfen ohne Netz');
    expect(source.servers.single.check, isNotNull);
  });

  test('Löschen entfernt Konfiguration, Cache, Prüfung und Secrets', () async {
    server.auth = FakeAuthMode.bearer;
    final view = await source.add(
      draft(auth: McpAuthKind.bearer, token: server.bearerToken),
    );
    final id = view.config.id;
    await source.remove(id);
    expect(configs.stored, isEmpty);
    expect(cache.entries, isEmpty);
    expect(configs.checks, isEmpty);
    expect(secrets.values, isEmpty);
    expect(source.servers, isEmpty);
    expect(await source.load(), isEmpty);
  });

  test('Nachsorge löscht Secrets nur eines nicht mehr vorhandenen '
      'Servers', () async {
    server.auth = FakeAuthMode.bearer;
    final view = await source.add(
      draft(auth: McpAuthKind.bearer, token: server.bearerToken),
    );
    final removal = IntegrationRemoval(
      integration: view.integration,
      toolNames: const {},
      whole: true,
    );
    await source.deleteSecrets(removal);
    expect(secrets.values[McpSecretRefs.bearer(view.config.id)], isNotNull);
    // Teilweise Entfernung und fremde Integrationen: nichts zu tun.
    await source.deleteSecrets(
      IntegrationRemoval(
        integration: view.integration,
        toolNames: const {'x'},
        whole: false,
      ),
    );
    await source.deleteSecrets(
      IntegrationRemoval(
        integration: FakeIntegration(id: 'x', tools: const []),
        toolNames: const {},
        whole: true,
      ),
    );
    expect(secrets.values, isNotEmpty);

    await source.dispose();
    configs.stored = [];
    source = newSource();
    await source.deleteSecrets(removal);
    expect(secrets.values, isEmpty);
    expect(cache.entries, isEmpty);
    expect(configs.checks, isEmpty);
  });

  test('Aufräumen übersteht Fehler einzelner Schritte', () async {
    server.auth = FakeAuthMode.bearer;
    final view = await source.add(
      draft(auth: McpAuthKind.bearer, token: server.bearerToken),
    );
    secrets.failReads = true;
    final failing = _FailingDelete(secrets);
    await source.dispose();
    source = McpServerSource(
      configs: configs,
      cache: cache,
      secrets: failing,
      httpClient: client,
      browser: FakeAuthorizationBrowser(),
      ids: _Ids(),
      log: logs.add,
    );
    await source.remove(view.config.id);
    expect(configs.stored, isEmpty, reason: 'Rest wird trotzdem gelöscht');
    expect(cache.entries, isEmpty);
    expect(logs.join('\n'), contains('Aufräumen unvollständig'));
    expect(logs.join('\n'), isNot(contains(server.bearerToken)));
  });

  test('Anlegen und Ändern lehnen Klartext ins Internet ab', () async {
    await expectLater(
      source.add(McpDraft(name: 'x', url: Uri.parse('http://example.org/mcp'))),
      throwsA(isA<McpException>()),
    );
    final view = await source.add(draft());
    await expectLater(
      source.update(
        McpServerConfig.fromJson({
          ...view.config.toJson(),
          'url': 'http://example.org/mcp',
        }),
      ),
      throwsA(isA<McpException>()),
    );
    await expectLater(
      source.update(
        McpServerConfig.fromJson({...view.config.toJson(), 'id': 'unbekannt'}),
      ),
      throwsArgumentError,
    );
  });

  test(
    'Ändern: gleiche Konfiguration tut nichts, neue wird übernommen',
    () async {
      final view = await source.add(draft());
      final before = source.servers.single.integration;
      await source.update(view.config);
      expect(identical(source.servers.single.integration, before), isTrue);
      await source.update(
        McpServerConfig.fromJson({...view.config.toJson(), 'name': 'Neu'}),
      );
      expect(configs.stored.single.name, 'Neu');
      expect(identical(source.servers.single.integration, before), isFalse);
    },
  );

  test('gleicher Name: eindeutiger Slug', () async {
    await source.add(draft());
    final second = await source.add(draft());
    expect(second.integrationId, isNot('mcp_homelab'));
    expect(second.integrationId, startsWith('mcp_homelab'));
    expect(source.byIntegrationId('mcp_homelab'), isNotNull);
    expect(source.byIntegrationId('mcp_nie'), isNull);
    expect(source.server('gibtsnicht'), isNull);
  });

  test(
    'probeDraft: erreichbar, Anmeldung nötig, Klartext ins Internet',
    () async {
      expect(
        (await source.probeDraft(draft())).status,
        McpReachability.reachable,
      );
      server.auth = FakeAuthMode.bearer;
      final auth = await source.probeDraft(
        draft(auth: McpAuthKind.bearer, token: 'falsch'),
      );
      expect(auth.status, McpReachability.authRequired);
      final good = await source.probeDraft(
        draft(auth: McpAuthKind.bearer, token: server.bearerToken),
      );
      expect(good.status, McpReachability.reachable);
      final public = await source.probeDraft(
        McpDraft(name: 'x', url: Uri.parse('http://example.org/mcp')),
      );
      expect(public.status, McpReachability.unreachable);
      expect(public.detail, contains('http nur im Heimnetz'));
      expect(secrets.values, isEmpty, reason: 'Probe schreibt keine Secrets');
    },
  );

  test('setSecret nur für Referenzen des Servers; Neuprüfung heilt', () async {
    server.auth = FakeAuthMode.bearer;
    final view = await source.add(
      draft(auth: McpAuthKind.bearer, token: 'falsch'),
    );
    expect(view.check!.status, McpReachability.authRequired);
    expect(errors.single, startsWith('mcp_homelab: Anmeldung nötig'));
    await expectLater(
      source.setSecret(view.config.id, 'bring.password', 'x'),
      throwsArgumentError,
    );
    expect(secrets.values.keys, isNot(contains('bring.password')));
    await source.setSecret(
      view.config.id,
      McpSecretRefs.bearer(view.config.id),
      server.bearerToken,
    );
    expect(source.servers.single.check!.ok, isTrue);
    expect(await source.servers.single.hasCredentials(), isTrue);
    await expectLater(source.signIn(view.config.id), throwsStateError);
  });

  test('Neu laden schreibt die Prüfung fort, Fehler des Speichers werden '
      'nur geloggt', () async {
    final view = await source.add(draft());
    server.requests.clear();
    final check = await source.reload(view.config.id);
    expect(check.ok, isTrue);
    expect(server.requests, isNotEmpty);
    expect(configs.checks[view.config.id], check);
    await expectLater(source.reload('unbekannt'), throwsArgumentError);
  });

  test(
    'Import setzt den Haken „kann Fremdes enthalten“ zurück auf an',
    () async {
      await source.add(draft());
      final data =
          jsonDecode(source.exportJson(enabled: (_) => true))!
              as Map<String, Object?>;
      for (final e in data['servers']! as List) {
        (e as Map<String, Object?>)['mayContainUntrustedContent'] = false;
      }
      final added = await source.importJson(jsonEncode(data));
      expect(added.single.config.mayContainUntrustedContent, isTrue);
    },
  );

  test('Export ohne Secrets, Import mit neuen Ids, Referenzen und '
      'ausgeschaltet', () async {
    server.auth = FakeAuthMode.bearer;
    await source.add(draft(auth: McpAuthKind.bearer, token: _canary));
    final text = source.exportJson(enabled: (_) => true);
    expect(text, isNot(contains(_canary)));
    expect(text, contains(McpServerSource.secretPlaceholder));
    expect(text, isNot(contains('"id"')));

    final added = await source.importJson(text);
    final copy = added.single;
    expect(copy.config.id, isNot('s1'));
    expect(copy.config.slug, isNot('homelab'));
    expect(
      copy.config.auth,
      McpBearerAuth(McpSecretRefs.bearer(copy.config.id)),
    );
    expect(secrets.values.keys, {
      McpSecretRefs.bearer('s1'),
    }, reason: 'Import legt keine Secrets an');
    expect(configs.stored, hasLength(2));

    final before = configs.stored.length;
    await expectLater(source.importJson('kein json'), throwsFormatException);
    await expectLater(source.importJson('[]'), throwsFormatException);
    await expectLater(
      source.importJson(jsonEncode({'format': 'x', 'servers': <Object?>[]})),
      throwsFormatException,
    );
    await expectLater(
      source.importJson(
        jsonEncode({
          'format': McpServerSource.exportFormat,
          'servers': [1],
        }),
      ),
      throwsFormatException,
    );
    await expectLater(
      source.importJson(
        jsonEncode({
          'format': McpServerSource.exportFormat,
          'servers': [
            {
              'name': 'x',
              'slug': 'x',
              'url': 'http://example.org/mcp',
              'transport': 'streamable',
              'auth': {'kind': 'none'},
            },
          ],
        }),
      ),
      throwsA(isA<McpException>()),
    );
    expect(configs.stored, hasLength(before), reason: 'nichts halb importiert');
  });

  test('Audit: Prüfung und Fehler, Adressen ohne Query, Sink-Fehler nur '
      'geloggt', () async {
    server.auth = FakeAuthMode.bearer;
    final view = await source.add(draft(auth: McpAuthKind.bearer, token: 'x'));
    await Future<void>.delayed(Duration.zero);
    final kinds = audit.entries.map((e) => e.kind).toSet();
    expect(kinds, contains(McpAuditKind.error));
    final text = jsonEncode(audit.entries.map((e) => e.payload).toList());
    expect(text, isNot(contains(server.bearerToken)));

    audit.fail = true;
    await source.reload(view.config.id);
    await Future<void>.delayed(Duration.zero);
    expect(logs.join('\n'), contains('Audit-Eintrag nicht geschrieben'));
  });

  test('sanitizeMcpDetail entfernt code und state aus Adressen', () {
    expect(
      sanitizeMcpDetail('Weiter: https://x.org/cb?code=GEHEIM&state=abc ok'),
      'Weiter: https://x.org/cb?… ok',
    );
    expect(sanitizeMcpDetail('ohne Adresse'), 'ohne Adresse');
  });

  test('Ladefehler des Speichers wird erneut versucht', () async {
    final broken = _BrokenConfigs(configs);
    await source.dispose();
    source = McpServerSource(
      configs: broken,
      cache: cache,
      secrets: secrets,
      httpClient: client,
      browser: FakeAuthorizationBrowser(),
      ids: _Ids(),
    );
    await expectLater(source.load(), throwsStateError);
    broken.fail = false;
    expect(await source.load(), isEmpty);
  });
}

final class _FailingDelete implements McpSecrets {
  _FailingDelete(this.inner);
  final McpSecrets inner;

  @override
  Future<String?> read(String ref) => inner.read(ref);

  @override
  Future<void> write(String ref, String value) => inner.write(ref, value);

  @override
  Future<void> delete(String ref) async =>
      throw StateError('Keystore gesperrt');
}

final class _BrokenConfigs implements McpConfigStore {
  _BrokenConfigs(this.inner);
  final McpConfigStore inner;
  bool fail = true;

  @override
  Future<List<McpServerConfig>> servers() async =>
      fail ? throw StateError('kaputt') : inner.servers();

  @override
  Future<void> saveServers(List<McpServerConfig> servers) =>
      inner.saveServers(servers);

  @override
  Future<McpCheck?> check(String serverId) => inner.check(serverId);

  @override
  Future<void> saveCheck(String serverId, McpCheck check) =>
      inner.saveCheck(serverId, check);

  @override
  Future<void> deleteCheck(String serverId) => inner.deleteCheck(serverId);
}
