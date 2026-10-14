import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:wendelin_core/fakes.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

import 'repo_support.dart';

final class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String next() => 'neu-${++_n}';
}

void main() {
  group('HttpToolSource', () {
    late FakeHttpToolStore store;
    late HttpToolRepository repo;
    late HttpToolSource source;
    final runner = HttpToolRunner(
      transport: ClientHttpToolTransport(
        MockClient((_) async => http.Response('', 500)),
      ),
      secrets: FakeHttpToolSecrets(),
    );

    setUp(() {
      store = FakeHttpToolStore();
      repo = HttpToolRepository(
        store: store,
        secrets: FakeHttpToolSecretVault(),
        ids: _Ids(),
      );
      source = HttpToolSource(repo, runner);
    });
    tearDown(() => repo.dispose());

    test('ohne Tools keine Integration; unverändert dasselbe Objekt; '
        'sensibel getrennt', () async {
      expect(source.kind, UserIntegrationKind.http);
      expect(await source.load(), isEmpty);
      await repo.save(testHttpTool());
      final first = await source.load();
      expect(first.map((i) => i.id), ['http']);
      expect(first.single.tools.single.name, 'http__licht');
      expect(await source.load(), [same(first.single)]);

      await repo.save(testHttpTool(id: 's', name: 'geheim', sensitive: true));
      final second = await source.load();
      expect(second.map((i) => i.id), ['http', 'http_sensitive']);
      expect(second.first, same(first.single), reason: 'http unverändert');
      expect(second.last.sensitive, isTrue);

      await repo.save(testHttpTool().copyWith(enabled: false));
      final third = await source.load();
      expect(third.map((i) => i.id), ['http_sensitive']);
      expect(third.single, same(second.last));
    });

    test('deleteSecrets räumt nur Tools auf, die wirklich weg sind', () async {
      final secrets = FakeHttpToolSecretVault();
      repo = HttpToolRepository(store: store, secrets: secrets, ids: _Ids());
      source = HttpToolSource(repo, runner);
      final a = testHttpTool(id: 'a', name: 'a');
      final b = testHttpTool(id: 'b', name: 'b');
      for (final d in [a, b]) {
        await repo.save(
          d,
          secretValues: {httpHeaderRef(d.id, 'X-Api-Key'): httpCanary},
        );
      }
      final integration = (await source.load()).single;
      store.stored = [b.toJson()];
      final fresh = HttpToolRepository(
        store: store,
        secrets: secrets,
        ids: _Ids(),
      );
      await HttpToolSource(fresh, runner).deleteSecrets(
        IntegrationRemoval(
          integration: integration,
          toolNames: {'http__a', 'http__b'},
          whole: false,
        ),
      );
      expect(await secrets.refs(), {'b.h.x-api-key'});
      // Keine HTTP-Integration: nichts zu tun.
      await source.deleteSecrets(
        IntegrationRemoval(
          integration: FakeIntegration(id: 'x', tools: const []),
          toolNames: const {},
          whole: true,
        ),
      );
    });
  });
}
