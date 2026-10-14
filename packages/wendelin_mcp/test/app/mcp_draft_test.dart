import 'package:test/test.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';

void main() {
  final url = Uri.parse('https://mcp.example.org/mcp');

  group('McpSecretRefs', () {
    test('Referenzen enthalten nur die Server-Id und den festen Präfix', () {
      expect(McpSecretRefs.prefix('s1'), 'mcp.s1.');
      expect(McpSecretRefs.bearer('s1'), 'mcp.s1.bearer');
      expect(McpSecretRefs.header('s1', 2), 'mcp.s1.header.2');
      expect(McpSecretRefs.oauthToken('s1'), 'mcp.s1.oauth.token');
      expect(McpSecretRefs.oauthClient('s1'), 'mcp.s1.oauth.client');
    });
  });

  group('McpDraft.toConfig', () {
    test('ohne Anmeldung: keine Secrets', () {
      final (config, secrets) = McpDraft(
        name: ' Haus ',
        url: url,
      ).toConfig('s1', 'haus');
      expect(config.name, 'Haus');
      expect(config.auth, const McpNoAuth());
      expect(secrets, isEmpty);
    });

    test('Bearer: Token nur im Secret-Teil, Konfiguration trägt die '
        'Referenz', () {
      final (config, secrets) = McpDraft(
        name: 'x',
        url: url,
        auth: McpAuthKind.bearer,
        token: 'geheim',
        sensitive: true,
        confirmAll: true,
      ).toConfig('s1', 'x');
      expect(config.auth, McpBearerAuth(McpSecretRefs.bearer('s1')));
      expect(secrets, {McpSecretRefs.bearer('s1'): 'geheim'});
      expect(config.toJson().toString(), isNot(contains('geheim')));
      expect((config.sensitive, config.confirmAll), (true, true));
      final (_, none) = McpDraft(
        name: 'x',
        url: url,
        auth: McpAuthKind.bearer,
        token: '',
      ).toConfig('s1', 'x');
      expect(none, isEmpty, reason: 'leeres Token wird nicht gespeichert');
    });

    test('Header: je Header eine Referenz nach Reihenfolge', () {
      final (config, secrets) = McpDraft(
        name: 'x',
        url: url,
        auth: McpAuthKind.headers,
        headers: const [('X-A', '1'), ('X-B', ''), ('X-C', '3')],
      ).toConfig('s1', 'x');
      expect(
        config.auth,
        McpHeadersAuth({
          'X-A': McpSecretRefs.header('s1', 0),
          'X-B': McpSecretRefs.header('s1', 1),
          'X-C': McpSecretRefs.header('s1', 2),
        }),
      );
      expect(secrets, {
        McpSecretRefs.header('s1', 0): '1',
        McpSecretRefs.header('s1', 2): '3',
      });
    });

    test('OAuth: Referenzen für Token und Client, Client-Id getrimmt', () {
      final (config, secrets) = McpDraft(
        name: 'x',
        url: url,
        auth: McpAuthKind.oauth,
        clientId: ' abc ',
      ).toConfig('s1', 'x');
      expect(
        config.auth,
        McpOAuth(
          tokenRef: McpSecretRefs.oauthToken('s1'),
          clientRef: McpSecretRefs.oauthClient('s1'),
          clientId: 'abc',
        ),
      );
      expect(secrets, isEmpty);
      final (blank, _) = McpDraft(
        name: 'x',
        url: url,
        auth: McpAuthKind.oauth,
        clientId: '  ',
      ).toConfig('s1', 'x');
      expect((blank.auth as McpOAuth).clientId, isNull);
    });
  });

  test('Vorlagen: Platzhalter erkannt, eigene Vorlage zuletzt', () {
    expect(McpTemplate.hasPlaceholder('http://<rechner>.ts.net/mcp'), isTrue);
    expect(
      McpTemplate.hasPlaceholder('http://homeassistant.local/mcp'),
      isFalse,
    );
    expect(McpTemplate.all.last, same(McpTemplate.custom));
    expect(McpTemplate.all.map((t) => t.id).toSet(), hasLength(4));
    expect(McpAuthKind.values.map((k) => k.label), everyElement(isNotEmpty));
    expect(McpSignInException.noBrowser.toString(), contains('Browser'));
  });

  test('McpCheck: JSON-Rundreise, kaputte Eingaben', () {
    final check = McpCheck(
      at: DateTime.utc(2026, 10, 14, 8),
      status: McpReachability.authRequired,
      detail: 'Token abgelaufen',
      latency: const Duration(milliseconds: 42),
      serverName: 'fake 1.0',
      transport: McpTransportKind.streamable,
    );
    final back = McpCheck.fromJson(check.toJson());
    expect(back.status, McpReachability.authRequired);
    expect(back.detail, 'Token abgelaufen');
    expect(back.latency, const Duration(milliseconds: 42));
    expect(back.serverName, 'fake 1.0');
    expect(back.transport, McpTransportKind.streamable);
    expect(back.at, check.at);
    expect(back.ok, isFalse);
    final minimal = McpCheck.fromJson(
      McpCheck(at: check.at, status: McpReachability.reachable).toJson(),
    );
    expect(minimal.ok, isTrue);
    expect(minimal.detail, isNull);
    expect(() => McpCheck.fromJson(const {}), throwsFormatException);
    expect(
      () => McpCheck.fromJson({'at': 'x', 'status': 'gibtsnicht'}),
      throwsFormatException,
    );
    final probe = McpCheck.fromProbe(
      const McpProbeResult(
        status: McpReachability.unreachable,
        detail: 'weg',
        latency: Duration.zero,
      ),
      check.at,
    );
    expect(probe.status, McpReachability.unreachable);
    expect(probe.serverName, isNull);
  });
}
