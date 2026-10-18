import 'package:flutter_test/flutter_test.dart';
import 'package:wendelin/di/spotify.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/fakes.dart';

/// Key names of the Spotify secrets on the device: written down literally,
/// they must not change (an update would lose the login).
const _keys = {'spotify.client_id', 'spotify.session'};

void main() {
  final auth = SpotifyAuth(
    accessToken: 'geheim-access',
    refreshToken: 'geheim-refresh',
    expiresAt: DateTime.utc(2030),
  );

  test('Client-ID und Tokens liegen unter den festen Schlüsseln und '
      'überleben einen Rundlauf', () async {
    final store = InMemorySecretStore({'bring.email': 'fremd'});
    final s = SecretStoreSpotifySecrets(store);
    await s.saveClientId('0123456789abcdef0123456789abcdef');
    await s.saveAuth(auth);
    expect(await store.listKeys(), {..._keys, 'bring.email'});
    expect(await s.clientId(), '0123456789abcdef0123456789abcdef');
    final back = (await s.auth())!;
    expect(back.accessToken, 'geheim-access');
    expect(back.refreshToken, 'geheim-refresh');
    expect(back.expiresAt, auth.expiresAt);
  });

  test(
    'Löschen räumt nur Spotify, kaputte Daten zählen als abgemeldet',
    () async {
      final store = InMemorySecretStore({'bring.email': 'fremd'});
      final s = SecretStoreSpotifySecrets(store);
      await s.saveClientId('x');
      await s.saveAuth(auth);
      await s.saveAuth(null);
      await s.saveClientId(null);
      expect(await store.listKeys(), {'bring.email'});
      await store.write('spotify.session', 'kein json');
      expect(await s.auth(), isNull);
      await store.write('spotify.session', '{"accessToken":1}');
      expect(await s.auth(), isNull);
    },
  );

  test('toString verrät nichts', () {
    expect(
      SecretStoreSpotifySecrets(InMemorySecretStore()).toString(),
      isNot(contains('geheim')),
    );
  });
}
