import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/agent/bring_share.dart';
import 'package:wendelin/di/bring.dart';
import 'package:wendelin/di/http_tools.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/testing.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../support/http_tools_support.dart';

final class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'neu-${++_n}';
}

void main() {
  httpToolSecretsContract('SecretStoreHttpToolSecrets', (values) async {
    final store = InMemorySecretStore();
    for (final e in values.entries) {
      await store.write('http_tool.${e.key}', e.value);
    }
    return SecretStoreHttpToolSecrets(store);
  });

  test('Adapter liest nur im eigenen Namensraum', () async {
    final store = InMemorySecretStore({
      'provider.anthropic.key': httpCanary,
      'bring.password': httpCanary,
    });
    final s = SecretStoreHttpToolSecrets(store);
    expect(await s.read('provider.anthropic.key'), isNull);
    expect(await s.read('../bring.password'), isNull);
    expect(await s.read(''), isNull);
    expect('$s', isNot(contains(httpCanary)));
    final pending = PendingHttpToolSecrets(s, {'a': 'neu', 'b': null});
    await store.write('http_tool.b', 'alt');
    await store.write('http_tool.c', 'gespeichert');
    expect(await pending.read('a'), 'neu');
    expect(await pending.read('b'), isNull, reason: 'entfernt');
    expect(await pending.read('c'), 'gespeichert');
    expect('$pending', isNot(contains('neu')));
  });

  group('Adapter der HttpToolRepository', () {
    late WendelinStorage storage;
    late InMemorySecretStore secrets;
    late HttpToolRepository repo;

    setUp(() {
      storage = openInMemoryStorage(clock: FixedClock(DateTime(2026, 10, 13)));
      secrets = InMemorySecretStore({'provider.x': 'fremd'});
      repo = HttpToolRepository(
        store: SettingsHttpToolStore(storage.settings),
        secrets: SecretStoreHttpToolVault(secrets),
        ids: _Ids(),
      );
    });
    tearDown(() async {
      await repo.dispose();
      await storage.close();
    });

    test('Definition in den Einstellungen `http.tools`, Secret unter '
        '`http_tool.<ref>`, Löschen räumt beides auf', () async {
      final d = testHttpTool();
      await repo.save(
        d,
        secretValues: {httpHeaderRef(d.id, 'X-Api-Key'): httpCanary},
      );
      final raw = await storage.settings.get(httpToolsSetting);
      expect(raw, [d.toJson()]);
      expect(jsonEncode(raw), isNot(contains(httpCanary)));
      expect(await secrets.read('http_tool.tool-1.h.x-api-key'), httpCanary);
      expect(await secrets.listKeys(), {
        'provider.x',
        'http_tool.tool-1.h.x-api-key',
      });
      await repo.delete(d.id);
      expect(await storage.settings.get(httpToolsSetting), isEmpty);
      expect(await secrets.listKeys(), {'provider.x'});
    });

    test('Kanarienschlüssel unter den alten Namen werden gelesen und beim '
        'Löschen entfernt', () async {
      final d = testHttpTool();
      await storage.settings.set(httpToolsSetting, [d.toJson()]);
      await secrets.write('http_tool.tool-1.h.x-api-key', httpCanary);
      await secrets.write('http_tool.tool-10.bearer', 'anderes-tool');
      expect(await repo.hasSecret('tool-1.h.x-api-key'), isTrue);
      expect(
        await SecretStoreHttpToolSecrets(secrets).read('tool-1.h.x-api-key'),
        httpCanary,
      );
      await repo.delete('tool-1');
      expect(await secrets.listKeys(), {
        'provider.x',
        'http_tool.tool-10.bearer',
      });
    });

    test('Fremde Schlüssel sind für den Vault unsichtbar', () async {
      final vault = SecretStoreHttpToolVault(secrets);
      expect(await vault.refs(), isEmpty);
      expect(await vault.read('provider.x'), isNull);
      expect('$vault', isNot(contains('fremd')));
    });
  });

  group('Bring!', () {
    test('SecretStore-Adapter: nur die Sitzung, abmelden löscht', () async {
      final store = InMemorySecretStore();
      final s = SecretStoreBringSecrets(store);
      expect(await s.auth(), isNull);
      const auth = BringAuth(userUuid: 'u', accessToken: 'tok');
      await s.saveAuth(auth);
      expect(await s.auth(), auth);
      await store.write('bring.session', 'kaputt');
      expect(await s.auth(), isNull);
      await s.saveAuth(null);
      expect(await store.read('bring.session'), isNull);
      await s.clear();
      expect(await store.listKeys(), isEmpty);
      expect('$s', isNot(contains(httpCanary)));
    });

    test('Share-Text nur bei API-Fehlern von bring__add_items', () {
      ToolCallBlock add(String args) =>
          ToolCallBlock(id: 'c', name: 'bring__add_items', argumentsJson: args);
      final failed = ToolOutcome.error(
        'Bring! nicht erreichbar. $bringRetryHint',
      );
      expect(
        bringShareTextFor(
          add('{"items":[{"name":"Milch","spec":"2 Liter"},"Eier",{"x":1}]}'),
          failed,
        ),
        'Milch (2 Liter)\nEier',
      );
      expect(
        bringShareTextFor(
          add('{"items":["Brot"]}'),
          ToolOutcome.error('Login abgelehnt. $bringFallbackHint'),
        ),
        'Brot',
      );
      expect(
        bringShareTextFor(
          add('{"items":["Brot"]}'),
          ToolOutcome.error('Keine Bring!-Liste „x“'),
        ),
        isNull,
        reason: 'kein API-Fehler',
      );
      expect(bringShareTextFor(add('{"items":[]}'), failed), isNull);
      expect(bringShareTextFor(add('{'), failed), isNull);
      expect(
        bringShareTextFor(add('{"items":["Brot"]}'), ToolOutcome.text('ok')),
        isNull,
      );
      expect(
        bringShareTextFor(
          const ToolCallBlock(
            id: 'c',
            name: 'bring__remove_item',
            argumentsJson: '{}',
          ),
          failed,
        ),
        isNull,
      );
    });
  });
}
