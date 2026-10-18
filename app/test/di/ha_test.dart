import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/home_assistant.dart';
import 'package:wendelin_integrations/fakes.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';

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
    expect(await store.load(), isEmpty);
  });
}
