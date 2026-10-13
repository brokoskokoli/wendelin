import 'dart:async';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_mcp/testing.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

void main() {
  late FakeMcpServer server;
  late http.Client httpClient;
  final cleanups = <Future<void> Function()>[];

  ToolContext ctx([CancelToken? cancel]) => ToolContext(
    sessionId: 's',
    clock: FixedClock(DateTime.utc(2026, 10, 13)),
    locale: 'de-DE',
    timeZone: 'Europe/Berlin',
    cancel: cancel,
  );

  setUp(() async {
    server = await FakeMcpServer.start(
      style: FakeResponseStyle.sse,
      tools: [
        FakeMcpTool(
          'get_weather',
          description: 'Wetter abfragen',
          inputSchema: {
            'type': 'object',
            'properties': {
              'city': {'type': 'string', 'pattern': '^[A-Z]'},
            },
            'required': ['city'],
          },
          annotations: {'readOnlyHint': true},
          handler: (args) => {
            'content': [
              {'type': 'text', 'text': 'Sonne in ${args['city']}'},
            ],
          },
        ),
        FakeMcpTool(
          'docker.restart',
          description: 'x' * 2000,
          annotations: {'destructiveHint': true},
          handler: (_) => {
            'content': [
              {'type': 'text', 'text': 'Container läuft nicht'},
            ],
            'isError': true,
          },
        ),
        FakeMcpTool('note_add', annotations: {'destructiveHint': false}),
        FakeMcpTool('debug_dump'),
        FakeMcpTool(
          'slow',
          handler: (_) async {
            await Future<void>.delayed(const Duration(seconds: 5));
            return {'content': <Object?>[]};
          },
        ),
      ],
    );
    httpClient = http.Client();
  });

  tearDown(() async {
    for (final c in cleanups.reversed) {
      await c();
    }
    cleanups.clear();
    httpClient.close();
    await server.close();
  });

  McpIntegration integration({
    McpAuth auth = const McpNoAuth(),
    FakeMcpSecrets? secrets,
    McpOAuthFlow? oauth,
    bool confirmAll = false,
    bool sensitive = false,
    Map<String, McpToolOverride> overrides = const {},
    McpErrorReporter? reportError,
    Uri? url,
    McpCacheStore? cache,
    McpCallObserver? onCall,
  }) {
    final client = McpClient(
      config: McpServerConfig(
        id: 'home-1',
        name: 'Home',
        slug: 'home',
        url: url ?? server.url,
        auth: auth,
        confirmAll: confirmAll,
        sensitive: sensitive,
        toolOverrides: overrides,
      ),
      httpClient: httpClient,
      secrets: secrets ?? FakeMcpSecrets(),
      oauth: oauth,
      cache: cache,
    );
    final i = McpIntegration(
      client: client,
      reportError: reportError,
      onCall: onCall,
    );
    cleanups
      ..add(client.dispose)
      ..add(i.dispose);
    return i;
  }

  test('Integration: Kennung, Anzeige, keine Einrichtung ohne Auth', () async {
    final i = integration(sensitive: true);
    expect(i.id, 'mcp_home');
    expect(Tool.isValidToolName(i.id), isTrue);
    expect(i.displayName, 'Home');
    expect(i.iconId, 'mcp');
    expect(i.platforms, {AppPlatform.android, AppPlatform.ios});
    expect(i.sensitive, isTrue);
    expect(i.setup, isEmpty);
    expect((await i.setupState()).complete, isTrue);
    expect(await i.checkAvailability(), Availability.yes);
    expect(i.tools, isEmpty);
  });

  test('Tools: Ergebnisse sind nie vertrauenswürdig (WP41)', () async {
    final tools = await integration().loadTools();
    expect(tools, isNotEmpty);
    for (final t in tools) {
      expect(t, isNot(isA<TrustedContentSource>()), reason: t.name);
    }
  });

  test('Tools: Namen, Risiko, Overrides, abgeschaltete fehlen', () async {
    final i = integration(
      overrides: const {
        'debug_dump': McpToolOverride(enabled: false),
        'get_weather': McpToolOverride(risk: RiskLevel.write),
        'docker.restart': McpToolOverride(risk: RiskLevel.read),
        'note_add': McpToolOverride(autoRun: true),
      },
    );
    final changed = i.toolsChanged.first;
    final tools = await i.loadTools();
    await changed;
    final byMcp = {for (final t in tools) t.mcpName: t};
    expect(byMcp.keys, ['get_weather', 'docker.restart', 'note_add', 'slow']);
    expect(byMcp['get_weather']!.name, 'mcp_home__get_weather');
    expect(byMcp['get_weather']!.risk, RiskLevel.write); // verschärft
    expect(
      byMcp['docker.restart']!.risk,
      RiskLevel.external,
    ); // nicht gelockert
    expect(
      byMcp['docker.restart']!.name,
      matches(RegExp(r'^mcp_home__docker_restart_[0-9a-f]{6}$')),
    );
    expect(byMcp['note_add']!.risk, RiskLevel.write); // autoRun
    expect(byMcp['slow']!.risk, RiskLevel.external); // ohne Angaben
    expect(i.skippedTools.single.toString(), 'debug_dump: abgeschaltet');
    expect(i.tools, same(i.mcpTools));
    for (final t in tools) {
      expect(Tool.isValidToolName(t.name), isTrue);
    }
    expect(byMcp['get_weather']!.unsupportedSchemaParts, ['city: pattern']);
    expect(byMcp['get_weather']!.inputSchema['required'], ['city']);
    expect(byMcp['docker.restart']!.description.length, maxMcpDescription);
    expect(byMcp['note_add']!.description, 'note_add');
    expect(byMcp['get_weather']!.toString(), contains('get_weather'));
    expect(byMcp['get_weather']!.spec.name, 'mcp_home__get_weather');
  });

  test(
    'Kontextbudget: zu große Schemas und zu viele Tools werden gemeldet',
    () {
      final i = integration();
      Map<String, Object?> schemaOf(int bytes) => {
        'type': 'object',
        'description': 'x' * bytes,
      };
      final tools = i.buildTools([
        McpToolInfo(name: 'gross', inputSchema: schemaOf(maxSchemaBytes)),
        McpToolInfo(name: 'grenze', inputSchema: schemaOf(maxSchemaBytes - 60)),
        for (var n = 0; n < maxToolsPerServer + 2; n++)
          McpToolInfo(name: 'tool_$n'),
      ]);
      expect(tools, hasLength(maxToolsPerServer));
      expect(tools.first.mcpName, 'grenze');
      expect(
        McpSchema.from(schemaOf(maxSchemaBytes - 60)).withinBudget,
        isTrue,
      );
      final skipped = {for (final s in i.skippedTools) s.name: s.reason};
      expect(skipped.keys, ['gross', 'tool_127', 'tool_128', 'tool_129']);
      expect(skipped['gross'], startsWith('Schema zu groß (8 KB'));
      expect(skipped['tool_129'], 'mehr als 128 Tools auf diesem Server');
    },
  );

  test('onCall meldet Antwort, Tool-Fehler und Verbindungsfehler, nicht den '
      'Abbruch', () async {
    final seen = <McpErrorKind?>[];
    final i = integration(onCall: (e) => seen.add(e?.kind));
    await i.loadTools(refresh: true);
    Tool tool(String n) => i.mcpTools.firstWhere((t) => t.mcpName == n);
    await tool('get_weather').execute({'city': 'Kiel'}, ctx());
    await tool('docker.restart').execute(const {}, ctx());
    final cancel = CancelToken();
    final slow = tool('slow').execute(const {}, ctx(cancel));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    cancel.cancel();
    await slow;
    await server.close();
    await tool('note_add').execute(const {}, ctx());
    expect(seen, [null, null, McpErrorKind.network]);
  });

  test('doppelte Tool-Namen: erstes Vorkommen bleibt', () {
    final i = integration();
    final tools = i.buildTools([
      const McpToolInfo(name: 'dup', description: 'erstes'),
      const McpToolInfo(name: 'dup', description: 'zweites'),
      const McpToolInfo(name: 'anders'),
    ]);
    expect(tools.map((t) => t.name), ['mcp_home__dup', 'mcp_home__anders']);
    expect(tools.first.description, 'erstes');
    expect(i.skippedTools.single.toString(), 'dup: Name doppelt vergeben');
  });

  test('confirmAll macht alle Tools external', () async {
    final tools = await integration(confirmAll: true).loadTools();
    expect(tools.every((t) => t.risk == RiskLevel.external), isTrue);
  });

  test('Ausführen: Ergebnis in der Daten-Hülle, kein Undo', () async {
    final i = integration();
    final weather = (await i.loadTools()).firstWhere(
      (t) => t.mcpName == 'get_weather',
    );
    final outcome = await weather.execute({'city': 'Kiel'}, ctx());
    expect(outcome.isError, isFalse);
    expect(outcome.undo, isNull);
    expect(outcome.text, contains('Sonne in Kiel'));
    expect(outcome.text, startsWith(mcpDataNotice));
    expect(outcome.summary, 'Home: get_weather ausgeführt');
    final call = server.requests.lastWhere((r) => r.rpcMethod == 'tools/call');
    expect(call.body, contains('"name":"get_weather"'));
  });

  test('Ausführen: isError, Protokollfehler, Abbruch', () async {
    final i = integration();
    final tools = {for (final t in await i.loadTools()) t.mcpName: t};
    final failed = await tools['docker.restart']!.execute(const {}, ctx());
    expect(failed.isError, isTrue);
    expect(failed.text, contains('Container läuft nicht'));

    server.tools.removeWhere((t) => t.name == 'note_add');
    final missing = await tools['note_add']!.execute(const {}, ctx());
    expect(missing.isError, isTrue);
    expect(
      missing.text,
      startsWith('MCP-Server „Home“: Server meldet Fehler -32602'),
    );
    expect(missing.summary, 'Home: Fehler');

    final cancel = CancelToken();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 100), cancel.cancel),
    );
    final cancelled = await tools['slow']!.execute(const {}, ctx(cancel));
    expect(cancelled.text, ToolOutcome.cancelledText);
    expect(cancelled.isError, isTrue);
  });

  test('Bestätigungstext: Server, Tool, gekürzte Argumente', () async {
    final tools = {
      for (final t in await integration().loadTools()) t.mcpName: t,
    };
    expect(
      tools['docker.restart']!.describeForConfirmation({'container': 'web'}),
      'Home: docker.restart {"container":"web"}',
    );
    expect(
      tools['note_add']!.describeForConfirmation(const {}),
      'Home: note_add',
    );
    final long = tools['note_add']!.describeForConfirmation({
      'text': 'y' * 500,
    });
    expect(long.length, lessThan(140));
    expect(long, endsWith('…'));
  });

  test('Cache: Tools ohne Serverkontakt', () async {
    final cache = InMemoryMcpCacheStore();
    await integration(cache: cache).loadTools();
    final requests = server.requests.length;
    final cached = integration(cache: cache);
    expect(await cached.loadCachedTools(), hasLength(5));
    expect(server.requests.length, requests);
    expect(await integration().loadCachedTools(), isEmpty);
  });

  test('list_changed: neu laden und melden', () async {
    final i = integration();
    final weather = (await i.loadTools()).firstWhere(
      (t) => t.mcpName == 'get_weather',
    );
    server
      ..sendListChanged = true
      ..tools.add(FakeMcpTool('neu'));
    final reloaded = i.toolsChanged.first;
    await weather.execute({'city': 'Kiel'}, ctx());
    await reloaded.timeout(const Duration(seconds: 5));
    expect(i.tools.map((t) => t.name), contains('mcp_home__neu'));
  });

  group('Status', () {
    test(
      'Bearer: fehlendes Secret → Einrichtung nötig, ohne Serverkontakt',
      () async {
        final i = integration(auth: const McpBearerAuth('home.bearer'));
        expect(i.setup.single.id, McpIntegration.authStep);
        expect(i.setup.single.kind, SetupStepKind.login);
        expect(i.setup.single.label, 'Zugangsdaten eintragen');
        expect((await i.setupState()).missingSteps, [McpIntegration.authStep]);
        expect(await i.checkAvailability(), Availability.yes);
        expect(server.requests, isEmpty);
      },
    );

    test('Bearer abgelehnt → Einrichtung nötig', () async {
      server.auth = FakeAuthMode.bearer;
      final i = integration(
        auth: McpHeadersAuth({'authorization': 'h'}),
        secrets: FakeMcpSecrets({'h': 'Bearer falsch'}),
      );
      expect((await i.setupState()).complete, isTrue);
      expect(await i.checkAvailability(), Availability.yes);
      expect((await i.setupState()).missingSteps, [McpIntegration.authStep]);
      // Richtiger Wert → wieder vollständig.
      final ok = integration(
        auth: McpHeadersAuth({'authorization': 'h'}),
        secrets: FakeMcpSecrets({'h': 'Bearer ${server.bearerToken}'}),
      );
      expect(await ok.checkAvailability(), Availability.yes);
      expect((await ok.setupState()).complete, isTrue);
    });

    test(
      'nicht erreichbar / kein MCP-Server → nicht verfügbar mit Grund',
      () async {
        final offline = integration(url: Uri.parse('http://127.0.0.1:1/mcp'));
        final a = await offline.checkAvailability();
        expect(a.available, isFalse);
        expect(a.reason, startsWith('Nicht erreichbar'));
        final wrong = integration(
          url: server.origin.replace(path: '/kein-mcp'),
        );
        final b = await wrong.checkAvailability();
        expect(b.available, isFalse);
        expect(b.reason, startsWith('Kein gültiger MCP-Server'));
      },
    );

    test(
      'OAuth: abgelaufenes, nicht erneuerbares Token → Fehler, Tools pausiert',
      () async {
        server
          ..auth = FakeAuthMode.oauth
          ..rejectRefresh = true;
        final secrets = FakeMcpSecrets();
        final flow = McpOAuthFlow(
          client: httpClient,
          secrets: secrets,
          browser: FakeAuthorizationBrowser(),
          redirectUri: Uri.parse('app.wendelin://oauth/mcp'),
          random: Random(3),
        );
        final reported = <String, String>{};
        final i = integration(
          auth: McpOAuth(tokenRef: 'tok', clientRef: 'cli'),
          secrets: secrets,
          oauth: flow,
          reportError: (id, message) => reported[id] = message,
        );
        expect(i.setup.single.label, 'Beim Server anmelden');
        expect((await i.setupState()).complete, isFalse);
        await flow.authorize(i.config);
        expect((await i.setupState()).complete, isTrue);
        expect(await i.checkAvailability(), Availability.yes);
        final tool = (await i.loadTools()).first;

        server.expireAccessTokens();
        final outcome = await tool.execute({'city': 'Kiel'}, ctx());
        expect(outcome.isError, isTrue);
        expect(outcome.text, contains('abgelaufen'));
        expect(reported['mcp_home'], contains('Anmeldung nötig'));
        expect((await i.setupState()).missingSteps, [McpIntegration.authStep]);

        // loadTools meldet den Fehler ebenfalls.
        reported.clear();
        await expectLater(
          i.loadTools(refresh: true),
          throwsA(isA<McpException>()),
        );
        expect(reported, contains('mcp_home'));
      },
    );

    test('OAuth ohne Flow: nie vollständig', () async {
      final i = integration(
        auth: McpOAuth(tokenRef: 't', clientRef: 'c'),
      );
      expect((await i.setupState()).complete, isFalse);
    });
  });
}
