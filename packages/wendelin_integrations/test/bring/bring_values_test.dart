import 'package:test/test.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';

void main() {
  test('BringAuth: JSON hin und zurück, ungültiges JSON → null', () {
    const full = BringAuth(
      userUuid: 'u',
      publicUuid: 'p',
      accessToken: 'a',
      refreshToken: 'r',
      defaultListUuid: 'l',
    );
    expect(BringAuth.fromJson(full.toJson()), full);
    expect(BringAuth.fromJson(full.toJson()).hashCode, full.hashCode);
    const minimal = BringAuth(userUuid: 'u', accessToken: 'a');
    expect(minimal.toJson(), {'userUuid': 'u', 'accessToken': 'a'});
    expect(BringAuth.fromJson(minimal.toJson()), minimal);
    expect(
      BringAuth.fromJson({
        'userUuid': 'u',
        'accessToken': 'a',
        'publicUuid': 3,
      }),
      minimal,
    );
    for (final bad in <Object?>[
      null,
      'x',
      {'userUuid': 'u'},
      {'accessToken': 'a'},
      {'userUuid': 1, 'accessToken': 'a'},
    ]) {
      expect(BringAuth.fromJson(bad), isNull, reason: '$bad');
    }
    expect(full == minimal, isFalse);
    final renewed = full.withTokens(accessToken: 'b');
    expect(renewed.refreshToken, 'r');
    expect(renewed.defaultListUuid, 'l');
    expect(renewed.publicUuid, 'p');
  });

  test('Wertgleichheit und toString', () {
    const l = BringList(uuid: 'u', name: 'Zuhause');
    expect(l, const BringList(uuid: 'u', name: 'Zuhause'));
    expect(l.hashCode, const BringList(uuid: 'u', name: 'Zuhause').hashCode);
    expect('$l', 'BringList(Zuhause)');

    const i = BringItem(name: 'Milch', spec: '1 l', uuid: 'x');
    expect(i, const BringItem(name: 'Milch', spec: '1 l', uuid: 'x'));
    expect(i == const BringItem(name: 'Milch', spec: '1 l'), isFalse);
    expect(
      i.hashCode,
      const BringItem(name: 'Milch', spec: '1 l', uuid: 'x').hashCode,
    );
    expect('$i', 'BringItem(Milch, 1 l)');
    expect('${const BringItem(name: 'Eier')}', 'BringItem(Eier)');
    expect(i.toJson(), {'name': 'Milch', 'spec': '1 l'});

    final a = BringItems(purchase: [i], recently: const []);
    final b = BringItems(purchase: [i], recently: const []);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a == BringItems(purchase: const [], recently: [i]), isFalse);
    expect('$a', 'BringItems(1 offen, 0 zuletzt)');
    expect(() => a.purchase.add(i), throwsUnsupportedError);
  });

  test('Standard-Client ohne eigenen HTTP-Client', () {
    final api = HttpBringApi();
    expect(api.apiKey, bringPublicApiKey);
    expect(api.country, 'DE');
    expect(bringApiBaseUrl.host, 'api.getbring.com');
  });
}
