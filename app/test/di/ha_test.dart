import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

void main() {
  const canary = 'kanarien-token';
  late InMemorySecretStore secrets;
  late SecretStoreHa store;
  late FakeHaApi api;

  setUp(() {
    secrets = InMemorySecretStore({'provider.anthropic.apiKey': 'fremd'});
    store = SecretStoreHa(secrets);
    api = FakeHaApi();
  });

  test('Adresse, Token und Geräte liegen nur unter ha.*', () async {
    expect(
      await haConnect(
        api: api,
        store: store,
        address: '192.168.1.20:8123',
        token: ' $canary ',
      ),
      isNull,
    );
    await store.save(const [HaEntity(entityId: 'light.a', name: 'A')]);
    expect(await secrets.listKeys(), {
      'ha.url',
      'ha.token',
      'ha.entities',
      'provider.anthropic.apiKey',
    });
    expect(
      await store.endpoint(),
      const HaEndpoint(url: 'http://192.168.1.20:8123', token: canary),
    );
    expect(store.toString(), isNot(contains(canary)));
    await haDisconnect(store);
    expect(await secrets.listKeys(), {'provider.anthropic.apiKey'});
  });

  test('unzulässige Adresse oder Token: nichts wird gespeichert', () async {
    for (final (address, token) in [
      ('http://example.com', canary),
      ('', canary),
      ('192.168.1.20', ''),
    ]) {
      expect(
        await haConnect(api: api, store: store, address: address, token: token),
        isNotNull,
        reason: address,
      );
    }
    expect(await secrets.listKeys(), {'provider.anthropic.apiKey'});
    expect(api.methodCalls, isEmpty);
  });

  test('abgelehnte Prüfung stellt den vorherigen Zugang wieder her', () async {
    await haConnect(api: api, store: store, address: '10.0.0.1', token: canary);
    await store.save(const [HaEntity(entityId: 'light.a', name: 'A')]);
    api.failNext(
      'check',
      const PortException(PortErrorKind.permissionDenied, 'abgelehnt'),
    );
    expect(
      await haConnect(api: api, store: store, address: '10.0.0.2', token: 'x'),
      'abgelehnt',
    );
    expect((await store.endpoint())!.url, 'http://10.0.0.1');
    expect(await store.load(), hasLength(1));
  });

  test('andere Instanz: Geräteauswahl wird verworfen', () async {
    await haConnect(api: api, store: store, address: '10.0.0.1', token: canary);
    await store.save(const [HaEntity(entityId: 'light.a', name: 'A')]);
    await haConnect(api: api, store: store, address: '10.0.0.1', token: 'neu');
    expect(await store.load(), hasLength(1));
    await haConnect(api: api, store: store, address: '10.0.0.2', token: canary);
    expect(await store.load(), isEmpty);
  });

  test('kaputte Geräteliste ergibt leere Liste', () async {
    await secrets.write('ha.entities', 'kein json');
    expect(await store.load(), isEmpty);
    await secrets.write('ha.entities', '{"a":1}');
    expect(await SecretStoreHa(secrets).load(), isEmpty);
  });

  test(
    'Stufe je Geräteart: ha.kind_levels, kaputt = alles D (WP160)',
    () async {
      expect((await store.kindLevels()).raw, isEmpty);
      await store.saveKindLevels(
        const HaKindLevels().withLevel(HaKind.light, SecurityLevel.a),
      );
      expect(await secrets.read('ha.kind_levels'), '{"light":"a"}');
      expect((await store.kindLevels()).levelOf(HaKind.light), SecurityLevel.a);
      await store.saveKindLevels(const HaKindLevels());
      expect(await secrets.read('ha.kind_levels'), isNull);
      await secrets.write('ha.kind_levels', 'kein json');
      final fresh = SecretStoreHa(secrets);
      expect((await fresh.kindLevels()).levelOf(HaKind.media), SecurityLevel.d);
      await secrets.write('ha.kind_levels', '{"light":7}');
      expect(
        (await SecretStoreHa(secrets).kindLevels()).levelOf(HaKind.light),
        SecurityLevel.d,
      );
      await store.clear();
      expect(await secrets.read('ha.kind_levels'), isNull);
    },
  );

  group('Speicher-Cache der Geräteliste', () {
    const a = HaEntity(entityId: 'light.a', name: 'A');
    const b = HaEntity(entityId: 'light.b', name: 'B');

    test('liest die Geräte nur einmal aus dem Secret-Store', () async {
      await store.save(const [a]);
      expect(await store.load(), [a]);
      await secrets.write('ha.entities', '[]');
      expect(await store.load(), [a]);
    });

    test('save, leeres save und clear verwerfen den Cache', () async {
      await store.save(const [a]);
      expect(await store.load(), [a]);
      await store.save(const [a, b]);
      expect(await store.load(), [a, b]);
      await store.save(const []);
      expect(await store.load(), isEmpty);
      await store.save(const [a]);
      expect(await store.load(), [a]);
      await store.clear();
      expect(await store.load(), isEmpty);
    });

    test('ein Lesefehler wird nicht zwischengespeichert', () async {
      final failing = SecretStoreHa(_FailOnce(secrets));
      await expectLater(failing.load(), throwsStateError);
      await secrets.write('ha.entities', '[{"id":"light.a","name":"A"}]');
      expect((await failing.load()), isNotEmpty);
    });
  });
}

/// Secret store whose first read throws.
final class _FailOnce implements SecretStore {
  _FailOnce(this._inner);

  final SecretStore _inner;
  bool _failed = false;

  @override
  Future<String?> read(String key) {
    if (!_failed) {
      _failed = true;
      throw StateError('Lesefehler');
    }
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> delete(String key) => _inner.delete(key);

  @override
  Future<Set<String>> listKeys() => _inner.listKeys();
}
