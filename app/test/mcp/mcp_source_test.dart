import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/app_settings.dart';
import 'package:wendelin/di/mcp/mcp_persistence.dart';
import 'package:wendelin/di/mcp/mcp_providers.dart';
import 'package:wendelin/di/mcp/mcp_secrets.dart';
import 'package:wendelin/di/mcp/mcp_source.dart';
import 'package:wendelin/di/mcp/mcp_templates.dart';
import 'package:wendelin/di/providers.dart';
import 'package:wendelin/di/user_integrations.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/mcp_support.dart';
import '../support/test_env.dart';

void main() {
  late FakeMcpServer server;
  late TestEnv env;
  late ProviderContainer c;

  setUp(() async {
    allowRealHttp();
    server = await FakeMcpServer.start(tools: homeTools());
    env = TestEnv(enabled: const {}, extraOverrides: mcpOverrides());
    c = env.container();
  });

  tearDown(() async {
    c.dispose();
    await server.close();
  });

  McpServerSource source() => c.read(mcpServerSourceProvider);

  List<String> catalog([PrivacyLevel level = PrivacyLevel.standard]) => c
      .read(toolRegistryProvider)
      .activeSpecsFor(level, sessionId: 's')
      .map((s) => s.name)
      .toList();

  Tool tool(String name) => c
      .read(toolRegistryProvider)
      .integrations
      .expand((i) => i.integration.tools)
      .firstWhere((t) => t.name == name);

  group('Server anlegen und Zustände', () {
    test('Vorlage → Server: Tools aus dem Server landen in der Registry, '
        'Name mcp_<slug>__<tool>', () async {
      final view = await addAndEnable(c, draftFor(server, name: 'Home Lab'));
      expect(view.integrationId, 'mcp_homelab');
      expect(view.check!.status, McpReachability.reachable);
      expect(view.check!.serverName, 'fake-mcp 1.0.0');
      expect(catalog(), [
        'mcp_homelab__delete_scene',
        'mcp_homelab__get_state',
        'mcp_homelab__set_light',
      ]);
      final sync = c.read(userIntegrationSyncProvider);
      expect(sync.kindOf('mcp_homelab'), UserIntegrationKind.mcp);
      expect(
        c.read(toolRegistryProvider).status('mcp_homelab'),
        IntegrationStatus.active,
      );
      // Konfiguration ohne Secrets in den Einstellungen.
      final stored = await env.storage.settings.get(McpSettings.servers);
      expect(stored!.single.name, 'Home Lab');
      expect(
        await env.storage.settings.get(McpSettings.cache(view.config.id)),
        isNotNull,
      );
    });

    test('initialize beim Aktivieren (Schalter), nicht beim Anlegen', () async {
      await c.read(toolRegistryReadyProvider.future);
      final view = await source().add(
        draftFor(server, auth: McpAuthKind.bearer, token: 'x'),
      );
      server.requests.clear();
      await c.read(userIntegrationSyncProvider).settled();
      expect(server.requests, isEmpty);
      await c
          .read(integrationActivatorProvider)
          .setEnabled(view.integrationId, enabled: true);
      await waitUntil(
        () => server.requests.any((r) => r.rpcMethod == 'initialize'),
      );
    });

    test('probe zeigt erreichbar, Auth nötig, nicht erreichbar, '
        'Protokollfehler', () async {
      final ok = await source().probeDraft(draftFor(server));
      expect(ok.status, McpReachability.reachable);

      server.auth = FakeAuthMode.bearer;
      final auth = await source().probeDraft(
        draftFor(server, auth: McpAuthKind.bearer, token: 'falsch'),
      );
      expect(auth.status, McpReachability.authRequired);
      final good = await source().probeDraft(
        draftFor(server, auth: McpAuthKind.bearer, token: server.bearerToken),
      );
      expect(good.status, McpReachability.reachable);

      final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close();
      final unreachable = await source().probeDraft(
        McpDraft(name: 'weg', url: Uri.parse('http://127.0.0.1:$port/mcp')),
      );
      expect(unreachable.status, McpReachability.unreachable);

      final web = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      web.listen((r) async {
        r.response.headers.contentType = ContentType.html;
        r.response.write('<html>Hallo</html>');
        await r.response.close();
      });
      addTearDown(() => web.close(force: true));
      final protocol = await source().probeDraft(
        McpDraft(name: 'web', url: Uri.parse('http://127.0.0.1:${web.port}/')),
      );
      expect(protocol.status, McpReachability.protocolError);

      final public = await source().probeDraft(
        McpDraft(name: 'x', url: Uri.parse('http://example.org/mcp')),
      );
      expect(public.status, McpReachability.unreachable);
      expect(public.detail, contains('http nur im Heimnetz'));
    });

    test('add lehnt Klartext ins Internet ab', () async {
      await c.read(toolRegistryReadyProvider.future);
      expect(
        () => source().add(
          McpDraft(name: 'x', url: Uri.parse('http://example.org/mcp')),
        ),
        throwsA(isA<McpException>()),
      );
    });

    test('gleicher Name: eindeutiger Slug', () async {
      await addAndEnable(c, draftFor(server));
      final second = await addAndEnable(c, draftFor(server));
      expect(second.integrationId, isNot('mcp_homeserver'));
      expect(second.integrationId, startsWith('mcp_homeserver'));
      expect(catalog().where((n) => n.endsWith('__get_state')), hasLength(2));
    });
  });

  group('Tool-Schalter und Risiko', () {
    test('Tool abschalten entfernt es aus dem Katalog, Einschalten bringt '
        'es zurück', () async {
      final view = await addAndEnable(c, draftFor(server));
      await source().update(
        view.config.copyWith(
          toolOverrides: {
            'delete_scene': const McpToolOverride(enabled: false),
          },
        ),
      );
      await c.read(userIntegrationSyncProvider).settled();
      expect(catalog(), isNot(contains('mcp_homeserver__delete_scene')));
      expect(
        source().server(view.config.id)!.skipped.single.reason,
        'abgeschaltet',
      );
      await source().update(view.config.copyWith(toolOverrides: {}));
      await c.read(userIntegrationSyncProvider).settled();
      expect(catalog(), contains('mcp_homeserver__delete_scene'));
    });

    test('effektive Stufen: read, write ohne Undo → bestätigen, '
        'external; Override nur verschärfend, autoRun nur bei write', () async {
      final view = await addAndEnable(c, draftFor(server));
      expect(tool('mcp_homeserver__get_state').risk, RiskLevel.read);
      expect(tool('mcp_homeserver__set_light').risk, RiskLevel.external);
      expect(tool('mcp_homeserver__delete_scene').risk, RiskLevel.external);

      await source().update(
        view.config.copyWith(
          toolOverrides: {
            'get_state': const McpToolOverride(risk: RiskLevel.external),
            'set_light': const McpToolOverride(autoRun: true),
            // Versuch zu lockern: wirkt nicht.
            'delete_scene': const McpToolOverride(
              risk: RiskLevel.read,
              autoRun: true,
            ),
          },
        ),
      );
      await c.read(userIntegrationSyncProvider).settled();
      expect(tool('mcp_homeserver__get_state').risk, RiskLevel.external);
      expect(tool('mcp_homeserver__set_light').risk, RiskLevel.write);
      expect(tool('mcp_homeserver__delete_scene').risk, RiskLevel.external);

      // „Alle Tools bestätigen“ schlägt autoRun.
      final next = source().server(view.config.id)!.config;
      await source().update(next.copyWith(confirmAll: true));
      await c.read(userIntegrationSyncProvider).settled();
      expect(tool('mcp_homeserver__set_light').risk, RiskLevel.external);
      expect(tool('mcp_homeserver__get_state').risk, RiskLevel.external);
    });

    test('sensibler Server: nur für Ziele ab der Stufe (K10)', () async {
      await addAndEnable(c, draftFor(server, sensitive: true));
      c.read(toolRegistryProvider).sensitiveMinimum = PrivacyLevel.tee;
      expect(catalog().where((n) => n.startsWith('mcp_')), isEmpty);
      expect(catalog(PrivacyLevel.tee), contains('mcp_homeserver__get_state'));
    });
  });

  group('Lebenszyklus', () {
    test('Neustart: Tools aus dem Cache sofort da, ohne Netz; Rückkehr in '
        'die App fragt den Server nicht', () async {
      final view = await addAndEnable(c, draftFor(server));
      c.dispose();
      await server.close();
      server = await FakeMcpServer.start(tools: homeTools());

      final again = TestEnv(
        enabled: {view.integrationId},
        extraOverrides: mcpOverrides(),
        storage: env.storage,
      );
      c = again.container();
      await c.read(toolRegistryReadyProvider.future);
      expect(catalog(), contains('mcp_homeserver__get_state'));
      await c.read(toolRegistryProvider).refresh();
      expect(server.requests, isEmpty);
      expect(
        c.read(toolRegistryProvider).status(view.integrationId),
        IntegrationStatus.active,
      );
    });

    test('list_changed während eines Aufrufs lädt neu und aktualisiert die '
        'Registry', () async {
      server.style = FakeResponseStyle.sse;
      await addAndEnable(c, draftFor(server));
      server
        ..sendListChanged = true
        ..tools = [...homeTools(), FakeMcpTool('new_tool')];
      final outcome = await tool('mcp_homeserver__set_light')
          .execute(const {}, _ctx());
      expect(outcome.isError, isFalse);
      await waitUntil(() => catalog().contains('mcp_homeserver__new_tool'));
    });

    test('abgelehntes Token: Fehler mit Grund, Neu laden nach Ersetzen '
        'heilt', () async {
      server.auth = FakeAuthMode.bearer;
      final view = await addAndEnable(
        c,
        draftFor(server, auth: McpAuthKind.bearer, token: server.bearerToken),
      );
      expect(catalog(), contains('mcp_homeserver__get_state'));
      server.bearerToken = 'neues-token';
      final outcome = await tool('mcp_homeserver__get_state')
          .execute(const {'entity': 'licht'}, _ctx());
      expect(outcome.isError, isTrue);
      final info = c.read(toolRegistryProvider).info(view.integrationId);
      expect(info.status, IntegrationStatus.error);
      expect(info.error, startsWith('Anmeldung nötig'));

      await source().setSecret(
        view.config.id,
        McpSecretRefs.bearer(view.config.id),
        'neues-token',
      );
      await c.read(userIntegrationSyncProvider).settled();
      expect(
        c.read(toolRegistryProvider).status(view.integrationId),
        IntegrationStatus.active,
      );
    });
  });

  group('Löschen', () {
    test('räumt Registry, Konfiguration, Cache und Secrets auf', () async {
      server.auth = FakeAuthMode.bearer;
      final view = await addAndEnable(
        c,
        draftFor(server, auth: McpAuthKind.bearer, token: server.bearerToken),
      );
      final id = view.config.id;
      expect(await env.secrets.read(McpSecretRefs.bearer(id)), isNotNull);

      await source().remove(id);
      await c.read(userIntegrationSyncProvider).settled();
      expect(catalog().where((n) => n.startsWith('mcp_')), isEmpty);
      expect(
        c.read(toolRegistryProvider).integrations.map((i) => i.id),
        isNot(contains(view.integrationId)),
      );
      expect(await env.secrets.listKeys(), isEmpty);
      expect(await env.storage.settings.get(McpSettings.servers), isEmpty);
      expect(await env.storage.settings.get(McpSettings.cache(id)), isNull);
      expect(await env.storage.settings.get(McpSettings.check(id)), isNull);
      expect(
        await env.storage.settings.get(
          AppSettings.integrationEnabled(view.integrationId),
        ),
        isFalse,
      );
    });

    test(
      'Nachsorge löscht keine Secrets eines noch vorhandenen Servers',
      () async {
        server.auth = FakeAuthMode.bearer;
        final view = await addAndEnable(
          c,
          draftFor(server, auth: McpAuthKind.bearer, token: server.bearerToken),
        );
        await source().deleteSecrets(
          IntegrationRemoval(
            integration: view.integration,
            toolNames: const {},
            whole: true,
          ),
        );
        expect(
          await env.secrets.read(McpSecretRefs.bearer(view.config.id)),
          server.bearerToken,
        );
      },
    );
  });

  group('OAuth', () {
    test('Anmeldung Ende-zu-Ende: Token im SecretStore, nicht in den '
        'Einstellungen', () async {
      server.auth = FakeAuthMode.oauth;
      await c.read(toolRegistryReadyProvider.future);
      final view = await source().add(
        draftFor(server, auth: McpAuthKind.oauth),
      );
      final sync = c.read(userIntegrationSyncProvider);
      await sync.settled();
      expect((await view.integration.setupState()).missingSteps, ['auth']);

      final check = await source().signIn(view.config.id);
      expect(check.status, McpReachability.reachable);
      await sync.settled();
      final token = await env.secrets.read(
        McpSecretRefs.oauthToken(view.config.id),
      );
      expect(token, isNotNull);
      final access =
          (jsonDecode(token!) as Map<String, Object?>)['accessToken']!
              as String;
      expect(server.accessTokens, contains(access));
      expect(
        await env.secrets.read(McpSecretRefs.oauthClient(view.config.id)),
        isNotNull,
      );
      final settingsJson = jsonEncode(
        (await env.storage.settings.get(McpSettings.servers))!
            .map((s) => s.toJson())
            .toList(),
      );
      expect(settingsJson, isNot(contains(access)));
      await c
          .read(integrationActivatorProvider)
          .setEnabled(view.integrationId, enabled: true);
      expect(catalog(), contains('mcp_homeserver__get_state'));
    });

    test('kein Browser: klarer Hinweis statt Absturz', () async {
      server.auth = FakeAuthMode.oauth;
      c.dispose();
      c = TestEnv(
        enabled: const {},
        storage: env.storage,
        extraOverrides: [
          ...mcpOverrides(),
          mcpBrowserAvailableProvider.overrideWithValue(() async => false),
        ],
      ).container();
      await c.read(toolRegistryReadyProvider.future);
      final view = await source().add(
        draftFor(server, auth: McpAuthKind.oauth),
      );
      await expectLater(
        source().signIn(view.config.id),
        throwsA(
          isA<McpSignInException>().having(
            (e) => e.message,
            'message',
            contains('Kein Browser'),
          ),
        ),
      );
    });

    test('falscher state wird verworfen', () async {
      server.auth = FakeAuthMode.oauth;
      c.dispose();
      c = TestEnv(
        enabled: const {},
        storage: env.storage,
        extraOverrides: mcpOverrides(
          browser: FakeAuthorizationBrowser(
            tamper: (u) => u.replace(
              queryParameters: {...u.queryParameters, 'state': 'fremd'},
            ),
          ),
        ),
      ).container();
      await c.read(toolRegistryReadyProvider.future);
      final view = await source().add(
        draftFor(server, auth: McpAuthKind.oauth),
      );
      await expectLater(
        source().signIn(view.config.id),
        throwsA(isA<McpException>()),
      );
      expect(
        await env.secrets.read(McpSecretRefs.oauthToken(view.config.id)),
        isNull,
      );
    });
  });

  group('Export und Import', () {
    test('Export ohne Secrets, Import fragt sie neu ab', () async {
      server.auth = FakeAuthMode.bearer;
      final view = await addAndEnable(
        c,
        draftFor(server, auth: McpAuthKind.bearer, token: server.bearerToken),
      );
      await source().update(
        view.config.copyWith(
          confirmAll: true,
          toolOverrides: {'get_state': const McpToolOverride(enabled: false)},
        ),
      );
      final json = source().exportJson(
        enabled: (id) => c.read(toolRegistryProvider).info(id).enabled,
      );
      expect(json, isNot(contains(server.bearerToken)));
      expect(json, isNot(contains(view.config.id)));
      expect(json, contains(McpServerSource.secretPlaceholder));

      // Anderes Gerät.
      final other = TestEnv(enabled: const {}, extraOverrides: mcpOverrides());
      final c2 = other.container();
      addTearDown(c2.dispose);
      await c2.read(toolRegistryReadyProvider.future);
      final imported = await c2.read(mcpServerSourceProvider).importJson(json);
      final config = imported.single.config;
      expect(config.name, 'Homeserver');
      expect(config.slug, 'homeserver');
      expect(config.confirmAll, isTrue);
      expect(config.toolOverrides['get_state']!.enabled, isFalse);
      expect(config.auth, McpBearerAuth(McpSecretRefs.bearer(config.id)));
      expect(await imported.single.hasCredentials(), isFalse);
      await c2.read(userIntegrationSyncProvider).settled();
      expect(
        c2.read(toolRegistryProvider).info(config.integrationId).enabled,
        isFalse,
      );
      expect(
        () => c2.read(mcpServerSourceProvider).importJson('{"x":1}'),
        throwsFormatException,
      );
    });
  });

  test('Audit: Verbinden und Auth-Fehler ohne Tokens', () async {
    server.auth = FakeAuthMode.bearer;
    final view = await addAndEnable(
      c,
      draftFor(server, auth: McpAuthKind.bearer, token: server.bearerToken),
    );
    server.bearerToken = 'anders';
    await source().reload(view.config.id);
    final entries = await env.storage.audit.query();
    final mcp = entries.where((e) => e.payload['source'] == 'mcp').toList();
    expect(mcp.where((e) => e.kind == AuditKind.verification), isNotEmpty);
    expect(
      mcp
          .where((e) => e.kind == AuditKind.error)
          .map((e) => e.payload['message']),
      contains(contains('Homeserver')),
    );
  });

  group('Review-Nachbesserungen', () {
    test('„Alle Tools bestätigen“ beim Anlegen: jedes Tool external', () async {
      await addAndEnable(c, draftFor(server, confirmAll: true));
      final mcp = c
          .read(toolRegistryProvider)
          .integrations
          .expand((i) => i.integration.tools)
          .where((t) => t.name.startsWith('mcp_'));
      expect(mcp, hasLength(3));
      expect(mcp.map((t) => t.risk).toSet(), {RiskLevel.external});
    });

    test('Tool-Aufruf schreibt die letzte Prüfung fort (ohne Extra-Anfrage)', () async {
      final view = await addAndEnable(c, draftFor(server));
      final id = view.config.id;
      final port = server.url.port;
      await server.close();
      await tool('mcp_homeserver__get_state')
          .execute(const {'entity': 'x'}, _ctx());
      await waitUntil(
        () => source().server(id)!.check!.status == McpReachability.unreachable,
      );
      expect(
        (await env.storage.settings.get(McpSettings.check(id)))!.status,
        McpReachability.unreachable,
      );
      // Server wieder da (gleicher Port): der nächste Aufruf heilt die Anzeige.
      server = await FakeMcpServer.start(tools: homeTools(), port: port);
      final before = server.requests.length;
      await tool('mcp_homeserver__get_state')
          .execute(const {'entity': 'x'}, _ctx());
      await waitUntil(
        () => source().server(id)!.check!.status == McpReachability.reachable,
      );
      // Nur der Aufruf selbst (initialize, initialized, tools/call), kein probe.
      expect(
        server.requests.skip(before).where((r) => r.rpcMethod == 'tools/list'),
        isEmpty,
      );
    });

    test(
      'Import prüft erst alles: ein ungültiger Eintrag legt nichts an',
      () async {
        await c.read(toolRegistryReadyProvider.future);
        final json = jsonEncode({
          'format': McpServerSource.exportFormat,
          'version': 1,
          'servers': [
            {
              'name': 'Gut',
              'slug': 'gut',
              'url': 'http://homeserver.local/mcp',
              'auth': {'kind': 'none'},
            },
            {
              'name': 'Internet',
              'slug': 'internet',
              'url': 'http://example.org/mcp',
              'auth': {'kind': 'none'},
            },
          ],
        });
        await expectLater(
          source().importJson(json),
          throwsA(isA<McpException>()),
        );
        expect(source().servers, isEmpty);
        expect(await env.storage.settings.get(McpSettings.servers), isEmpty);
      },
    );

    test('Ändern auf Klartext ins Internet wird abgelehnt', () async {
      final view = await addAndEnable(c, draftFor(server));
      await expectLater(
        source().update(
          view.config.copyWith(url: Uri.parse('http://example.org/mcp')),
        ),
        throwsA(isA<McpException>()),
      );
      expect(source().server(view.config.id)!.config.url, server.url);
    });

    test('setSecret nur für Referenzen des Servers', () async {
      server.auth = FakeAuthMode.bearer;
      final view = await addAndEnable(
        c,
        draftFor(server, auth: McpAuthKind.bearer, token: server.bearerToken),
      );
      expect(
        () => source().setSecret(view.config.id, 'provider.claude', 'x'),
        throwsArgumentError,
      );
      expect(await env.secrets.read('provider.claude'), isNull);
    });

    test(
      'Neu laden mit abgelehntem Token: Integration im Zustand „Fehler“',
      () async {
        server.auth = FakeAuthMode.bearer;
        final view = await addAndEnable(
          c,
          draftFor(server, auth: McpAuthKind.bearer, token: server.bearerToken),
        );
        server.bearerToken = 'anders';
        final check = await source().reload(view.config.id);
        expect(check.status, McpReachability.authRequired);
        final info = c.read(toolRegistryProvider).info(view.integrationId);
        expect(info.status, IntegrationStatus.error);
        expect(info.error, startsWith('Anmeldung nötig'));
      },
    );

    test('Audit-Fehlertexte ohne Query von Adressen', () async {
      final web = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      web.listen((r) async {
        await r.drain<void>();
        r.response.statusCode = 500;
        r.response.write(
          'Fehler, siehe app.wendelin://oauth/mcp?code=GEHEIM&state=s',
        );
        await r.response.close();
      });
      addTearDown(() => web.close(force: true));
      await c.read(toolRegistryReadyProvider.future);
      final view = await source().add(
        McpDraft(
          name: 'Web',
          url: Uri.parse('http://127.0.0.1:${web.port}/mcp'),
        ),
      );
      expect(view.check!.ok, isFalse);
      var audit = '';
      for (var i = 0; i < 100 && !audit.contains('„Web“'); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        audit = jsonEncode([
          for (final e in await env.storage.audit.query()) e.toJson(),
        ]);
      }
      expect(audit, contains('MCP-Server „Web“'));
      expect(audit, isNot(contains('GEHEIM')));
    });
  });

  test('sanitizeMcpDetail entfernt code und state aus Adressen', () {
    expect(
      sanitizeMcpDetail(
        'Fehler bei app.wendelin://oauth/mcp?code=geheim&state=abc und '
        'https://as.example.org/authorize?client_id=1#x',
      ),
      'Fehler bei app.wendelin://oauth/mcp?… und '
      'https://as.example.org/authorize?…',
    );
  });
}

ToolContext _ctx() => ToolContext(
  sessionId: 's',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);
