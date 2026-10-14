import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wendelin_integrations/wendelin_integrations.dart';
import 'package:wendelin_storage/wendelin_storage.dart';

import 'app_settings.dart';
import 'providers.dart';

/// Namespace of the HTTP-tool secrets in the [SecretStore]. A secret
/// reference `r` of a definition is stored under `http_tool.r`, so an
/// HTTP tool can never read another secret (provider keys, Bring!).
const httpToolSecretNamespace = 'http_tool.';

/// [HttpToolSecrets] on the app's [SecretStore] (Android Keystore). Reads
/// only inside [httpToolSecretNamespace]. Passes `httpToolSecretsContract`.
final class SecretStoreHttpToolSecrets implements HttpToolSecrets {
  /// Creates the adapter.
  SecretStoreHttpToolSecrets(SecretStore store)
    : _scoped = ScopedSecretStore(store, httpToolSecretNamespace);

  final ScopedSecretStore _scoped;

  @override
  Future<String?> read(String secretRef) async {
    if (secretRef.isEmpty) return null;
    return _scoped.read(secretRef);
  }

  @override
  String toString() => 'SecretStoreHttpToolSecrets(<verborgen>)';
}

/// Settings key of the stored definitions (JSON of each, no secrets).
final httpToolsSetting = SettingKey<List<Map<String, Object?>>>(
  'http.tools',
  encode: (list) => list,
  decode: (json) {
    if (json is! List) throw const FormatException('http.tools: Liste');
    return [
      for (final e in json)
        e is Map<String, Object?>
            ? e
            : throw const FormatException('http.tools: Objekt erwartet'),
    ];
  },
  defaultValue: const [],
);

/// [HttpToolStore] on the app's settings (`http.tools`, no secrets).
final class SettingsHttpToolStore implements HttpToolStore {
  /// Creates the adapter.
  const SettingsHttpToolStore(this.settings);

  /// Where the definitions live.
  final SettingsRepository settings;

  @override
  Future<List<Map<String, Object?>>> read() async =>
      await settings.get(httpToolsSetting) ?? const [];

  @override
  Future<void> write(List<Map<String, Object?>> definitions) =>
      settings.set(httpToolsSetting, definitions);
}

/// [HttpToolSecretVault] on the namespace [httpToolSecretNamespace] of the
/// device [SecretStore].
final class SecretStoreHttpToolVault implements HttpToolSecretVault {
  /// Creates the adapter.
  SecretStoreHttpToolVault(SecretStore store)
    : _scoped = ScopedSecretStore(store, httpToolSecretNamespace);

  final ScopedSecretStore _scoped;

  @override
  Future<String?> read(String ref) => _scoped.read(ref);

  @override
  Future<void> write(String ref, String value) => _scoped.write(ref, value);

  @override
  Future<void> delete(String ref) => _scoped.delete(ref);

  @override
  Future<Set<String>> refs() => _scoped.listKeys();

  @override
  String toString() => 'SecretStoreHttpToolVault(<verborgen>)';
}

/// Builds the runner of the HTTP tools for a secret source (the editor's
/// test run passes secrets that are not saved yet). Tests override it
/// with a `MockClient` transport.
typedef HttpToolRunnerFactory = HttpToolRunner Function(
  HttpToolSecrets secrets,
);

/// Runner factory: pinned `dart:io` transport (ADR 0011 §3).
final httpToolRunnerFactoryProvider = Provider<HttpToolRunnerFactory>((ref) {
  final clock = ref.watch(clockProvider);
  return (secrets) => HttpToolRunner(
    transport: PinnedHttpToolTransport(),
    secrets: secrets,
    clock: clock,
  );
});

/// Stored secrets of the HTTP tools.
final httpToolSecretsProvider = Provider<HttpToolSecrets>(
  (ref) => SecretStoreHttpToolSecrets(ref.watch(secretStoreProvider)),
);

/// The user's HTTP-tool definitions.
final httpToolRepositoryProvider = Provider<HttpToolRepository>((ref) {
  final repository = HttpToolRepository(
    store: SettingsHttpToolStore(ref.watch(storageProvider).settings),
    secrets: SecretStoreHttpToolVault(ref.watch(secretStoreProvider)),
    ids: ref.watch(idGeneratorProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// The HTTP tools as user-defined integrations.
final httpToolSourceProvider = Provider<HttpToolSource>(
  (ref) => HttpToolSource(
    ref.watch(httpToolRepositoryProvider),
    ref.watch(httpToolRunnerFactoryProvider)(
      ref.watch(httpToolSecretsProvider),
    ),
  ),
);

/// Switches the integration of [definition] on before its first tool is
/// saved, so a newly created tool is usable at once (creating it is the
/// explicit setup, ADR 0012). An integration that is already registered
/// keeps the user's switch.
Future<void> enableHttpIntegrationIfNew(
  SettingsRepository settings,
  Set<String> registeredIds,
  HttpToolDefinition definition,
) async {
  final id = definition.sensitive
      ? HttpToolsIntegration.sensitiveId
      : HttpToolsIntegration.plainId;
  if (registeredIds.contains(id)) return;
  await settings.set(AppSettings.integrationEnabled(id), true);
}
