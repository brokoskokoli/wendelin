import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_core/wendelin_core.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'preferences.dart';
import 'providers.dart';

/// [TodoistSecrets] on the app's [SecretStore]: the personal API token only.
/// Never settings JSON, SQLite, logs or exports.
final class SecretStoreTodoistSecrets implements TodoistSecrets {
  /// Creates the adapter.
  SecretStoreTodoistSecrets(SecretStore store)
    : store = ScopedSecretStore(store, namespace);

  /// The Todoist part of the device secret store (keys `todoist.*`).
  final ScopedSecretStore store;

  /// Prefix of all Todoist keys in the device secret store.
  static const namespace = 'todoist.';

  /// Key of the token (`todoist.token` on the device).
  static const tokenKey = 'token';

  @override
  Future<String?> token() => store.read(tokenKey);

  /// Stores the token.
  Future<void> saveToken(String token) => store.write(tokenKey, token);

  /// Deletes the token.
  Future<void> clear() => store.delete(tokenKey);

  @override
  String toString() => 'SecretStoreTodoistSecrets(<verborgen>)';
}

/// Client of the Todoist API v1; tests override it with `FakeTodoistApi`.
final todoistApiProvider = Provider<TodoistApi>(
  (ref) => HttpTodoistApi(
    client: ref.watch(httpClientProvider),
    language: () => ref.read(languageProvider),
  ),
);

/// Where the Todoist token lives.
final todoistSecretsProvider = Provider<SecretStoreTodoistSecrets>(
  (ref) => SecretStoreTodoistSecrets(ref.watch(secretStoreProvider)),
);

/// The built Todoist integration, if it is registered (not in the demo
/// mode).
TodoistIntegration? todoistIntegrationOf(
  Map<String, Integration> integrations,
) => switch (integrations['todoist']) {
  final i? => switch (unwrapIntegration(i)) {
    final TodoistIntegration t => t,
    _ => null,
  },
  null => null,
};

/// Connects with [token]: checks it against the API first, then stores it.
/// Returns `null` on success, else the kind of failure (nothing is stored
/// then); the UI words it, no text carries the token.
Future<PortErrorKind?> todoistConnect({
  required TodoistApi api,
  required SecretStoreTodoistSecrets secrets,
  required String token,
}) async {
  try {
    await api.projects(token);
  } on PortException catch (e) {
    return e.kind;
  }
  await secrets.saveToken(token);
  return null;
}
