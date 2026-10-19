import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import '../platform/google_tasks_platform.dart';
import 'providers.dart';

/// [GoogleTasksSecrets] on the app's [SecretStore]: the user's OAuth client
/// (ID and secret) and the refresh token. Never settings JSON, SQLite, logs
/// or exports.
final class SecretStoreGoogleTasksSecrets implements GoogleTasksSecrets {
  /// Creates the adapter.
  SecretStoreGoogleTasksSecrets(SecretStore store)
    : store = ScopedSecretStore(store, namespace);

  /// The Google Tasks part of the device secret store (`gtasks.*`).
  final ScopedSecretStore store;

  /// Prefix of all Google Tasks keys in the device secret store.
  static const namespace = 'gtasks.';

  /// Key of the client ID (`gtasks.client_id`).
  static const clientIdKey = 'client_id';

  /// Key of the client secret (`gtasks.client_secret`).
  static const clientSecretKey = 'client_secret';

  /// Key of the refresh token (`gtasks.refresh_token`).
  static const refreshKey = 'refresh_token';

  @override
  Future<GoogleClient?> client() async {
    final id = await store.read(clientIdKey);
    final secret = await store.read(clientSecretKey);
    if (id == null || id.isEmpty || secret == null || secret.isEmpty) {
      return null;
    }
    return GoogleClient(id: id, secret: secret);
  }

  @override
  Future<void> saveClient(GoogleClient? client) async {
    if (client == null) {
      await store.delete(clientIdKey);
      await store.delete(clientSecretKey);
    } else {
      await store.write(clientIdKey, client.id);
      await store.write(clientSecretKey, client.secret);
    }
  }

  @override
  Future<String?> refreshToken() => store.read(refreshKey);

  @override
  Future<void> saveRefreshToken(String? token) =>
      token == null ? store.delete(refreshKey) : store.write(refreshKey, token);

  @override
  String toString() => 'SecretStoreGoogleTasksSecrets(<verborgen>)';
}

/// Client of the Tasks API; tests override it with `FakeGoogleTasksApi`.
final googleTasksApiProvider = Provider<GoogleTasksApi>(
  (ref) => HttpGoogleTasksApi(client: ref.watch(httpClientProvider)),
);

/// Google's token endpoint; tests override it with `FakeGoogleTasksApi`.
final googleOAuthProvider = Provider<GoogleOAuthApi>(
  (ref) => HttpGoogleOAuthApi(client: ref.watch(httpClientProvider)),
);

/// Where the Google client and refresh token live.
final googleTasksSecretsProvider = Provider<SecretStoreGoogleTasksSecrets>(
  (ref) => SecretStoreGoogleTasksSecrets(ref.watch(secretStoreProvider)),
);

/// Opens the login page in the browser; tests override it.
final googleBrowserProvider = Provider<GoogleBrowserOpener>(
  (ref) => const ChannelGoogleBrowserOpener(),
);

/// Starts the local server for the login redirect; tests override it.
final googleReceiverProvider = Provider<Future<RedirectReceiver> Function()>(
  (ref) => LoopbackReceiver.start,
);

/// The login flow of the settings page.
final googleTasksLoginProvider = Provider<GoogleTasksLogin>(
  (ref) => GoogleTasksLogin(
    ref.watch(googleOAuthProvider),
    ref.watch(googleTasksSecretsProvider),
    ref.watch(googleBrowserProvider),
    receiver: ref.watch(googleReceiverProvider),
  ),
);

/// The built Google Tasks integration, if it is registered (not in the demo
/// mode).
GoogleTasksIntegration? googleTasksIntegrationOf(
  Map<String, Integration> integrations,
) => switch (integrations['gtasks']) {
  final i? => switch (unwrapIntegration(i)) {
    final GoogleTasksIntegration g => g,
    _ => null,
  },
  null => null,
};
