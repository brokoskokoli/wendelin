import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';

import '../src/ports.dart';

/// Creates a fresh, empty [McpSecrets] under test.
typedef McpSecretsFactory = FutureOr<McpSecrets> Function();

/// Reusable contract suite for every [McpSecrets] implementation
/// (`FakeMcpSecrets`, the app's store on top of its `SecretStore`).
///
/// Checks what the MCP client relies on: a missing reference reads as
/// `null`, values (token sets as JSON, header values with Unicode, long
/// tokens) come back unchanged, writes overwrite, references are
/// independent, and deleting a missing reference is no error (the app
/// deletes secrets of a removed server twice: at once and in the
/// follow-up cleanup).
void mcpSecretsContract(
  McpSecretsFactory create, {
  String name = 'McpSecrets',
}) {
  group('$name erfüllt McpSecrets-Vertrag', () {
    test('fehlende Referenz liefert null', () async {
      final s = await create();
      expect(await s.read('mcp.fehlt.bearer'), isNull);
    });

    test('write und read liefern den Wert unverändert', () async {
      final s = await create();
      final tokenSet = jsonEncode({
        'accessToken': 'at-ä€🎵',
        'refreshToken': 'rt "quoted" \\',
        'expiresAt': '2026-10-13T08:12:00.000Z',
        'tokenEndpoint': 'https://auth.example.org/token',
        'clientId': 'c-1',
        'resource': 'https://mcp.example.org/mcp',
      });
      final values = {
        'mcp.s1.bearer': 'eyJhbGciOi.${'x' * 2048}',
        'mcp.s1.header.0': '  Wert mit Rand\nzweite Zeile ',
        'mcp.s1.oauth.token': tokenSet,
      };
      for (final e in values.entries) {
        await s.write(e.key, e.value);
      }
      for (final e in values.entries) {
        expect(await s.read(e.key), e.value, reason: e.key);
      }
    });

    test('write überschreibt den alten Wert', () async {
      final s = await create();
      await s.write('mcp.s1.bearer', 'alt');
      await s.write('mcp.s1.bearer', 'neu');
      expect(await s.read('mcp.s1.bearer'), 'neu');
    });

    test('Referenzen sind unabhängig voneinander', () async {
      final s = await create();
      await s.write('mcp.s1.bearer', '1');
      await s.write('mcp.s2.bearer', '2');
      await s.delete('mcp.s1.bearer');
      expect(await s.read('mcp.s1.bearer'), isNull);
      expect(await s.read('mcp.s2.bearer'), '2');
    });

    test('delete entfernt, fehlende Referenz ist kein Fehler', () async {
      final s = await create();
      await s.write('mcp.s1.oauth.client', '{"client_id":"c"}');
      await s.delete('mcp.s1.oauth.client');
      expect(await s.read('mcp.s1.oauth.client'), isNull);
      await s.delete('mcp.s1.oauth.client');
      await s.delete('mcp.nie.geschrieben');
    });
  });
}
