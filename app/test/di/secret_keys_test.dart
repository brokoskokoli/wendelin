import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/bring.dart';
import 'package:wendelin/di/http_tools.dart';
import 'package:wendelin/di/mcp/mcp_secrets.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_mcp/wendelin_mcp.dart';
import 'package:wendelin_storage/fakes.dart';

/// The key names under which secrets already lie on devices (before
/// WP39). They are written down here literally and must never change:
/// otherwise an update would lose Bring! login, HTTP-tool secrets and MCP
/// tokens.
const _bringKeys = ['bring.session'];
const _legacyBringKeys = ['bring.email', 'bring.password'];
const _httpKeys = [
  'http_tool.tool-1.bearer',
  'http_tool.tool-1.h.x-api-key',
  'http_tool.tool-10.bearer',
];
const _mcpKeys = [
  'mcp.s1.bearer',
  'mcp.s1.header.0',
  'mcp.s1.oauth.token',
  'mcp.s1.oauth.client',
];

final class _Ids implements IdGenerator {
  @override
  String next() => 'neu';
}

void main() {
  const canary = 'kanarienvogel-schluessel-4711';

  InMemorySecretStore deviceStore() => InMemorySecretStore({
    for (final k in [..._bringKeys, ..._httpKeys, ..._mcpKeys]) k: canary,
    'provider.anthropic.apiKey': 'fremd',
  });

  test('Bring!: Migration löscht E-Mail und Passwort, Sitzung bleibt; '
      'idempotent', () async {
    final store = deviceStore();
    await store.write('bring.session', '{"userUuid":"u","accessToken":"t"}');
    for (final k in _legacyBringKeys) {
      await store.write(k, canary);
    }
    final s = SecretStoreBringSecrets(store);
    // Schon das erste Lesen der Sitzung wartet auf die Migration.
    expect((await s.auth())!.userUuid, 'u');
    expect(await store.listKeys(), {
      ..._bringKeys,
      ..._httpKeys,
      ..._mcpKeys,
      'provider.anthropic.apiKey',
    });
    expect(await store.read('bring.email'), isNull);
    expect(await store.read('bring.password'), isNull);
    await s.removeLegacyLogin();
    expect((await s.auth())!.userUuid, 'u');
    await s.clear();
    expect(await store.listKeys(), {
      ..._httpKeys,
      ..._mcpKeys,
      'provider.anthropic.apiKey',
    });
  });

  test(
    'Bring!: nach der Anmeldung liegt nur die Sitzung im Speicher',
    () async {
      final store = InMemorySecretStore();
      final s = SecretStoreBringSecrets(store);
      await s.saveAuth(const BringAuth(userUuid: 'u', accessToken: 't'));
      expect(await store.listKeys(), _bringKeys.toSet());
    },
  );

  test('HTTP-Tools: alte Schlüssel werden gelesen, Löschen räumt nur das '
      'eigene Tool', () async {
    final store = deviceStore();
    final s = SecretStoreHttpToolSecrets(store);
    expect(await s.read('tool-1.bearer'), canary);
    expect(await s.read('tool-1.h.x-api-key'), canary);
    final vault = SecretStoreHttpToolVault(store);
    expect(await vault.refs(), {
      'tool-1.bearer',
      'tool-1.h.x-api-key',
      'tool-10.bearer',
    });
    final repo = HttpToolRepository(
      store: FakeHttpToolStore(),
      secrets: vault,
      ids: _Ids(),
    );
    await repo.deleteSecretsOfRemoved('tool-1');
    expect(await store.listKeys(), {
      ..._bringKeys,
      'http_tool.tool-10.bearer',
      ..._mcpKeys,
      'provider.anthropic.apiKey',
    });
    await repo.dispose();
  });

  test('MCP: Referenzen sind die gespeicherten Schlüssel', () async {
    final store = deviceStore();
    final s = SecretStoreMcpSecrets(store);
    for (final key in _mcpKeys) {
      expect(await s.read(key), canary, reason: key);
    }
    expect(McpSecretRefs.bearer('s1'), _mcpKeys[0]);
    expect(McpSecretRefs.header('s1', 0), _mcpKeys[1]);
    expect(McpSecretRefs.oauthToken('s1'), _mcpKeys[2]);
    expect(McpSecretRefs.oauthClient('s1'), _mcpKeys[3]);
    for (final key in _mcpKeys) {
      await s.delete(key);
    }
    expect(await store.listKeys(), {
      ..._bringKeys,
      ..._httpKeys,
      'provider.anthropic.apiKey',
    });
    await s.write('mcp.s2.bearer', 'neu');
    expect(await store.read('mcp.s2.bearer'), 'neu');
  });

  test(
    'MCP: fremde Schlüssel sind unsichtbar und nicht beschreibbar',
    () async {
      final store = deviceStore();
      final s = SecretStoreMcpSecrets(store);
      expect(await s.read('bring.session'), isNull);
      expect(await s.read('provider.anthropic.apiKey'), isNull);
      expect(await s.read('mcp.'), isNull);
      await s.delete('bring.session');
      expect(await store.read('bring.session'), canary);
      await expectLater(s.write('bring.session', 'x'), throwsArgumentError);
      expect(await store.read('bring.session'), canary);
    },
  );
}
