import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/spotify_platform.dart';
import 'core_providers.dart';

/// [SpotifySecrets] on the app's [SecretStore]: the user's Client-ID and the
/// tokens. Never settings JSON, SQLite, logs or exports.
final class SecretStoreSpotifySecrets implements SpotifySecrets {
  /// Creates the adapter.
  SecretStoreSpotifySecrets(SecretStore store)
    : store = ScopedSecretStore(store, namespace);

  /// The Spotify part of the device secret store (keys `spotify.*`).
  final ScopedSecretStore store;

  /// Prefix of all Spotify keys in the device secret store.
  static const namespace = 'spotify.';

  /// Key of the Client-ID (`spotify.client_id` on the device).
  static const clientIdKey = 'client_id';

  /// Key of the tokens, JSON of [SpotifyAuth] (`spotify.session`).
  static const sessionKey = 'session';

  @override
  Future<String?> clientId() => store.read(clientIdKey);

  @override
  Future<void> saveClientId(String? clientId) => clientId == null
      ? store.delete(clientIdKey)
      : store.write(clientIdKey, clientId);

  @override
  Future<SpotifyAuth?> auth() async {
    final raw = await store.read(sessionKey);
    if (raw == null) return null;
    try {
      return SpotifyAuth.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveAuth(SpotifyAuth? auth) => auth == null
      ? store.delete(sessionKey)
      : store.write(sessionKey, jsonEncode(auth.toJson()));

  @override
  String toString() => 'SecretStoreSpotifySecrets(<verborgen>)';
}

/// Spotify Web API; tests override it with `FakeSpotifyApi`.
final spotifyApiProvider = Provider<SpotifyApi>(
  (ref) => HttpSpotifyApi(client: ref.watch(httpClientProvider)),
);

/// Where the Spotify Client-ID and tokens live.
final spotifySecretsProvider = Provider<SecretStoreSpotifySecrets>(
  (ref) => SecretStoreSpotifySecrets(ref.watch(secretStoreProvider)),
);

/// Shows the Spotify login (Custom Tab); tests override it.
final spotifyAuthBrowserProvider = Provider<SpotifyAuthBrowser>(
  (ref) => const ChannelSpotifyAuthBrowser(),
);

/// Wakes the Spotify app when no device is active; tests override it.
final spotifyLauncherProvider = Provider<SpotifyAppLauncher>(
  (ref) => const IntentSpotifyLauncher(),
);

/// The phone's own names, to find its Spotify device; tests override it.
final spotifyHostDeviceProvider = Provider<SpotifyHostDevice>(
  (ref) => const ChannelSpotifyHostDevice(),
);

/// The login flow of the settings page.
final spotifyLoginProvider = Provider<SpotifyLogin>(
  (ref) => SpotifyLogin(
    ref.watch(spotifyApiProvider),
    ref.watch(spotifySecretsProvider),
    ref.watch(spotifyAuthBrowserProvider),
  ),
);

/// The built Spotify integration, if it is registered (not in the demo
/// mode).
SpotifyIntegration? spotifyIntegrationOf(
  Map<String, Integration> integrations,
) => switch (integrations['spotify']) {
  final i? => switch (unwrapIntegration(i)) {
    final SpotifyIntegration s => s,
    _ => null,
  },
  null => null,
};
