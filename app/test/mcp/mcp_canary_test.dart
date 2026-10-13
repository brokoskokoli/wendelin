import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:wendelin/di/mcp/mcp_secrets.dart';
import 'package:wendelin/di/mcp/mcp_source.dart';
import 'package:wendelin/di/mcp/mcp_templates.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/mcp_support.dart';

/// Kanarienwert: darf nur im SecretStore und im Header an den Server
/// auftauchen.
const canary = 'CANARY-mcp-7f3a9c1e5b2d';

/// Every value the MCP source writes into the settings, as JSON.
final class _RecordingSettings implements SettingsRepository {
  _RecordingSettings(this._inner);

  final SettingsRepository _inner;
  final List<String> written = [];

  @override
  Future<T?> get<T extends Object>(SettingKey<T> key) => _inner.get(key);

  @override
  Future<void> set<T extends Object>(SettingKey<T> key, T value) {
    written.add('${key.name}=${jsonEncode(key.encode(value))}');
    return _inner.set(key, value);
  }

  @override
  Future<void> remove(SettingKey<Object> key) => _inner.remove(key);
}

void main() {
  late WendelinStorage storage;
  late InMemorySecretStore secretStore;
  late _RecordingSettings settings;
  late http.Client client;
  late List<String> logs;
  late List<String> printed;
  late DebugPrintCallback originalPrint;

  setUp(() {
    allowRealHttp();
    storage = openInMemoryStorage(clock: FixedClock(DateTime(2026, 10, 13)));
    secretStore = InMemorySecretStore();
    settings = _RecordingSettings(storage.settings);
    client = http.Client();
    logs = [];
    printed = [];
    originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => printed.add('$message');
  });

  tearDown(() async {
    debugPrint = originalPrint;
    client.close();
    await storage.close();
  });

  McpServerSource source({AuthorizationBrowser? browser}) => McpServerSource(
    settings: settings,
    secrets: SecretStoreMcpSecrets(secretStore),
    httpClient: client,
    browser: browser ?? FakeAuthorizationBrowser(),
    ids: UuidV4Generator(),
    audit: storage.audit,
    log: logs.add,
  );

  Future<void> expectNowhere(
    McpServerSource s,
    Iterable<String> secrets,
  ) async {
    final audit = jsonEncode([
      for (final e in await storage.audit.query()) e.toJson(),
    ]);
    final export = s.exportJson();
    final places = {
      'Einstellungen': settings.written.join('\n'),
      'Audit-Log': audit,
      'Export': export,
      'Debug-Log (McpLog)': logs.join('\n'),
      'Debug-Log (debugPrint)': printed.join('\n'),
    };
    for (final secret in secrets) {
      for (final MapEntry(key: place, value: text) in places.entries) {
        expect(text, isNot(contains(secret)), reason: place);
      }
    }
    expect(settings.written, isNotEmpty);
    expect(logs, isNotEmpty);
  }

  test('Bearer-Token: weder in Einstellungen, Export, Audit noch Debug-Log, '
      'auch wenn der Server es zurückspiegelt', () async {
    final server =
        await FakeMcpServer.start(tools: homeTools(), auth: FakeAuthMode.bearer)
          ..bearerToken = canary;
    addTearDown(server.close);
    final s = source();
    final view = await s.add(
      draftFor(server, auth: McpAuthKind.bearer, token: canary),
    );
    expect(view.check!.ok, isTrue);
    expect(
      await secretStore.read(McpSecretRefs.bearer(view.config.id)),
      canary,
    );
    // Call a tool, then an expired token (401) and a server that echoes
    // all headers in its error text (worst case).
    final tool = view.integration.tools.firstWhere(
      (t) => t.name.endsWith('get_state'),
    );
    await tool.execute(const {'entity': 'x'}, _ctx());
    server.bearerToken = 'anders';
    await s.reload(view.config.id);

    final echo = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    echo.listen((req) async {
      await utf8.decoder.bind(req).join();
      final headers = StringBuffer();
      req.headers.forEach((k, v) => headers.write('$k=${v.join()} '));
      req.response.statusCode = 500;
      req.response.write('Fehler, Anfrage war: $headers');
      await req.response.close();
    });
    addTearDown(() => echo.close(force: true));
    await s.update(
      view.config.copyWith(url: Uri.parse('http://127.0.0.1:${echo.port}/mcp')),
    );
    final check = await s.reload(view.config.id);
    expect(check.ok, isFalse);
    expect(check.detail, contains('***'));

    await expectNowhere(s, [canary]);
    await s.dispose();
  });

  test(
    'OAuth-Tokens: weder in Einstellungen, Export, Audit noch Debug-Log',
    () async {
      final server = await FakeMcpServer.start(
        tools: homeTools(),
        auth: FakeAuthMode.oauth,
      );
      addTearDown(server.close);
      final s = source();
      final view = await s.add(draftFor(server, auth: McpAuthKind.oauth));
      await s.signIn(view.config.id);
      final tool = s.server(view.config.id)!.integration.tools.first;
      await tool.execute(const {'entity': 'x'}, _ctx());
      // Refresh after expiry.
      server.expireAccessTokens();
      await s.reload(view.config.id);

      final secrets = {...server.accessTokens, ...server.refreshTokens};
      expect(secrets, isNotEmpty);
      final stored = await secretStore.read(
        McpSecretRefs.oauthToken(view.config.id),
      );
      for (final t in server.accessTokens) {
        if (stored!.contains(t)) return expectNowhere(s, secrets);
      }
      fail('Token nicht im SecretStore');
    },
  );

  test('Rückleitung mit code/state erscheint nicht im Audit', () async {
    final server = await FakeMcpServer.start(auth: FakeAuthMode.oauth);
    addTearDown(server.close);
    final s = source(
      browser: FakeAuthorizationBrowser(
        tamper: (u) => u.replace(
          queryParameters: {...u.queryParameters, 'state': 'fremd'},
        ),
      ),
    );
    final view = await s.add(draftFor(server, auth: McpAuthKind.oauth));
    await expectLater(s.signIn(view.config.id), throwsA(isA<McpException>()));
    final audit = jsonEncode([
      for (final e in await storage.audit.query()) e.toJson(),
    ]);
    expect(audit, contains('Anmeldung fehlgeschlagen'));
    expect(audit, isNot(contains('code=')));
    expect(audit, isNot(contains('state=')));
  });
}

ToolContext _ctx() => ToolContext(
  sessionId: 's',
  clock: const SystemClock(),
  locale: 'de-DE',
  timeZone: 'Europe/Berlin',
);
